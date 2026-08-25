## Minimal tune-free grab/capture prober for the 0.7.8 baseline.
##
## Seats N baseline bots in the headless 0.7.8 sim, drives the SHIPPED
## `decide()` byte-identically (per-slot RNG isolation like runBot), and
## reports per-team grabs / captures / wins over a batch. Its only purpose is
## to prove the origin/main baseline is NOT blind on 0.7.8 (it reads the
## "<color> flag" labels the live server emits) — i.e. it actually steals and
## captures, unlike a heart-label reader on the same server.
##
## Usage:
##   nim c -d:release --opt:speed -o:/tmp/grabprobe.out \
##     players/baseline/eval/grabprobe.nim
##   /tmp/grabprobe.out --games 12 --seed 100 --ticks 10000

import std/[os, random, strutils, strformat]
import ./harness_engine

include "../baseline.nim"

type
  Driver = object
    bot: Bot
    client: ProtocolClient
    lastMask: uint8
    navBuilt: bool
    rng: Rand

when defined(idhash):
  # -d:idhash ONLY — the CONTROL-IDENTITY instrument. Two FNV-1a-64 rolling
  # hashes per episode:
  #   idMask = every emitted button mask, in strict (tick, slot) order. This is
  #            the policy's entire output channel; if it matches, the two
  #            binaries made the same decision on every frame of every seat.
  #   idTraj = every seat's ground-truth (x, y, hp, alive) after every advance.
  #            A mask hash alone cannot catch a divergence that starts in the
  #            engine, and a trajectory hash alone cannot localise one to the
  #            policy; together they do both.
  # Never compiled into a measurement build: the hash is control-proof only.
  var idMask: uint64 = 0xcbf29ce484222325'u64
  var idTraj: uint64 = 0xcbf29ce484222325'u64
  var idFrames = 0
  proc idMix(h: var uint64, v: int) =
    var x = cast[uint64](v)
    for b in 0 .. 7:
      h = h xor ((x shr (b * 8)) and 0xff'u64)
      h = h * 0x100000001b3'u64

proc newDriver(slot, team, episodeSeed: int): Driver =
  # ⭐⭐ RIG-FIDELITY FIX (2026-08-20) — see the long note on the same line in
  # harness.nim. `if team == 0: Red else: Blue` collapses green AND yellow to
  # Blue; the hosted policy seeds bot.team from SLOT PARITY, so green (engine
  # index 2) is Red in the field. The collapse gave green an inverted homeSign
  # on every 4-team episode this probe has ever run. `team mod 2` agrees with
  # the old expression exactly on 2-team boards ({0,1}), so nothing 2-team moves.
  let t = (if team mod 2 == 0: Red else: Blue)
  let role = roleForSeat(clamp(slot div 2, 0, 7), t)
  var tune = shippedCombatTune()
  # Isolate the two 2026-07-16 finish fixes (carrier home-stretch + thief chase).
  #   NOFIX=1        → strip the fixes from BOTH teams (mirror control).
  #   FIXTEAM=red    → only Red gets the fixes; Blue is stripped (seat-rotated A/B).
  #   FIXTEAM=blue   → only Blue gets them; Red stripped.
  # ⭐ spinCap RANGE FORK isolation (issue #8). shippedCombatTune() reads
  # NOSPINCAP / SPINRANGE from the process env, but the harness runs all 16
  # bots in ONE process — so without this the "A/B" is a mirror. SPINTEAM
  # picks which side gets the candidate traverse and RE-STAMPS the other side
  # back to plain v39, giving a deterministic, per-tick, seat-rotatable A/B.
  let spinTeam = getEnv("SPINTEAM")
  if spinTeam.len > 0:
    let mine = (spinTeam == "red" and t == Red) or (spinTeam == "blue" and t == Blue)
    if not mine:
      tune.spinCap = true
      tune.spinCapRangePx = Inf
  # ⭐ SHAPE A/B isolation (2026-08-14, the Hermes study). shippedCombatTune() reads
  # NOSHAPE from the PROCESS env and all 16 bots share one process, so a bare NOSHAPE=1
  # would strip both sides and the "A/B" would be a mirror — the same trap SPINTEAM and
  # AIMTEAM exist to avoid. SHAPETEAM=red|blue gives that side the one-runner shaping and
  # RE-STAMPS the other side back to the six-attacker push, giving a deterministic,
  # seat-rotatable head-to-head out of ONE frozen binary.
  # ⭐⭐⭐ wlead ISOLATION (2026-08-20). shippedCombatTune() reads NOWLEAD /
  # WLEADTICKS / WLEADSELF from the PROCESS env and this probe runs all 16 bots
  # in ONE process, so a bare NOWLEAD=1 is a MIRROR, not an A/B. WLEADTEAM keys
  # on the RAW ENGINE TEAM INDEX (0..3) — never Red/Blue, which collapses three
  # teams into one on a 4-team board and has compared 4 seats against 12 before
  # — and RE-STAMPS every other team back to the shipped-off control.
  # An out-of-range WLEADTEAM (e.g. 9) is the all-off control arm.
  # ⚠️ `when compiles` (v59 integration): WITHOUT this guard the file stops
  # dropping into a PRE-MERGE tree, which breaks the identity-oracle pattern
  # every other lane in this bundle depends on — the two arms of an identity
  # proof must differ in baseline.nim ONLY, so the SAME rig file has to build
  # against both policies. Every sibling isolation block here already carries the
  # guard; this one was the exception, and it is what stopped the 702701e-side
  # oracle from compiling.
  when compiles(tune.windupLead):
    let wleadTeam = getEnv("WLEADTEAM")
    if wleadTeam.len > 0 and team != parseInt(wleadTeam):
      tune.windupLead = 0.0
      tune.windupSelfLead = 0.0
  let shapeTeam = getEnv("SHAPETEAM")
  if shapeTeam.len > 0:
    tune.oneRunner = (shapeTeam == "red" and t == Red) or
                     (shapeTeam == "blue" and t == Blue)
  # ⭐⭐ MID-QUAD BREAK isolation (2026-08-14). Same problem as SPINTEAM: this
  # harness seats OUR policy on all 16 slots, so a whole-batch env flip is a
  # MIRROR — both sides move together and per-seat K/D is symmetric by
  # construction, which is exactly the "no-op A/B" tell. SEAT4TEAM arms the
  # package on ONE colour: roleForSeat reads it directly (a pure function cannot
  # be re-stamped) and the two tune levers are stripped from the other colour
  # here, so all three move as one arm. ⚠️ SEAT-ROTATE IT — run red-armed and
  # blue-armed and average, or you have measured the side.
  let seat4Team = getEnv("SEAT4TEAM")
  if seat4Team.len > 0:
    let armed = (seat4Team == "red" and t == Red) or
                (seat4Team == "blue" and t == Blue)
    if not armed:
      tune.roleSep = false
      tune.midSpread = false
  let fixTeam = getEnv("FIXTEAM")
  let stripFix =
    getEnv("NOFIX") == "1" or
    (fixTeam == "red" and t == Blue) or
    (fixTeam == "blue" and t == Red)
  # PBMARGIN=1 narrows the strip to PLAYBOOK ONLY, so the "control" seat keeps the
  # full champion minus the play layer. That measures the MARGINAL contribution of
  # the playbook on top of the shipped champion (the decision-relevant question now
  # that playbook is in shippedCombatTune), rather than champion-vs-bare-core.
  let pbMargin = getEnv("PBMARGIN") == "1"
  if stripFix:
    tune.playbook = false
    if not pbMargin:
      tune.carrierHomeStretch = false
      tune.chaseThief = false
      tune.cornerPreAim = false
      tune.sentryDisplace = false
      tune.topBias = false
  # Per-lever isolation: NOCHASE strips only the behavioral thief-chase lever
  # (leaving the pure carrier-pathing finish fix on) for whichever team holds
  # the fix, so a seat-rotated pair attributes the two levers separately.
  if getEnv("NOCHASE") == "1" and not stripFix:
    tune.chaseThief = false
  if getEnv("NOHOMESTRETCH") == "1" and not stripFix:
    tune.carrierHomeStretch = false
  # CORNER PRE-AIM isolation: NOCORNER strips only the wall-aim fix for the fixed
  # team, so a seat-rotated pair attributes the aim lever separately. Isolating
  # it alone (NOCHASE+NOHOMESTRETCH set too) measures its hit-rate effect clean.
  if getEnv("NOCORNER") == "1" and not stripFix:
    tune.cornerPreAim = false
  if getEnv("NOSENTRY") == "1" and not stripFix:
    tune.sentryDisplace = false
  if getEnv("NOTOPBIAS") == "1" and not stripFix:
    tune.topBias = false
  # PLAYBOOK is now ON in shippedCombatTune. NOPLAYBOOK strips only the play layer
  # for the fixed team, so a seat-rotated pair isolates the observation-triggered
  # plays against an otherwise-identical control that keeps every other lever.
  if getEnv("NOPLAYBOOK") == "1" and not stripFix:
    tune.playbook = false
  # ⛔ GRABTIMING — DEAD KNOB, removed 2026-08-20 (lever-liveness audit).
  # `grabTiming` has ZERO read sites in baseline.nim: smartGrab superseded the
  # hard-threshold gates and their bodies went with them. This "liveness check"
  # was checking a build that is byte-identical to its control.
  if getEnv("GRABTIMING").len > 0:
    quit("⛔ GRABTIMING is a DEAD knob: grabTiming has no read site in " &
      "baseline.nim (superseded by smartGrab). This run would have been a " &
      "guaranteed null.", 2)
  # HOLDLINE=1 / GRABGATE=1 (2026-07-22, the h006 counters) turn ON the anti-over-extend
  # rally / numbers-gated pocket open (neither in shippedCombatTune) so the not-blind
  # oracle can confirm each build still grabs + has decisive games before any A/B.
  # Applies to BOTH teams (a mirror liveness check).
  if getEnv("HOLDLINE") == "1":
    tune.holdLine = true
  # ⛔ GRABGATE — DEAD KNOB, removed 2026-08-20. Same cause as GRABTIMING.
  if getEnv("GRABGATE").len > 0:
    quit("⛔ GRABGATE is a DEAD knob: grabGate has no read site in " &
      "baseline.nim (superseded by smartGrab). This run would have been a " &
      "guaranteed null.", 2)
  # ⭐ GV40 AIM A/B (2026-08-06). shippedCombatTune() reads OLDAIM from the
  # process env and all 16 bots share ONE process, so a bare OLDAIM=1 would arm
  # BOTH sides and the "A/B" would be a mirror — the same trap SPINTEAM and
  # RALLYTEAM exist to avoid. AIMTEAM=red|blue gives that side the SHIPPED-
  # BROKEN GV36 slot servo and leaves the other on the GV40 continuous fix,
  # giving a deterministic, seat-rotatable head-to-head from one frozen binary.
  let aimTeam = getEnv("AIMTEAM")
  if aimTeam.len > 0:
    tune.aimLegacy = (aimTeam == "red" and t == Red) or
                     (aimTeam == "blue" and t == Blue)
  # ⭐⭐ FFA4 PACKAGE isolation (2026-08-17, the integration gate). The four ffa4
  # levers are read from the PROCESS env by shippedCombatTune(), and this rig
  # seats every slot in ONE process — so a bare NOxxx=1 strips all four teams
  # and the "A/B" is a MIRROR (the SPINTEAM/SEAT4TEAM/AIMTEAM trap). FFA4TEAM
  # re-stamps the flags OFF for the unarmed side, giving an armed-vs-control
  # comparison inside the SAME episode against identical opponents.
  # ⚠️ In THIS rig `t` is Red for engine team 0 only and Blue for teams 1..3
  # (see the `if team == 0` above), so FFA4TEAM=red arms ONE of four teams and
  # controls three — the closest local analogue of the hosted field, where only
  # we carry the package. FFA4TEAM=blue inverts it (three armed, one control).
  # Per-lever arms (FFA4ONLY) isolate one lever on the armed side.
  # `when compiles` so this SAME file drops into a pre-merge tree (the d045bb5
  # fingerprint control) where the four tune fields do not exist yet.
  when compiles(tune.ffaMedSee):
   let ffa4Team = getEnv("FFA4TEAM")
   if ffa4Team.len > 0:
     let armed = (ffa4Team == "red" and t == Red) or
                 (ffa4Team == "blue" and t == Blue)
     let only = getEnv("FFA4ONLY")          # "", or one of L1/L2/L3/L4
     if not armed:
       tune.ffaMedSee = false
       tune.lastLifeGuard = false
       tune.tradeGate = false
     elif only.len > 0:
       # L4 (flagClock) is RETIRED — see its tombstone in baseline.nim. FFA4ONLY=L4
       # now arms nothing, which is the correct answer, not a bug.
       tune.ffaMedSee = only == "L1"
       tune.tradeGate = only == "L2"
       tune.lastLifeGuard = only == "L3"
  # ⭐⭐ ffa4 lives audit (2026-08-17) TEAM ISOLATION. shippedCombatTune() reads
  # NOFFAMEDSEE/NOLASTLIFE from the process env and all numPlayers bots share
  # ONE process, so a bare NOxxx=1 would strip every team and the "A/B" would
  # be a mirror — the same trap SPINTEAM/SHAPETEAM/SEAT4TEAM exist to avoid.
  # Both levers are GameTeams>2-gated already; on a 4-team board
  # FFAMEDTEAM=<n>/LASTLIFETEAM=<n> arms ONLY engine team index n (0..3) and
  # strips every other team, giving a deterministic, team-rotatable A/B from
  # one binary. Uses the raw team INDEX param, not red/blue: `t` above
  # collapses every non-zero team to Blue on a >2-team board.
  let ffaMedTeam = getEnv("FFAMEDTEAM")
  if ffaMedTeam.len > 0:
    tune.ffaMedSee = team == parseInt(ffaMedTeam)
  let lastLifeTeam = getEnv("LASTLIFETEAM")
  if lastLifeTeam.len > 0:
    tune.lastLifeGuard = team == parseInt(lastLifeTeam)
  # ⭐⭐⭐ kitSel (FEASIBILITY-AWARE KIT SELECTOR, 2026-08-20) TEAM ISOLATION.
  # shippedCombatTune() reads KITSEL from the PROCESS env and all numPlayers bots
  # run in ONE process, so a bare KITSEL=1 arms every team and measures a MIRROR —
  # the same trap SPINTEAM / SEAT4TEAM / FFAMEDTEAM / WUFFTEAM exist to avoid.
  # KITSELTEAM=<n> arms ONLY raw engine team index n and strips every other team.
  # ⚠️ RAW INDEX, never red/blue: `t` above collapses every non-zero team to Blue
  # on a >2-team board, so a colour-named knob would compare a 4-seat arm against
  # a 12-seat arm — which has actually happened here before.
  # Accepts a COMMA LIST ("0,2") so one run can arm half the board and still be
  # paired against a pure control arm; KITSELTEAM=9 (any out-of-range index) IS
  # that control arm — same binary, same env shape, the two runs differ in ONE
  # integer. ⚠️ Seat is NOT exchangeable on this board (8.9/8.9/23.2/58.9% win
  # share by slot block), so every team must be compared against ITSELF.
  # ⚠️ Unlike ffaMedSee/lastLifeGuard, kitSel is NOT GameTeams>2-gated at its call
  # site — the phantom address is wrong on 2-team generated boards too — so this
  # knob is meaningful on a 2-team rig as well, and a 2-team run is NOT a
  # guaranteed no-op the way the ffa4 package's is.
  when compiles(tune.kitSel):
    let kitSelTeam = getEnv("KITSELTEAM")
    if kitSelTeam.len > 0:
      var kitSelArmed = false
      for part in kitSelTeam.split(','):
        let p = part.strip()
        if p.len > 0 and team == parseInt(p): kitSelArmed = true
      # ⚠️ ASSIGNMENT, never an OR. KITSELTEAM=<n> must arm team n and DISARM
      # every other team; an out-of-range KITSELTEAM=9 must therefore force the
      # lever OFF everywhere and give a pure all-control arm. NOKITSEL stays
      # authoritative over the isolation knob — a force-revert has to revert, or
      # "roll it back by re-running with different env" is a lie (the NOWUFF /
      # NONADEFF precedent, both of which were merge-fixed for exactly this).
      tune.kitSel = kitSelArmed and getEnv("NOKITSEL").len == 0
  # ⭐⭐⭐ wuff (WINDUP FRIENDLY-FIRE VETO, 2026-08-19) TEAM ISOLATION.
  # shippedCombatTune() reads WUFF from the PROCESS env and all bots run in ONE
  # process, so a bare WUFF=1 arms every team and measures a MIRROR — the same
  # trap SPINTEAM / SEAT4TEAM / FFAMEDTEAM exist to avoid. WUFFTEAM=<n> arms ONLY
  # raw engine team index n and strips every other team. RAW INDEX, never
  # red/blue: `t` above collapses every non-zero team to Blue on a >2-team board,
  # and this board has four bases.
  #
  # Accepts a COMMA LIST ("0,2") so one run can arm half the board and still be
  # paired against a pure control arm; WUFFTEAM=9 (any out-of-range index) IS
  # that control arm — same binary, same env shape, the two runs differ in ONE
  # integer. ⚠️ Seat is NOT exchangeable on this board (8.9/8.9/23.2/58.9% win
  # share by slot block), so every team must be compared against ITSELF.
  let wuffTeam = getEnv("WUFFTEAM")
  if wuffTeam.len > 0:
    var wuffArmed = false
    for part in wuffTeam.split(','):
      let p = part.strip()
      if p.len > 0 and team == parseInt(p): wuffArmed = true
    # ⚠️ ASSIGNMENT, never an OR — and that matters MORE now the lever ships
    # DEFAULT ON. WUFFTEAM=<n> must arm team n and DISARM every other team; an
    # out-of-range WUFFTEAM=9 must therefore force the lever OFF everywhere and
    # give a pure all-control arm. If this were written as `tune.windupFf =
    # tune.windupFf or armed` the flipped default would leave every team hot and
    # silently turn every future A/B into a MIRROR. Verified empirically, not just
    # read: WUFFTEAM=9 prints windupFf=0 on all four LEVERSTATE rows.
    # NOWUFF stays authoritative over the isolation knob: a force-revert has to
    # revert, or "roll it back by re-running with different env" is a lie.
    tune.windupFf = wuffArmed and getEnv("NOWUFF").len == 0

  # ⭐⭐ AoE FRIENDLY-FIRE VETO (2026-08-19) TEAM ISOLATION. shippedCombatTune()
  # reads NADEFF / SPRAYFF from the process env and all numPlayers bots share ONE
  # process, so a bare NADEFF=1 arms every team and the "A/B" is a MIRROR — the
  # same trap CQBLOSTEAM / FFAMEDTEAM / SPINTEAM exist to avoid. NADEFFTEAM=<n>
  # arms ONLY engine team index n and strips every other team; SPRAYFFTEAM does
  # the same for the cone. Raw team INDEX, not red/blue: `t` above collapses
  # every non-zero team to Blue on a >2-team board, so red/blue cannot name one
  # of four seats. An OUT-OF-RANGE index (e.g. 9) is the all-CONTROL arm — same
  # binary, same env shape, the two runs differ in ONE integer.
  # Both accept a COMMA LIST ("0,2") so one run can arm half the board and still
  # be paired against a pure NADEFFTEAM=9 control: seat is NOT exchangeable here
  # (the mid-quad finding), so every team has to be measured against ITSELF.
  # `when compiles` so this same file still drops into a pre-merge tree.
  proc aoeArmed(envName: string, team: int): bool =
    let raw = getEnv(envName)
    if raw.len == 0: return false
    for part in raw.split(','):
      let p = part.strip()
      if p.len > 0 and team == parseInt(p): return true
    false
  # ⚠️ MERGE FIX (2026-08-19): the force-revert stays authoritative over the
  # isolation knob, exactly as NOWUFF does over WUFFTEAM. Without this a
  # NONADEFF=1 run that also carried NADEFFTEAM would arm the lever it was asked
  # to revert, and "roll back by re-running with different env" would be a lie.
  when compiles(tune.nadeFfVeto):
    if getEnv("NADEFFTEAM").len > 0:
      tune.nadeFfVeto = aoeArmed("NADEFFTEAM", team) and getEnv("NONADEFF").len == 0
  when compiles(tune.sprayFfVeto):
    if getEnv("SPRAYFFTEAM").len > 0:
      tune.sprayFfVeto = aoeArmed("SPRAYFFTEAM", team) and getEnv("NOSPRAYFF").len == 0
  # ⭐⭐⭐ RAID FRAME (2026-08-20) TEAM ISOLATION. shippedCombatTune() reads
  # NORAIDFRAME from the PROCESS env and all numPlayers bots share ONE process,
  # so a whole-batch flip is a MIRROR — both sides move together and every
  # per-seat metric comes out symmetric by construction, which is the "no-op A/B"
  # tell. RAIDFRAMETEAM=<n>[,<n>] arms ONLY those RAW ENGINE TEAM INDICES 0..3.
  # ⚠️ RAW INDEX, NEVER THE Red/Blue ENUM. `t` above collapses every non-zero
  # team to Blue on a >2-team board, so a colour-named isolation on a 4-team
  # board historically compared a 4-SEAT arm against a 12-SEAT arm and called it
  # an A/B. An OUT-OF-RANGE index (e.g. RAIDFRAMETEAM=9) is the pure all-CONTROL
  # arm: same binary, same env shape, the two runs differ in ONE integer.
  # ⚠️ ASSIGNMENT, never an OR — the lever ships DEFAULT ON, so an OR would leave
  # every team hot and silently make the "isolated" arm a mirror.
  # NORAIDFRAME stays authoritative on top: a force-revert has to revert, or
  # "roll it back by re-running with different env" is a lie.
  # ⚠️ Seat is NOT exchangeable on this board (8.9/8.9/23.2/58.9% win share by
  # slot block), so every team must be compared against ITSELF, arm vs arm.
  when compiles(tune.raidFrame):
    if getEnv("RAIDFRAMETEAM").len > 0:
      tune.raidFrame = aoeArmed("RAIDFRAMETEAM", team) and
                       getEnv("NORAIDFRAME").len == 0
  # ⭐⭐⭐ TGEV (the ffa4 TRADE-EV GATE, 2026-08-20) TEAM ISOLATION.
  # shippedCombatTune() reads TGEV/TGSQ/TGCON/TGHP from the PROCESS env and every
  # seat in this rig runs in ONE process, so a bare TGEV=1 arms all four teams and
  # the "A/B" is a MIRROR — the trap WUFFTEAM / NADEFFTEAM / FFAMEDTEAM / SPINTEAM
  # all exist to avoid. TGEVTEAM=<n>[,<n>] arms ONLY raw engine team index n and
  # strips every other team.
  #
  # RAW TEAM INDEX, never red/blue: `t` above collapses every non-zero team into
  # Blue on a >2-team board, and this board has four bases. Comma list so one run
  # can arm half the board; an OUT-OF-RANGE index (TGEVTEAM=9) is the pure
  # all-CONTROL arm — same binary, same env shape, the two runs differ in ONE
  # integer. ⚠️ Seat is NOT exchangeable here (8.9/8.9/23.2/58.9% win share by
  # slot block), so every team must be compared against ITSELF across arms.
  #
  # ⚠️ ASSIGNMENT, never an OR: TGEVTEAM=9 has to print 0 on all four LEVERSTATE
  # rows or the control arm is silently hot. And each NOxxx stays authoritative
  # over the isolation knob, exactly as NOWUFF does over WUFFTEAM — otherwise
  # "roll it back by re-running with different env" is a lie.
  # The four sub-flags are structurally unreachable without tradeGate itself, so
  # the knob moves all of them together and the per-lever arms stay the NOxxx.
  # ⭐⭐⭐ VOLUMETEAM (2026-08-20) — TEAM ISOLATION FOR THE NOW-DEFAULT-ON tradeGate.
  # shippedCombatTune() reads NOVOLUME from the PROCESS env and every seat in this
  # rig runs in ONE process, so a bare NOVOLUME=1 strips all four teams and the
  # "A/B" is a MIRROR — the trap WUFFTEAM / NADEFFTEAM / FFAMEDTEAM / SPINTEAM all
  # exist to avoid. VOLUMETEAM=<n>[,<n>] arms ONLY raw engine team index n and
  # strips every other team. RAW INDEX, never red/blue: `t` above collapses every
  # non-zero team into Blue on a >2-team board and this board has four bases.
  #
  # ⚠️⚠️ THE INVERSION, RE-CHECKED NOW THE DEFAULT IS ON. This must be an
  # ASSIGNMENT, never an OR. With the lever hot by default, `tune.tradeGate =
  # tune.tradeGate or armed` would leave every team armed and silently turn every
  # future A/B into a mirror — the exact bug WUFFTEAM's comment warns about, and
  # the reason that comment exists. An OUT-OF-RANGE index (VOLUMETEAM=9) must
  # therefore force the lever OFF on ALL FOUR teams and give a pure control arm.
  # Verified empirically on the TGSTATE rows, not read off the source.
  # NOVOLUME stays authoritative over the isolation knob, or "roll it back by
  # re-running with different env" is a lie.
  if getEnv("VOLUMETEAM").len > 0:
    tune.tradeGate = aoeArmed("VOLUMETEAM", team) and getEnv("NOVOLUME").len == 0
  # TGEVTEAM (the EXTENSION package: square bar / contest term / hp symmetry) is
  # applied AFTER VOLUMETEAM and overrides it for tradeGate, since the three
  # sub-flags are structurally unreachable without the parent gate.
  when compiles(tune.tradeGateSquare):
    if getEnv("TGEVTEAM").len > 0:
      let tgArmed = aoeArmed("TGEVTEAM", team)
      tune.tradeGate = tgArmed and getEnv("NOVOLUME").len == 0
      tune.tradeGateSquare = tgArmed and getEnv("NOTGSQ").len == 0
      tune.tradeGateContest = tgArmed and getEnv("NOTGCON").len == 0
      tune.tradeGateSelfHp = tgArmed and getEnv("NOTGHP").len == 0
  # ⭐⭐⭐ SPRAY CONE GEOMETRY (2026-08-20) TEAM ISOLATION. Identical shape and
  # identical reasoning: `team` here is the RAW ENGINE TEAM INDEX 0..3, never the
  # Red/Blue enum — `t` collapses every non-zero team to Blue on a >2-team board,
  # so a colour-named knob once compared a 4-seat arm against a 12-seat one. An
  # out-of-range index (SPRAYCONETEAM=9) is the pure all-CONTROL arm: same binary,
  # same env shape, the two runs differ in ONE integer. ASSIGNMENT, never an OR —
  # both levers ship DEFAULT ON, so an OR would leave every team hot and turn the
  # A/B into a mirror. The NOxxx force-revert stays authoritative over the
  # isolation knob, matching NOWUFF/WUFFTEAM.
  when compiles(tune.sprayConeFire):
    if getEnv("SPRAYCONETEAM").len > 0:
      tune.sprayConeFire = aoeArmed("SPRAYCONETEAM", team) and
        getEnv("NOSPRAYCONE").len == 0
  when compiles(tune.sprayFireFirst):
    if getEnv("SPRAYFIRSTTEAM").len > 0:
      tune.sprayFireFirst = aoeArmed("SPRAYFIRSTTEAM", team) and
        getEnv("NOSPRAYFIRST").len == 0
  # ⭐⭐⭐ ONE LOCK OWNER (2026-08-20) TEAM ISOLATION. lockOne used to be
  # `getEnv("NOLOCKONE")` read DIRECTLY inside decide() — process-wide and
  # COMMON-MODE across every bot in this one process, so no rig, this one
  # included, could ever isolate it (see the "lockOne IS NOT IN THIS LIST AND
  # CANNOT BE" note this comment replaces, in harness.nim's V59BUNDLE block).
  # Migrated into CombatTune, it takes the identical shape as every other
  # post-migration lever here: `team` is the RAW ENGINE TEAM INDEX 0..3, never
  # the Red/Blue enum (`t` collapses every non-zero team to Blue on a >2-team
  # board, so a colour-named knob once compared a 4-seat arm against a
  # 12-seat one). LOCKONETEAM=<n>[,<n>] arms ONLY those team indices; an
  # out-of-range index (LOCKONETEAM=9) is the pure all-CONTROL arm — same
  # binary, same env shape, the two runs differ in ONE integer. ASSIGNMENT,
  # never an OR — the lever ships DEFAULT ON, so an OR would leave every team
  # hot and silently turn the "isolated" arm into a mirror. NOLOCKONE stays
  # authoritative over the isolation knob, matching NOWUFF/WUFFTEAM.
  when compiles(tune.lockOne):
    if getEnv("LOCKONETEAM").len > 0:
      tune.lockOne = aoeArmed("LOCKONETEAM", team) and
        getEnv("NOLOCKONE").len == 0
  result.bot = Bot(slot: slot, team: t, role: role, tune: tune)
  result.bot.resetTransient()
  result.client = initProtocolClient()
  result.lastMask = 0xff'u8
  result.navBuilt = false
  result.rng = initRand(slot * 7919 + 1 + episodeSeed * 1_000_003)

var maskFnv: uint64 = 0xcbf29ce484222325'u64
  ## ⭐ CONTROL-IDENTITY: FNV-1a offset basis. Folded once per emitted mask, in
  ## (tick, slot) order because the harness drives the seats in slot order inside
  ## each tick. Printed at the end of a batch; two builds that agree on this
  ## number produced the same mask AND the same trajectory on every frame.
var maskFrames = 0

proc frame(driver: var Driver, packet: string): uint8 =
  let bot = driver.bot
  let client = driver.client
  if not client.feedInProcessPacket(packet):
    return driver.lastMask
  let adv = max(1, client.frameAdvance)
  bot.tick += adv
  bot.estAim = floorMod(bot.estAim + bot.rotSign * AimRate * adv, AimBrads)
  if not client.mapCameraReady:
    bot.resetTransient()
    return driver.lastMask
  if not driver.navBuilt and client.walkabilityReady:
    bot.buildNavGrid(client)
    driver.navBuilt = true
  randState() = driver.rng
  result = bot.decide(client)
  driver.rng = randState()
  driver.lastMask = result
  # ── ⭐ CONTROL-IDENTITY HASH (2026-08-20). An FNV-1a fold over EVERY emitted
  # mask in (tick, slot) order plus the seat's own position — the trajectory, not
  # just the decision. Two binaries that agree here agreed on every frame of every
  # episode, which is the only proof that a lever's NO* opt-out is a true revert
  # and not merely a similar-looking outcome. Unconditional and free: one xor and
  # one multiply per frame, and it is never read by any decision.
  maskFnv = maskFnv xor uint64(result)
  maskFnv = maskFnv * 0x100000001B3'u64
  maskFnv = maskFnv xor uint64(bot.tick and 0xffff)
  maskFnv = maskFnv * 0x100000001B3'u64
  maskFnv = maskFnv xor uint64(bot.slot)
  maskFnv = maskFnv * 0x100000001B3'u64
  maskFnv = maskFnv xor cast[uint64](int64(bot.lastPos.x * 64.0))
  maskFnv = maskFnv * 0x100000001B3'u64
  maskFnv = maskFnv xor cast[uint64](int64(bot.lastPos.y * 64.0))
  maskFnv = maskFnv * 0x100000001B3'u64
  inc maskFrames

when defined(roleprobe):
  # ── ⭐⭐ MID-QUAD PROBE (grabprobe side). The finding is GEOMETRIC — four of
  # eight seats in the mid family, one mid role dealt twice, four bodies in one
  # corridor — so the numbers that can move on a mirror rig are per-seat K/D
  # (with SEAT4TEAM arming one colour) and TEAMMATE SEPARATION. Win rate on a
  # mirror cannot move by construction and is not scored here.
  #
  # ⚠️ SEPARATION IS TAKEN FROM GROUND TRUTH (-d:rwtruth slotTruth), never from
  # a bot's own fogged belief about where its mates are: a probe that counts
  # what the bot BELIEVES is not the field metric.
  const
    RpSampleEvery = 20        # ticks between separation samples (~cheap, and far
                              # longer than one engagement so samples are not
                              # autocorrelated into a fake n)
    RpNadePairPx = 120.0      # ONE grenade catches BOTH: GrenadeBlastRadius is 52
                              # and the check is body-box based, so a pair inside
                              # ~2*(52+half) can be taken by a single blast. This
                              # is the mirror analogue of the field stat this
                              # package targets (58.4% of enemy nade impacts that
                              # damaged us caught 2+ of ours).
    RpTightPairPx = 60.0      # dead-on-top-of-each-other, the hard bunching case
  var
    rpKills, rpDeaths: array[2, array[8, int]]   # per (team, teamSeat)
    rpEps: array[2, array[8, int]]               # episodes the seat appeared in
    rpPairAll, rpPairNade, rpPairTight: array[2, int]  # sampled unordered pairs
    rpBodyAll, rpBodyNade: array[2, int]         # sampled live bodies / with a
                                                 # mate inside one blast
    rpYSpreadSum: array[2, float]                # Σ stdev of live-teammate y
    rpYSpreadN: array[2, int]
    # ⭐ FRIENDLY FIRE, batch totals. Not split by colour on purpose: this rig is
    # a MIRROR, so in the symmetric arms the own-colour rate is a property of the
    # ARM, not of a side. (With SEAT4TEAM armed the sides differ — the per-seat
    # K/D table is where that split is read.)
    rpKillsAll, rpFfKills, rpFfGun, rpFfNade, rpFfSpray: int
    rpDmgAll, rpFfDmg: int

  proc rpSample(engine: EvalEngine, players: int) =
    ## One ground-truth separation sample over every live body, bucketed by team.
    var xs, ys: array[4, seq[float]]
    for s in 0 ..< players:
      let tr = engine.slotTruth(s)
      if not tr.alive: continue
      if tr.team notin 0 .. 3: continue
      xs[tr.team].add tr.x
      ys[tr.team].add tr.y
    for tm in 0 .. 1:
      let n = xs[tm].len
      if n == 0: continue
      var nearFor = newSeq[bool](n)
      for i in 0 ..< n:
        for j in i + 1 ..< n:
          let dx = xs[tm][i] - xs[tm][j]
          let dy = ys[tm][i] - ys[tm][j]
          let d = sqrt(dx * dx + dy * dy)
          inc rpPairAll[tm]
          if d <= RpNadePairPx:
            inc rpPairNade[tm]
            nearFor[i] = true
            nearFor[j] = true
          if d <= RpTightPairPx: inc rpPairTight[tm]
      for i in 0 ..< n:
        inc rpBodyAll[tm]
        if nearFor[i]: inc rpBodyNade[tm]
      if n >= 2:
        var m = 0.0
        for y in ys[tm]: m += y
        m /= n.float
        var v = 0.0
        for y in ys[tm]: v += (y - m) * (y - m)
        rpYSpreadSum[tm] += sqrt(v / (n - 1).float)
        inc rpYSpreadN[tm]

when defined(lifeprobe):
  # ⭐⭐ ffa4 LIVES PROBE (2026-08-17). Two field-shaped metrics nothing else in
  # this harness computes, PER REAL TEAM COLOR (0..3, engine.teamOfSlot):
  #   "lives spent by half-time" — Σ over a team's seats of (3 - livesNow),
  #     sampled at tick == ticks div 2 (or at game end, whichever comes
  #     first, so a short episode still contributes). GROUND TRUTH via
  #     slotLifeState, never the bot's own fogged perception.
  #   "P(all 4 slots eliminated)" — episodes ending with every seat on the
  #     team at lives==0 and not alive.
  # P(escape|hp==1) and medkits/episode reuse the EXISTING tune-independent
  # wbprobe/msprobe globals already built into baseline.nim (msHeals/
  # wbHp1Heals/wbHp1Deaths) — a before/after MIRROR run pair (candidate vs
  # NOFFAMEDSEE=1 NOLASTLIFE=1) is the A/B for those two; they just had no
  # report wired to a harness before now (see the report block below).
  var lpEpisodes: array[4, int]
  var lpSeatsPerTeam: array[4, int]
  var lpHalfSpentSum: array[4, float]
  var lpFinalAllElim: array[4, int]

when defined(wuffprobe):
  # ⭐⭐⭐ wuff futility-bound cross-run state (grabprobe side).
  var wuffOffHist: array[9, int]   # (botTick - triggerTick) offsets, -4..+4, for
                                   # every released gun shot whose trigger frame
                                   # was found in the policy ledger. A single
                                   # sharp mode PROVES the two clocks align; a
                                   # smear means the join is unreliable and the
                                   # bound below must not be believed.
  var wuffFfNoPull = 0             # friendly-fire impacts whose trigger frame was
                                   # NOT in the ledger at all — a gun shot pulled
                                   # from OUTSIDE the engage branch (the ambush /
                                   # arc-breach forks also set wantFire), i.e.
                                   # OUT OF THIS LEVER'S REACH by construction.

when defined(doorprobe):
  var engineTeamOfSlot: array[32, int]   # real team index per slot (4-team safe)

  proc dpStat(v: seq[float]): (float, float) =
    ## mean, sample stdev.
    if v.len == 0: return (0.0, 0.0)
    var m = 0.0
    for x in v: m += x
    m /= v.len.float
    if v.len < 2: return (m, 0.0)
    var s = 0.0
    for x in v: s += (x - m) * (x - m)
    (m, sqrt(s / (v.len - 1).float))

  proc dpEntryLine(tag: string) =
    ## ⚠️ Printed AFTER EVERY GAME and flushed. This rig runs ~12 min/game under
    ## fleet load and the summary only exists at process exit, so a starved or
    ## killed run used to yield NOTHING. Cumulative, so any partial run is still
    ## a usable measurement — it just has fewer entries behind it.
    for tm in 0 .. 1:
      var allY, subY, subD: seq[float]
      for st in 0 .. 7:
        for i in 0 ..< dpEntryN[tm][st]:
          allY.add dpEntryY[tm][st][i]
          if st <= 3: subY.add dpEntryY[tm][st][i]
        if st <= 3:
          for i in 0 ..< dpDoorN[tm][st]: subD.add dpDoorY[tm][st][i]
      let (am, asd) = dpStat(allY)
      let (sm, ssd) = dpStat(subY)
      let (dm, dsd) = dpStat(subD)
      echo &"ENTRYY {tag} team{tm}  all n={allY.len} mean={am:.1f} " &
        &"stdev={asd:.1f}  |  SUBSET(seats0-3) n={subY.len} mean={sm:.1f} " &
        &"STDEV={ssd:.1f}  |  DOOR(+90px seats0-3) n={subD.len} " &
        &"mean={dm:.1f} STDEV={dsd:.1f}"
    flushFile(stdout)

when defined(ndprobe):
  # -d:ndprobe ENGINE TRUTH, mirrored verbatim from harness.nim (2026-08-17,
  # the grabprobe lever-attribution gap). The policy-side ndprobe counters
  # (ndCarryFrames, ndSupplyRole, ndPairFrames, ...) already live in
  # baseline.nim and arrive here for free via the `include` above — but the
  # ENGINE-truth half (throws/pickups/impacts/spacing) was only ever wired
  # into harness.nim's runEpisode, so grabprobe has never been able to report
  # it. These vars + the two collection sites below (per-tick spacing sample,
  # per-episode grenade-record join) port that wiring so grabprobe can print
  # the identical ND-PROBE funnel harness.out does.
  var ndThrows, ndPickups: array[4, int]
  var ndImpactDmg = 0        # impacts that damaged at least one enemy body
  var ndImpactBunch = 0      # ...of which caught >=2 bodies of ONE team
  var ndVictims = 0          # enemy bodies damaged, summed over impacts
  var ndStaleThrows, ndStaleHit, ndStaleVictims: int
  var ndFreshThrows, ndFreshHit, ndFreshVictims: int
  var ndUnjoined = 0         # releases with no matching engine throw
  var ndSpaceBots = 0
  var ndSpaceUnder = 0
  var ndSpaceSum = 0.0
  var ndSpaceHist: array[6, int]

when defined(fpprobe):
  # ⭐⭐ -d:fpprobe (2026-08-17, ffa4 integration gate). Two jobs no existing
  # probe does:
  #   (1) BEHAVIOURAL FINGERPRINT. A fire counter is not proof — a sibling
  #       lever logged 362 target writes on a run whose emitted button-mask
  #       stream was byte-identical, because navSteer overwrote every waypoint.
  #       fpMask hashes EVERY emitted button mask in (tick, slot) order and
  #       fpTraj hashes ground-truth positions on a stride, so "identical" and
  #       "different" are both provable, not argued.
  #   (2) LIFE ECONOMY. The ffa4 scoring metric is lives spent BY HALF-TIME,
  #       and an ffa4 episode ends by ELIMINATION well before maxTicks — so
  #       half-time is half of the REALISED length, which is only knowable
  #       afterwards. Keep a per-team death timeline and index it at the end.
  var fpMask: uint64 = 0xcbf29ce484222325'u64
  var fpTraj: uint64 = 0xcbf29ce484222325'u64
  proc fpMix(h: var uint64, b: uint8) =
    h = (h xor b.uint64) * 0x100000001b3'u64
  proc fpMixInt(h: var uint64, v: int) =
    var x = v
    for i in 0 .. 3:
      fpMix(h, uint8(x and 0xff))
      x = x shr 8
  const FpTrajStride = 25          # ticks between trajectory samples
  var
    fpDeathTL: array[4, seq[int]]  # per team: cumulative deaths, sampled per tick
    fpLivesHalf: array[4, int]     # Σ lives spent by half-time, over episodes
    # ⭐⭐ FIXED-WINDOW life spend (2026-08-17, coordinator's confound). "By
    # half-time" is a proportion of a length the LEVER ITSELF CHANGES: if a
    # lever keeps a team alive the episode runs longer, half-time lands at a
    # later absolute tick, and more lives have been spent by then MECHANICALLY
    # — the metric penalises the lever for working. An ABSOLUTE tick is
    # identical across arms by construction. 1500 is the window the original
    # causal read used (early deaths predict the winner 76.4%).
    fpLivesAt: array[3, array[4, int]]   # Σ lives spent by tick 1000 / 1500 / 2000
    fpLivesAtN: array[3, array[4, int]]  # episodes that actually REACHED that tick
    fpTicksByTeam: array[4, int]         # Σ realised episode length (survival proxy)
    fpLivesEnd: array[4, int]      # Σ lives spent at episode end
    fpEps: array[4, int]           # episodes counted per team
    fpWiped: array[4, int]         # episodes the team lost ALL its lives
    fpCapsTotal: array[4, int]     # Σ captures
    fpCapsLate: array[4, int]      # ...struck in the final 20% of the episode
    fpCapTL: array[4, seq[int]]    # per team: cumulative captures, per tick
    fpHp1Enter: array[4, int]      # times a live body first reached hp == 1
    fpHp1Escape: array[4, int]     # ...and got back above 1 hp alive (a heal)
    fpHp1Death: array[4, int]      # ...and died at 1 hp
    fpHeals: array[4, int]         # any hp increase on a live body (kits taken)
    fpTicksSum = 0
    fpGames = 0

when defined(tempoprobe):
  # ⭐⭐⭐ TGEV FUTILITY BOUND + the measured c, both from ONE run.
  #
  # The rule: "the gate FIRED" is worth nothing on its own — an 88.7% bind rate
  # once turned out constant by construction. What has to be answerable BEFORE a
  # sweep is "how many lives by T=1200 could this gate plausibly recover", and
  # that is an UPPER bound, computable with no counterfactual:
  #
  #   a life the gate can possibly save = an early death whose slot took a
  #   DECLINE DECISION within TgFollowTicks before it died.
  #
  # Every early death with NO decision in front of it is unreachable by this
  # lever at ANY effect size, so the covered share caps the payoff. Run it in
  # TGSHADOW=1 (decisions recorded, declineUntil never written) and the bound
  # comes off a run that is byte-identical to the control — no sweep, no arm.
  #
  # The same ledger measures c (TradeContestBurn), which is the one constant in
  # the design without a source: rival lives burned inside TgJoinRadius of a fight
  # we declined, within the same window, split contested vs solo.
  const TgEarlyWindow = 1200
    ## The pre-registered metric tick: attrition margin @T=1200 has AUC 0.777 for
    ## finishing first, and by T=2400 every team converges on the 12-life ceiling.
  const TgJoinRadius = 260.0     ## mirrors baseline's RetreatRadius (the tally radius)
  const TgFollowJoin = 120       ## mirrors baseline's TgFollowTicks
  var
    tgEpsJoined = 0
    tgDecisions = 0            # ledger rows (rising-edge declines)
    tgDecisionsContest = 0
    tgDecFollowedByOwnDeath = 0   # ...and that slot died within the window
    tgEarlyDeaths = 0             # ALL deaths at tick <= TgEarlyWindow (denominator)
    tgEarlyDeathsCovered = 0      # ...preceded by a decision => THE BOUND numerator
    tgEarlyDeathsArmed = 0        # ...on a team whose tune actually has the gate on
    tgEarlyDeathsArmedCov = 0
    tgBurnContestSum = 0
    tgBurnContestN = 0
    tgBurnSoloSum = 0
    tgBurnSoloN = 0
    tgArmedTeam: array[4, bool]
when defined(kselprobe):
  # ⭐⭐⭐ THE PLACEBO-CONTROLLED APPROACH METRIC, ON THE RIG (kitSel, 2026-08-20).
  # PRIMARY instrument for the kit lane, ported from the hosted-replay tool so the
  # same statistic can be read before AND after a code change without shipping.
  # Net px CLOSED, during an hp==1 segment, toward a target fixed at segment
  # ONSET, in three families:
  #   REAL     nearest STOCKED engine spawn        (the thing we want)
  #   LOCKED   nearest spawn that is NOT stocked   (placebo 1 — a real spot with
  #            no kit on it, so approach to it is not kit-seeking)
  #   PHANTOM  nearest formula spot                (placebo 2 — where the control
  #            arm's medEcon actually addresses)
  # A policy that steers to kits closes px on REAL and not on the placebos.
  # ⚠️ Read the PAIRED contrast (REAL minus a placebo), never a single column.
  # The hosted study showed the PHANTOM column is contaminated by a POSITIONAL
  # ARTIFACT — the formula sits on the contested centre column and every policy
  # drifts there, including the scripted control, whose source provably contains
  # no formula at all. LOCKED is the honest placebo; PHANTOM is diagnostic only.
  # All ground truth (engine.medKitSpawnsTruth + slotVitals), never a bot belief.
  var ksApN: array[4, int]         # hp1 segments scored
  var ksApReal: array[4, float]    # Σ net px closed on the nearest STOCKED spawn
  var ksApLocked: array[4, float]  # Σ ... on the nearest UNSTOCKED spawn
  var ksApPhantom: array[4, float] # Σ ... on the nearest formula spot
  var ksApOnset: array[4, float]   # Σ onset distance to the stocked target — the
                                   # exposure the errand actually had to cover
  var ksApNLocked: array[4, int]   # segments the LOCKED placebo was defined on
  var ksApNPhantom: array[4, int]  # segments the PHANTOM placebo was defined on
  var ksApNoReal: array[4, int]    # segments with NO stocked spawn anywhere: the
                                   # "kits are genuinely unavailable" share, i.e.
                                   # the number that would kill this whole lane
  # Per-slot segment state. Targets are LATCHED at onset, matching the hosted
  # instrument exactly — re-picking the nearest target every tick would score a
  # bot that merely wanders as though it were converging.
  var ksSegOn: array[32, bool]
  var ksSegReal: array[32, tuple[x, y: float, ok: bool]]
  var ksSegLocked: array[32, tuple[x, y: float, ok: bool]]
  var ksSegPhantom: array[32, tuple[x, y: float, ok: bool]]
  var ksSegD0: array[32, tuple[real, locked, phantom: float]]

  proc ksDist(ax, ay, bx, by: float): float =
    let dx = ax - bx
    let dy = ay - by
    sqrt(dx * dx + dy * dy)

  # ── ⭐⭐ THE TWO-VALUE `Team` ENUM: does the code defect have a MEASURED COST?
  # (2026-08-20, raised by the deadlever lane, measured here at the coordinator's
  # request.) The POLICY's `Team = enum Red, Blue` (baseline.nim:2010) has two
  # values; the engine's has four. Every static address is written
  # `if team == Red: <a> else: <b>`, so on a 4-team board two colours are handed
  # another colour's coordinate. `ownShieldSpawn` and `arcSpawn` are the two live
  # cases (the med-kit formula is NOT one — it has no team term at all, and its
  # miss is a generator mismatch, proven by |dx| == 0 on 18/18 2-team boards).
  #
  # ⚠️ THE COLOUR -> Team MAPPING IS SLOT PARITY, NOT "everything past red is
  # Blue". runBot seeds `team = (if slot mod 2 == 0: Red else: Blue)` and the
  # colour lock only re-deals for literal "red"/"blue" (baseline.nim ~7093:
  # "colors past blue have no 2-team analogue, so they keep the parity team").
  # So GREEN inherits RED's address and YELLOW inherits BLUE's — green does NOT
  # inherit blue's. Getting this backwards would invert the predicted geometry.
  #
  # ⚠️ SEAT IS THE CONFOUND. Shield grabs are dominated by ONE seat
  # (ShieldRushSeat = 0, ~86% of 2-team shields, and it collapses ~30x on
  # 4-team), so colour and seat MUST be crossed, never pooled — otherwise the
  # seat effect masquerades as a colour effect. Both are counted below.
  #
  # ⚠️ ARC IS A LATENT COST, NOT A LIVE ONE: arcSpawn is only reached through
  # arcBreach, which the deadlever lane established is `when defined(arcOn)`
  # and therefore unreachable in every shipped image. Reported, labelled.
  var ksShieldGrab: array[4, array[8, int]]   # [raw team index][team seat]
  var ksArcGrab: array[4, array[8, int]]
  var ksHadShield: array[32, bool]
  var ksHadArc: array[32, bool]
  var ksAddrErrShield: array[4, float]        # policy address -> OWN team spawn
  var ksAddrErrArc: array[4, float]
  var ksAddrN: array[4, int]

const FfaFixedWindow = 1500
  ## ⭐⭐ The arm-invariant life-spend window (2026-08-17). "By half-time" is a
  ## fraction of an episode length the LEVER ITSELF changes — a lever that keeps
  ## a team alive lengthens the episode, half-time lands later, and more lives
  ## have been spent by then MECHANICALLY. An absolute tick is identical across
  ## arms. 1500 is the window the causal read used (early deaths predict the
  ## winner 76.4%, early kills 45.1%).

proc main() =
  var games = 12
  var seed = 100
  var ticks = 10000
  var i = 0   # commandLineParams() excludes argv[0]; start at the FIRST real flag
  let p = commandLineParams()
  while i < p.len:
    case p[i]
    of "--games": inc i; games = parseInt(p[i])
    of "--seed": inc i; seed = parseInt(p[i])
    of "--ticks": inc i; ticks = parseInt(p[i])
    else: discard
    inc i

  var
    totRedGrab, totBlueGrab, totRedCap, totBlueCap: int
    totRedShot, totBlueShot, totRedHit, totBlueHit: int
    redWins, blueWins, draws: int
    # ⭐ N-TEAM TALLY (v49 rig): winnerTeam is ord(sim.winner) — already 0..3 —
    # and r.slots carries team/kills/deaths/captures per seat, so the 4-team
    # truth always flowed through this probe and was being collapsed into two
    # buckets ("Blue" = every non-Red team — why a 4-team mirror printed
    # "Red 0 / Blue 10" and looked like a red-seat defect). Aggregate per real
    # team. Engine redGrabs/blueGrabs misattribute on >2 teams (any non-Blue
    # victim credits "blue"), so GRABS stays a 2-team metric.
    teamWins, teamCaps, teamKills, teamDeaths: array[4, int]
  # ⭐⭐ L2/L4 ffa4 TEMPO MANDATE (2026-08-17) scoring: lives spent BY HALF-TIME
  # (of each team's own starting pool — causal, ~5x more discriminating than
  # K/D per the mandate) and capture TIMING (L4's own target: move captures
  # later without losing any). Always-on (not gated behind a -d: probe — this
  # is the headline score, not lever-fire diagnostics), engine truth straight
  # off r.slots. "Half-time" = min(ticks/2, the tick the episode actually
  # ended) — a game that WIPES before the clock's halfway point can spend no
  # more lives after it ends, so its final tally IS its half-time tally.
  var totLivesStart, totLivesHalf: float   # Σ over (games × teams) of each
                                           # team's own starting/half-time pool
  when defined(sprayab):
    # ⭐⭐⭐ the carried-can A/B ledger, per RAW ENGINE TEAM. Presses, carry-ticks
    # and yield are all per team so SPRAYCONETEAM=<n> can be scored against the
    # SAME team in a control run — seat is NOT exchangeable on this board
    # (8.9/8.9/23.2/58.9% win share by slot block), so nothing may be pooled
    # across teams and no team may be compared to another.
    var
      sabPress, sabCarryT, sabDmg, sabFfDmg, sabKills, sabFfKills, sabHits,
        sabLanded, sabEps: array[4, int]
      sabCursor = 0            # read cursor into the never-drained tier-2 sink
      sabPrevArc: array[32, int]
      sabFireAt: array[32, int]
      sabLandFlag: array[32, bool]
  when defined(aoeprobe):
    var
      aoGunFf, aoSprayFf, aoNadeFf, aoNadeSelf: int
      aoGunAll, aoSprayAll, aoNadeAll: int
      aoTeamEps = 0                      # Σ (episodes × teams) = the /team-Ep denominator
      aoNadeThrows, aoNadeMatched: int
      aoNHotN, aoNHotFf, aoNHotFoe: int  # throws the veto WOULD have stopped
      aoNColdN, aoNColdFf, aoNColdFoe: int
      aoNMissFf, aoNMissFoe: int         # bursts with no matching release row
      aoSprayEv, aoSprayMatched: int
      aoSHotFf, aoSHotFoe, aoSColdFf, aoSColdFoe: int
      aoSMissFf, aoSMissFoe: int
  var totCaptures = 0        # Σ captures, ANY team, this batch
  var totCapturesLate = 0    # ...of which landed in the final 20% of the clock
  when defined(wleadprobe):
    var
      wlShots, wlHits, wlIn: array[4, array[5, int]]
      wlPerp: array[4, array[5, float]]
      wlArmed: array[4, float]
      wlMaskFnv: uint64 = 0xcbf29ce484222325'u64
  when defined(shapeprobe):
    var
      shCross, shDeathOwn, shDeathEnemy, shDeepSum, shTicks: array[2, int]
      shDeepMax: array[2, int]
  let evalTeams = max(2, (if getEnv("EVAL_TEAMS").len > 0:
                            parseInt(getEnv("EVAL_TEAMS")) else: 2))
  # ⭐ EVAL_PLAYERS (2026-08-14): the 4ffa8 board is 32 SLOTS, and only there
  # does teamSeat reach 4..7 on a 4-team deal (teamSeat = slot div teams). With
  # the roster hard-coded to 16 the seat-4 half of the table was never exercised
  # at RUNTIME on 4-team at all — the seat dump proved the deal, but "the deal is
  # right" and "every seat still acts" are different claims and the statue
  # failure only shows up in the second one.
  let numPlayers = max(2, (if getEnv("EVAL_PLAYERS").len > 0:
                             parseInt(getEnv("EVAL_PLAYERS")) else: 16))
  for g in 0 ..< games:
    let epSeed = seed + g
    var engine = newEvalEngine(numPlayers, epSeed, ticks)
    var drivers: seq[Driver]
    for s in 0 ..< numPlayers:
      drivers.add newDriver(s, engine.teamOfSlot(s), epSeed)
      when defined(doorprobe):
        if s < 32: engineTeamOfSlot[s] = engine.teamOfSlot(s)
      when defined(wuffprobe):
        # The RAW engine team per slot, handed to the policy-side counters: they
        # cannot derive it themselves (bot.team is Red/Blue and collapses three
        # teams into one on this board).
        if s < 32: wuffTeamOfSlot[s] = engine.teamOfSlot(s)
    when defined(wleadprobe):
      # ⭐⭐⭐ LEVERSTATE — the RESOLVED tune, per RAW ENGINE TEAM, straight off
      # the constructed Bot. Not an echo of the env: this is what
      # shippedCombatTune() returned after every knob and the WLEADTEAM
      # re-stamp. With the lever DEFAULT ON an out-of-range WLEADTEAM=9 control
      # arm must print 0 for EVERY team, or the isolation is inverted.
      var wlSeen: array[4, bool]
      for s in 0 ..< numPlayers:
        let tm = engine.teamOfSlot(s)
        if tm notin 0 .. 3 or wlSeen[tm]: continue
        wlSeen[tm] = true
        wlArmed[tm] = drivers[s].bot.tune.windupLead
        echo "LEVERSTATE ", epSeed, " ", tm,
          " windupLead=", drivers[s].bot.tune.windupLead,
          " windupSelfLead=", drivers[s].bot.tune.windupSelfLead
    when defined(kselprobe):
      # ⭐⭐ STATIC ADDRESS ERROR, per RAW ENGINE TEAM. Before a single tick runs:
      # how far is the address the POLICY would walk to from the spawn the ENGINE
      # actually gave THAT team? This is the code defect expressed in pixels, and
      # it is what the pickup counts below have to be explained by.
      # The policy side is reproduced here rather than called, because
      # ownShieldSpawn/arcSpawn take the collapsed Red/Blue enum and the whole
      # point is to show what that collapse does to each of the four colours.
      block ksAddrErr:
        let ms = engine.mapSize()
        let
          mw = float(ms.w)
          mh = float(ms.h)
          shY = float(3 * ms.h div 4)          # ownShieldSpawn's y
          arcY = float(ms.h div 4)             # arcSpawn's y
          shields = engine.shieldSpawnsTruth()
          arcs = engine.arcSpawnsTruth()
        var seen: array[4, bool]
        for sl in 0 ..< numPlayers:
          let tm = engine.teamOfSlot(sl)
          if tm notin 0 .. 3 or seen[tm]: continue
          seen[tm] = true
          # SLOT PARITY is the mapping — green (2) -> Red, yellow (3) -> Blue.
          let asRed = (sl mod 2) == 0
          let shAddr = (if asRed: (50.0, shY) else: (mw - 50.0, shY))
          let arcAddr = (if asRed: (50.0, arcY) else: (mw - 50.0, arcY))
          # Compare against THIS team's OWN engine spawn, indexed by team.
          if tm < shields.len:
            ksAddrErrShield[tm] += ksDist(shAddr[0], shAddr[1],
              float(shields[tm].x), float(shields[tm].y))
          if tm < arcs.len:
            ksAddrErrArc[tm] += ksDist(arcAddr[0], arcAddr[1],
              float(arcs[tm].x), float(arcs[tm].y))
          inc ksAddrN[tm]
    when defined(wuffprobe):
      # ⭐⭐⭐ LEVERSTATE — the RESOLVED tune, per raw engine team, straight off the
      # constructed Bot. Not an echo of the env and not a claim about the source:
      # this is what shippedCombatTune() actually returned after every knob and
      # every team-isolation override was applied. It is the only line that can
      # answer "is the lever ARMED in this binary" without arguing from code, and
      # it is exactly the question v30 got wrong (lever in the source, dark in the
      # image, nine days). It also makes the isolation INVERSION checkable: with
      # the levers now DEFAULT ON, an out-of-range *TEAM=9 control arm must print
      # 0 for every team, not 1.
      var lsSeen: array[4, bool]
      for s in 0 ..< numPlayers:
        let tm = engine.teamOfSlot(s)
        if tm notin 0 .. 3 or lsSeen[tm]: continue
        lsSeen[tm] = true
        let tn = drivers[s].bot.tune
        echo "LEVERSTATE ", epSeed, " ", tm,
          " windupFf=", ord(tn.windupFf),
          " union=", ord(tn.windupFfUnion),
          " lead=", tn.windupFfLead,
          " selfLead=", tn.windupFfSelfLead.int,
          " axis=", ord(tn.windupFfAxis),
          " shadow=", ord(tn.windupFfShadow),
          " nadeFf=", ord(tn.nadeFfVeto),
          " sprayFf=", ord(tn.sprayFfVeto),
          " raidFrame=", ord(tn.raidFrame),
          " sprayCone=", (when compiles(tn.sprayConeFire): ord(tn.sprayConeFire) else: -1),
          " sprayFirst=", (when compiles(tn.sprayFireFirst): ord(tn.sprayFireFirst) else: -1),
          # ⭐⭐⭐ kitSel: the RESOLVED bit, so "is the selector armed in THIS
          # binary" is readable rather than argued. A KITSELTEAM=9 control arm
          # must print kitSel=0 on all four rows; an armed arm must print 1 on
          # exactly the named team(s) and 0 on the rest.
          " kitSel=", ord(tn.kitSel)
    when defined(wuffprobe):
      # The per-tick flag ledger is per EPISODE and indexed by BOT TICK, so it is
      # sized to the tick budget plus slack for the windup tail and cleared here.
      for s in 0 ..< 32:
        wuffTickFlags[s].setLen(ticks + 32)
        for i in 0 ..< wuffTickFlags[s].len: wuffTickFlags[s][i] = 0'u8
        wuffSupAt[s] = -1
    when defined(sprayab):
      sabCursor = 0
      # ⭐⭐⭐ ARM STATE, printed from the CONSTRUCTED Bot, not from the env. This
      # is the line that answers "is the lever actually on in this binary" —
      # exactly the question v30 got wrong (lever in the source, dark in the
      # image, nine days). With both levers DEFAULT ON, an out-of-range
      # SPRAYCONETEAM=9 control arm must print 0 for EVERY team.
      if sabEps[0] == 0:
        var sabLs: array[4, bool]
        for s in 0 ..< numPlayers:
          let tm = engine.teamOfSlot(s)
          if tm notin 0 .. 3 or sabLs[tm]: continue
          sabLs[tm] = true
          # `when compiles` so this same rig file drops UNCHANGED into the
          # pre-fix base tree — the A/B arms must differ in baseline.nim ONLY.
          when compiles(drivers[s].bot.tune.sprayConeFire):
            echo "SPRAYARM team=", tm,
              " sprayConeFire=", ord(drivers[s].bot.tune.sprayConeFire),
              " sprayFireFirst=", ord(drivers[s].bot.tune.sprayFireFirst),
              " spraySingle=", ord(drivers[s].bot.tune.spraySingle),
              " sprayFfVeto=", ord(drivers[s].bot.tune.sprayFfVeto)
          else:
            echo "SPRAYARM team=", tm, " sprayConeFire=NA sprayFireFirst=NA",
              " spraySingle=", ord(drivers[s].bot.tune.spraySingle),
              " sprayFfVeto=", ord(drivers[s].bot.tune.sprayFfVeto)
      for s in 0 ..< 32:
        sabPrevArc[s] = 0
        sabFireAt[s] = -100_000
        sabLandFlag[s] = false
      for t in 0 .. 3: inc sabEps[t]
    when defined(idhash):
      idMask = 0xcbf29ce484222325'u64
      idTraj = 0xcbf29ce484222325'u64
      idFrames = 0
    when defined(ndprobe):
      ndReleases.setLen(0)     # the release ledger is per-EPISODE (joined below)
    when defined(aoeprobe):
      nfRel.setLen(0)          # both AoE ledgers are per-EPISODE (joined below)
      sfFire.setLen(0)
    when defined(tempoprobe):
      # ⭐⭐⭐ TGEV ledgers are per EPISODE and joined at the end of it.
      tgEvt.setLen(0)
      for s2 in 0 ..< 32: tgShadowUntil[s2] = -1
      var tgDeaths: seq[tuple[tick, slot, team, x, y: int]] = @[]
      var tgPrevDeaths = newSeq[int](numPlayers)
      var tgPrevX = newSeq[int](numPlayers)
      var tgPrevY = newSeq[int](numPlayers)
      for s2 in 0 ..< numPlayers:
        let v = engine.slotVitals(s2)
        tgPrevDeaths[s2] = v.deaths
        tgPrevX[s2] = v.x
        tgPrevY[s2] = v.y
      for t in 0 .. 3: tgArmedTeam[t] = false
      for s2 in 0 ..< numPlayers:
        let tm = engine.teamOfSlot(s2)
        if tm in 0 .. 3 and drivers[s2].bot.tune.tradeGate:
          tgArmedTeam[tm] = true
      # ⭐⭐⭐ TGSTATE — the RESOLVED tune per RAW ENGINE TEAM, straight off the
      # constructed Bot. Not an echo of the env: this is what shippedCombatTune()
      # returned AFTER every knob and the TGEVTEAM override. It is the only line
      # that answers "is the lever armed in this binary" without arguing from
      # source — the exact question v30 got wrong (in the source, dark in the
      # image, nine days). TGEVTEAM=9 must print 0 on all four rows.
      if g == 0:
        var tgSeen: array[4, bool]
        for s2 in 0 ..< numPlayers:
          let tm = engine.teamOfSlot(s2)
          if tm notin 0 .. 3 or tgSeen[tm]: continue
          tgSeen[tm] = true
          let tn = drivers[s2].bot.tune
          echo "TGSTATE ", epSeed, " team", tm,
            " tradeGate=", ord(tn.tradeGate),
            " square=", ord(tn.tradeGateSquare),
            " contest=", ord(tn.tradeGateContest),
            " selfHp=", ord(tn.tradeGateSelfHp),
            " shadow=", ord(tn.tradeGateShadow),
            " burn=", tn.tradeGateBurn,
            " role=", drivers[s2].bot.role
    when defined(fpprobe):
      for t in 0 .. 3:
        fpDeathTL[t].setLen(0)
        fpCapTL[t].setLen(0)
      var fpWasHp1 = newSeq[bool](numPlayers)
      var fpLastHp = newSeq[int](numPlayers)
      var fpLastDeaths = newSeq[int](numPlayers)
      var fpWasAlive = newSeq[bool](numPlayers)
      for s in 0 ..< numPlayers:
        let v = engine.slotVitals(s)
        fpLastHp[s] = v.hp
        fpLastDeaths[s] = v.deaths
        fpWasAlive[s] = v.alive
    # tempo mandate: starting life pool per team (engine truth, before tick 0).
    var tmLivesStart: array[4, int]
    block:
      let r0 = engine.result()
      for s in r0.slots:
        if s.team in 0 .. 3: tmLivesStart[s.team] += s.lives + (if s.alive: 1 else: 0)
    # ⚠️ INTEGRATION FIX (2026-08-17): the original sampler took the pool at
    # `ticks div 2` OR at phaseOver, whichever came first. An ffa4 episode ends
    # by ELIMINATION — median 3087 ticks on 348 cached hosted 4-team episodes,
    # p25 2420 — so with --ticks 5000 nearly every episode hit phaseOver first
    # and the "half-time" reading was actually the FINAL pool. That inflates
    # lives-spent-by-half toward 12 in BOTH arms and flattens the very delta the
    # metric exists to show. Half-time is half of the REALISED length, which is
    # only knowable afterwards, so keep the timeline and index it at the end.
    var tmPoolTL: seq[int] = @[]
    var tmStartTotal = 0
    for t in 0 .. 3: tmStartTotal += tmLivesStart[t]
    var tmLastCapTotal = 0
    var tmCapTicks: seq[int] = @[]     # tick of every capture this episode
    when defined(lifeprobe):
      var lpTeamSeats: array[4, int]
      for s in 0 ..< numPlayers:
        let tm = engine.teamOfSlot(s)
        if tm in 0 .. 3: inc lpTeamSeats[tm]
      var lpHalfSampled = false
    var tick = 0
    while tick < ticks:
      # Stamp the ENGINE tick into the policy module before the frames run, so
      # the AoE release/press ledgers carry the same clock the sim events do and
      # the join below needs no offset guess (bot.tick is a per-seat frame count
      # that resets on respawn — joining on it would be a silent mismatch).
      when defined(aoeprobe): aoeTick = tick
      when defined(tempoprobe): tgTick = tick
      for s in 0 ..< numPlayers:
        let packet = engine.frameFor(s)
        let mask = drivers[s].frame(packet)
        engine.setMask(s, mask)
        when defined(idhash):
          idMix(idMask, tick)
          idMix(idMask, s)
          idMix(idMask, int(mask))
          inc idFrames
        when defined(fpprobe): fpMix(fpMask, mask)
        # ⭐⭐ SHOUT-FORWARDING FIX (2026-08-17). This rig never forwarded a bot's
        # staged shout (bot.shoutWant) into the sim — harness.nim's runEpisode
        # does this every frame (engine.applyShout), grabprobe never did. The
        # decide()-side counters (csEmit, csECall, ...) still incremented
        # because they fire the moment a bot STAGES a shout, not when it is
        # heard — so a whole prior grabprobe run could read EMIT>0 with every
        # downstream comms counter (HEARD/ADOPT/STACK-CONVERGE/WIPE-LANE/
        # LINE-DIVERT/LATCH-DROP) silently and permanently stuck at 0, with no
        # signal that the channel itself was disconnected. Mirrors harness.nim
        # lines ~561-563 exactly.
        if drivers[s].bot.shoutWant.len > 0:
          engine.applyShout(s, drivers[s].bot.shoutWant)
          drivers[s].bot.shoutWant = ""
      engine.advance()
      when defined(tempoprobe):
        # A death is detected the tick the counter MOVES, by which time the seat
        # may already sit on its respawn point — so the row carries the position
        # from the PREVIOUS tick, which is where the fight actually was.
        for s2 in 0 ..< numPlayers:
          let v = engine.slotVitals(s2)
          if v.deaths > tgPrevDeaths[s2]:
            tgDeaths.add((tick: tick, slot: s2, team: engine.teamOfSlot(s2),
                          x: tgPrevX[s2], y: tgPrevY[s2]))
          tgPrevDeaths[s2] = v.deaths
          if v.alive:
            tgPrevX[s2] = v.x
            tgPrevY[s2] = v.y
      when defined(sprayab):
        for s in 0 ..< numPlayers:
          if s >= 32: continue
          let tm = engine.sprayAbTeamOf(s)
          if tm notin 0 .. 3: continue
          let st = engine.sprayAbSlot(s)
          if st.can and st.alive: inc sabCarryT[tm]
          if st.arcTicks > sabPrevArc[s]:
            inc sabPress[tm]
            sabFireAt[s] = tick
            sabLandFlag[s] = false
          sabPrevArc[s] = st.arcTicks
        let sev = engine.sprayAbEvents(sabCursor)
        for t in 0 .. 3:
          sabDmg[t] += sev.dmg[t]; sabFfDmg[t] += sev.ffDmg[t]
          sabKills[t] += sev.kills[t]; sabFfKills[t] += sev.ffKills[t]
          sabHits[t] += sev.hits[t]
        # a press LANDED if it drew any spray damage inside its own 5-tick window
        for sc in 0 ..< 32:
          if not sev.dmgSrc[sc]: continue
          let tm = engine.sprayAbTeamOf(sc)
          if tm notin 0 .. 3: continue
          if tick - sabFireAt[sc] <= 5 and not sabLandFlag[sc]:
            sabLandFlag[sc] = true
            inc sabLanded[tm]
      when defined(idhash):
        for s in 0 ..< numPlayers:
          let st = engine.slotIdState(s)
          idMix(idTraj, tick)
          idMix(idTraj, s)
          idMix(idTraj, st.x)
          idMix(idTraj, st.y)
          idMix(idTraj, st.hp)
          idMix(idTraj, ord(st.alive))
      when defined(ndprobe):
        let sp = engine.ndSpacingSample()
        ndSpaceBots += sp.bots
        ndSpaceUnder += sp.underBlast
        ndSpaceSum += sp.sumNearest
        for b in 0 ..< sp.hist.len: ndSpaceHist[b] += sp.hist[b]
      inc tick
      when defined(fpprobe):
        var dTot: array[4, int]
        var cTot: array[4, int]
        for s in 0 ..< numPlayers:
          let tm = engine.teamOfSlot(s)
          let v = engine.slotVitals(s)
          if tm in 0 .. 3:
            dTot[tm] += v.deaths
            cTot[tm] += engine.slotCaptures(s)
            # hp == 1 episodes: entered, escaped (healed above 1 while alive),
            # or died there. GROUND TRUTH, never the bot's own belief.
            if v.alive and v.hp == 1 and not fpWasHp1[s]:
              fpWasHp1[s] = true
              inc fpHp1Enter[tm]
              # ⭐⭐⭐ kitSel APPROACH METRIC — LATCH the three targets at onset.
              when defined(kselprobe):
                if s < 32:
                  let
                    px = float(v.x)
                    py = float(v.y)
                  var
                    bestR = 1e18
                    bestL = 1e18
                    bestP = 1e18
                  ksSegReal[s] = (0.0, 0.0, false)
                  ksSegLocked[s] = (0.0, 0.0, false)
                  ksSegPhantom[s] = (0.0, 0.0, false)
                  for sp in engine.medKitSpawnsTruth():
                    let d = ksDist(px, py, float(sp.x), float(sp.y))
                    if sp.present:
                      if d < bestR:
                        bestR = d
                        ksSegReal[s] = (float(sp.x), float(sp.y), true)
                    else:
                      if d < bestL:
                        bestL = d
                        ksSegLocked[s] = (float(sp.x), float(sp.y), true)
                  # The formula spots the CONTROL arm's medEcon addresses. Derived
                  # from the live board's own dimensions, exactly as baseline.nim
                  # derives MedKitAX/AY/BX/BY — so this tracks the real defect on
                  # whatever map EVAL_MAPSPEC loaded, never a hard-coded pair.
                  let
                    ms = engine.mapSize()
                    mw = float(ms.w)
                    mh = float(ms.h)
                  for fp in [(mw / 2.0, mh / 3.0), (mw / 2.0, 2.0 * mh / 3.0)]:
                    let d = ksDist(px, py, fp[0], fp[1])
                    if d < bestP:
                      bestP = d
                      ksSegPhantom[s] = (fp[0], fp[1], true)
                  ksSegOn[s] = true
                  ksSegD0[s] = (bestR, bestL, bestP)
                  if not ksSegReal[s].ok: inc ksApNoReal[tm]
            elif fpWasHp1[s]:
              if v.deaths > fpLastDeaths[s] or not v.alive:
                fpWasHp1[s] = false
                inc fpHp1Death[tm]
              elif v.hp > 1:
                fpWasHp1[s] = false
                inc fpHp1Escape[tm]
              # ⭐⭐⭐ kitSel APPROACH METRIC — CLOSE the segment. Net px closed is
              # onset distance minus final distance to the SAME latched point, so
              # positive = moved toward it. A segment with no stocked spawn at all
              # is counted in ksApNoReal and contributes to nothing else.
              when defined(kselprobe):
                if s < 32 and ksSegOn[s] and not fpWasHp1[s]:
                  ksSegOn[s] = false
                  let
                    px = float(v.x)
                    py = float(v.y)
                  if ksSegReal[s].ok:
                    inc ksApN[tm]
                    ksApOnset[tm] += ksSegD0[s].real
                    ksApReal[tm] += ksSegD0[s].real -
                      ksDist(px, py, ksSegReal[s].x, ksSegReal[s].y)
                    # ⚠️ Its OWN denominator. A locked spawn only exists once
                    # somebody has taken a kit, so ksApLocked is summed over a
                    # SUBSET of the segments ksApReal covers — dividing both by
                    # ksApN would silently shrink the placebo toward zero and
                    # manufacture the very contrast this probe exists to test.
                    if ksSegLocked[s].ok:
                      inc ksApNLocked[tm]
                      ksApLocked[tm] += ksSegD0[s].locked -
                        ksDist(px, py, ksSegLocked[s].x, ksSegLocked[s].y)
                    if ksSegPhantom[s].ok:
                      inc ksApNPhantom[tm]
                      ksApPhantom[tm] += ksSegD0[s].phantom -
                        ksDist(px, py, ksSegPhantom[s].x, ksSegPhantom[s].y)
            # ⚠️ `alive last tick too`: a RESPAWN restores hp from 0 to full a few
            # ticks AFTER the death counter moved, so without this a respawn
            # reads as a medkit and heals/ep inflates ~10x.
            if v.alive and fpWasAlive[s] and v.hp > fpLastHp[s] and
                v.deaths == fpLastDeaths[s]:
              inc fpHeals[tm]
          when defined(kselprobe):
            # ⭐⭐ Shield / arc PICKUP EDGES, crossed by RAW TEAM INDEX and TEAM
            # SEAT. A false->true transition on a LIVE body is a grab; a respawn
            # clears the flag, so the `alive` guard keeps a respawn from reading
            # as a drop-and-regrab. teamSeat mirrors the policy's own
            # `clamp(slot div max(GameTeams,2), 0, 7)`.
            if s < 32 and tm in 0 .. 3:
              let it = engine.slotItems(s)
              let seat = clamp(s div max(evalTeams, 2), 0, 7)
              if it.alive and it.shield and not ksHadShield[s]:
                inc ksShieldGrab[tm][seat]
              if it.alive and it.arc and not ksHadArc[s]:
                inc ksArcGrab[tm][seat]
              ksHadShield[s] = it.shield and it.alive
              ksHadArc[s] = it.arc and it.alive
          fpLastHp[s] = v.hp
          fpLastDeaths[s] = v.deaths
          fpWasAlive[s] = v.alive
          if tick mod FpTrajStride == 0:
            fpMixInt(fpTraj, v.x)
            fpMixInt(fpTraj, v.y)
            fpMixInt(fpTraj, v.hp)
        for t in 0 .. 3:
          fpDeathTL[t].add dTot[t]
          fpCapTL[t].add cTot[t]
      when defined(lifeprobe):
        # ⭐⭐ FIXED ABSOLUTE WINDOW (2026-08-17, integration gate). This was
        # `tick >= ticks div 2` — PROPORTIONAL half-time. A lever that keeps a
        # team alive LENGTHENS the episode, which pushes half-time to a later
        # absolute tick, so more lives have been spent by then MECHANICALLY:
        # the metric penalises the lever for working, and a candidate that
        # survived longer read WORSE (11.06 vs 10.56) purely from the moving
        # denominator. FfaFixedWindow is identical across arms by construction.
        # 1500 is the window the causal read used (early deaths predict the
        # winner 76.4% there; early kills 45.1%).
        if not lpHalfSampled and tick >= FfaFixedWindow:
          lpHalfSampled = true
          for s in 0 ..< numPlayers:
            let tm = engine.teamOfSlot(s)
            if tm notin 0 .. 3: continue
            let st = engine.slotLifeState(s)
            let livesNow = st.lives + (if st.alive: 1 else: 0)
            lpHalfSpentSum[tm] += float(3 - livesNow)
      when defined(roleprobe):
        if tick mod RpSampleEvery == 0: rpSample(engine, numPlayers)
      when defined(idhash):
        # Printed on a 200-tick stride, not every tick: FNV is CUMULATIVE, so a
        # single frame's divergence permanently changes every later hash and a
        # strided read is a complete proof of the whole stream. Per-tick echo
        # was 5x the cost of the simulation itself.
        if tick mod 200 == 0 or tick == ticks:
         # ⭐⭐⭐ CONTROL-IDENTITY LINE. One per episode, printed BEFORE any
         # aggregation so a divergence is localised to a SEED and a TICK rather
         # than to a mean. A control arm that is byte-identical to the base
         # commit must reproduce BOTH hashes at EVERY sample; one mismatch is a
         # failed identity proof, not a rounding difference.
         echo "IDHASH seed=", epSeed, " t=", tick, " frames=", idFrames,
           " mask=", toHex(idMask), " traj=", toHex(idTraj)
      let r = engine.result()
      # tempo mandate: sample the life pool at half-time (or at whatever tick
      # the episode ends, if that's earlier — no more lives can be spent after).
      var poolNow = 0
      for s in r.slots:
        if s.team in 0 .. 3: poolNow += s.lives + (if s.alive: 1 else: 0)
      tmPoolTL.add poolNow
      # tempo mandate: capture TIMING. r.slots' `captures` is cumulative per
      # player, so a rise in the summed total this tick is a fresh capture,
      # timestamped at `tick` — bucket it against the clock fraction.
      var tmCapNow = 0
      for s in r.slots: tmCapNow += s.captures
      if tmCapNow > tmLastCapTotal:
        let newCaps = tmCapNow - tmLastCapTotal
        totCaptures += newCaps
        tmCapTicks.add tick
        tmLastCapTotal = tmCapNow
      if r.phaseOver: break
    let r = engine.result()
    when defined(wleadprobe):
      # ⭐ Harvest the range-binned shot census, per RAW TEAM. Printed as RAW
      # NUMERATORS/DENOMINATORS: this rig's absolutes are uncalibrated (a
      # measured 7.7x spread across seed blocks), so only a PAIRED contrast
      # armed-team vs unarmed-team on the SAME seeds is admissible.
      for tm in 0 ..< 4:
        for b in 0 ..< 5:
          let c = engine.wleadCounts(tm, b)
          wlShots[tm][b] += c.shots
          wlHits[tm][b] += c.hits
          wlIn[tm][b] += c.inWindow
          wlPerp[tm][b] += c.perpSum
      var wlK, wlD: array[4, int]
      for sl in r.slots:
        if sl.team in 0 .. 3:
          wlK[sl.team] += sl.kills
          wlD[sl.team] += sl.deaths
      for tm in 0 ..< min(4, max(2, evalTeams)):
        var line = "WLEADROW " & $epSeed & " " & $tm & " armed=" & $wlArmed[tm] &
          " K=" & $wlK[tm] & " D=" & $wlD[tm]
        for b in 0 ..< 5:
          let c = engine.wleadCounts(tm, b)
          line.add " b" & $b & "=" & $c.hits & "/" & $c.shots & ":" & $c.inWindow
        echo line
    when defined(wuffprobe):
      # ⭐⭐⭐ THE FUTILITY BOUND. Join every RELEASED gun shot back to the tick
      # that pulled it (engine truth, via GunTrigger.actionId), then ask the
      # policy-side ledger what the veto said on THAT frame. That turns "the veto
      # fired N times" into "the veto flagged the trigger of M of the K shots that
      # actually hit a teammate" — the only number that bounds what it can win.
      #
      # Printed RAW, one row per episode per team, because this rig's absolutes
      # are not calibrated to the field (a measured 7.7x spread across seed
      # blocks): only a PAIRED WITHIN-BLOCK contrast on identical seeds is
      # admissible, and that needs the per-episode grain. Columns are COUNTS,
      # never rates — pooling first would give an episode with 3 shots the weight
      # of one with 90.
      block wuffRow:
        var
          shots, ffHits, enHits, geo: array[4, int]
          ffFlagA, ffFlagB, ffFlagC, ffFlagD, ffFlagU, ffPullSeen: array[4, int]
          kl, dt, cp, lv: array[4, int]
        for row in engine.wuffGunShots():
          let t = row.srcTeam
          if t notin 0 .. 3: continue
          inc shots[t]
          let isFf = row.tgtTeam == t and row.tgtSlot >= 0
          if row.tgtSlot < 0: inc geo[t]
          elif isFf: inc ffHits[t]
          else: inc enHits[t]
          if row.triggerTick >= 0:
            # Tick alignment is MEASURED, not assumed: the bot's own tick and the
            # sim's tickCount are advanced by different code, so scan a small
            # window around the joined trigger tick, take the nearest frame this
            # slot actually pulled, and record the offset. wuffOffHist below is
            # the proof — a single sharp mode means the alignment is exact.
            var best = 99
            for off in -4 .. 4:
              let bt = row.triggerTick + off
              if row.srcSlot in 0 ..< 32 and bt >= 0 and
                  bt < wuffTickFlags[row.srcSlot].len and
                  (wuffTickFlags[row.srcSlot][bt] and 1'u8) != 0:
                if abs(off) < abs(best): best = off
            if best != 99:
              wuffOffHist[best + 4] += 1
              if isFf:
                inc ffPullSeen[t]
                let f = wuffTickFlags[row.srcSlot][row.triggerTick + best]
                if (f and 2'u8) != 0: inc ffFlagA[t]
                if (f and 4'u8) != 0: inc ffFlagB[t]
                if (f and 8'u8) != 0: inc ffFlagC[t]
                if (f and 16'u8) != 0: inc ffFlagD[t]
                if (f and 64'u8) != 0: inc ffFlagU[t]
            elif isFf:
              inc wuffFfNoPull
        for st in r.slots:
          if st.team notin 0 .. 3: continue
          kl[st.team] += st.kills
          dt[st.team] += st.deaths
          cp[st.team] += st.captures
          lv[st.team] += st.lives + (if st.alive: 1 else: 0)
        for t in 0 .. 3:
          if shots[t] == 0 and kl[t] == 0 and dt[t] == 0: continue
          echo "WUFFROW ", epSeed, " ", t, " ", r.ticks,
            " ", shots[t], " ", enHits[t], " ", ffHits[t], " ", geo[t],
            " ", ffPullSeen[t], " ", ffFlagA[t], " ", ffFlagB[t],
            " ", ffFlagC[t], " ", ffFlagD[t], " ", ffFlagU[t],
            " ", wuffCand[t], " ", wuffBlkA[t], " ", wuffBlkB[t],
            " ", wuffBlkC[t], " ", wuffBlkD[t], " ", wuffBlkU[t], " ", wuffNewD[t],
            " ", wuffSup[t], " ", wuffStale[t],
            " ", wuffRe[0][t], " ", wuffRe[1][t], " ", wuffRe[2][t],
            " ", kl[t], " ", dt[t], " ", cp[t], " ", lv[t]
        # The policy-side counters are process-global and cumulative; the row
        # above is a running total, so bank the episode deltas by resetting.
        for t in 0 .. 3:
          wuffCand[t] = 0; wuffBlkA[t] = 0; wuffBlkB[t] = 0; wuffBlkC[t] = 0
          wuffBlkD[t] = 0; wuffBlkU[t] = 0; wuffNewD[t] = 0
          wuffSup[t] = 0; wuffStale[t] = 0
          wuffRe[0][t] = 0; wuffRe[1][t] = 0; wuffRe[2][t] = 0
    when defined(lifeprobe):
      # Episode ended before tick FfaFixedWindow (common in ffa4 — the mode ends
      # by ELIMINATION): no more lives can be spent after that, so the final
      # state IS the count at the window. Denominator stays every episode, so
      # both arms are compared on the same population.
      if not lpHalfSampled:
        for s in 0 ..< numPlayers:
          let tm = engine.teamOfSlot(s)
          if tm notin 0 .. 3: continue
          let st = engine.slotLifeState(s)
          let livesNow = st.lives + (if st.alive: 1 else: 0)
          lpHalfSpentSum[tm] += float(3 - livesNow)
      for tm in 0 .. 3:
        if lpTeamSeats[tm] == 0: continue
        inc lpEpisodes[tm]
        lpSeatsPerTeam[tm] = lpTeamSeats[tm]
        var allElim = true
        for s in 0 ..< numPlayers:
          if engine.teamOfSlot(s) != tm: continue
          let st = engine.slotLifeState(s)
          if st.alive or st.lives > 0:
            allElim = false
            break
        if allElim: inc lpFinalAllElim[tm]
    when defined(ndprobe):
      # ENGINE TRUTH + the stale-vs-fresh DISCRIMINATION join, once per episode
      # (mirrors harness.nim's runEpisode tail verbatim).
      let recs = engine.ndGrenadeRecs()
      for rec in recs:
        case rec.kind
        of 0:
          if rec.team in 0 .. 3: inc ndThrows[rec.team]
        of 2:
          if rec.team in 0 .. 3: inc ndPickups[rec.team]
        of 1:
          var hit = 0
          var bunch = false
          for t in 0 .. 3:
            if t == rec.team: continue     # a self-blast is not a punish
            hit += rec.victims[t]
            if rec.victims[t] >= 2: bunch = true
          if hit > 0:
            inc ndImpactDmg
            ndVictims += hit
            if bunch: inc ndImpactBunch
        else: discard
      var ledger: array[64, seq[bool]]
      for rel in ndReleases:
        if rel.slot in 0 ..< ledger.len: ledger[rel.slot].add rel.stale
      var used: array[64, int]
      for rec in recs:
        if rec.kind != 0: continue
        if rec.slot < 0 or rec.slot >= ledger.len: continue
        if used[rec.slot] >= ledger[rec.slot].len:
          inc ndUnjoined
          continue
        let stale = ledger[rec.slot][used[rec.slot]]
        inc used[rec.slot]
        var v = 0
        for q in recs:
          if q.kind == 1 and q.actionId == rec.actionId:
            for t in 0 .. 3:
              if t != rec.team: v += q.victims[t]
            break
        if stale:
          inc ndStaleThrows
          ndStaleVictims += v
          if v > 0: inc ndStaleHit
        else:
          inc ndFreshThrows
          ndFreshVictims += v
          if v > 0: inc ndFreshHit
    block tmFold:
      # Realised length, realised half, realised final-20% — never the CONFIGURED
      # --ticks, which an elimination mode almost never reaches.
      let realT = tmPoolTL.len
      if realT > 0:
        totLivesStart += tmStartTotal.float
        totLivesHalf += tmPoolTL[max(0, min(realT - 1, FfaFixedWindow - 1))].float
        for ct in tmCapTicks:
          if ct.float >= 0.8 * realT.float: inc totCapturesLate
    when defined(tempoprobe):
      # ── ⭐⭐⭐ TGEV JOIN. Two answers out of one pair of ledgers.
      inc tgEpsJoined
      tgDecisions += tgEvt.len
      for e in tgEvt:
        if e.contested: inc tgDecisionsContest
        let eTeam = (if e.slot >= 0 and e.slot < numPlayers:
                       engine.teamOfSlot(e.slot) else: -1)
        var burn = 0
        var ownDied = false
        for d in tgDeaths:
          if d.tick <= e.tick or d.tick > e.tick + TgFollowJoin: continue
          if d.slot == e.slot:
            ownDied = true
          elif d.team != eTeam:
            let dx = (d.x - e.x).float
            let dy = (d.y - e.y).float
            if dx * dx + dy * dy <= TgJoinRadius * TgJoinRadius: inc burn
        if ownDied: inc tgDecFollowedByOwnDeath
        if e.contested:
          tgBurnContestSum += burn; inc tgBurnContestN
        else:
          tgBurnSoloSum += burn; inc tgBurnSoloN
      # THE BOUND. An early death with no decline decision in front of it is
      # unreachable by this lever at any effect size.
      for d in tgDeaths:
        if d.tick > TgEarlyWindow: continue
        inc tgEarlyDeaths
        let armed = d.team in 0 .. 3 and tgArmedTeam[d.team]
        if armed: inc tgEarlyDeathsArmed
        var covered = false
        for e in tgEvt:
          if e.slot == d.slot and d.tick > e.tick and
              d.tick - e.tick <= TgFollowJoin:
            covered = true
            break
        if covered:
          inc tgEarlyDeathsCovered
          if armed: inc tgEarlyDeathsArmedCov
    when defined(fpprobe):
      let realTicks = fpDeathTL[0].len
      inc fpGames
      fpTicksSum += realTicks
      if realTicks > 0:
        let halfIdx = max(0, realTicks div 2 - 1)
        let lateIdx = max(0, (realTicks * 4) div 5 - 1)
        let nTeams = max(2, evalTeams)
        const FpFixedTicks = [1000, 1500, 2000]
        for t in 0 ..< min(4, nTeams):
          inc fpEps[t]
          fpTicksByTeam[t] += realTicks
          for w in 0 .. 2:
            # An episode that ENDED before the window closed still contributes:
            # no more lives can be spent after elimination, so its final count IS
            # its count at that tick. Denominator stays every episode, so the two
            # arms are compared on the same population.
            let idx = min(realTicks - 1, FpFixedTicks[w] - 1)
            fpLivesAt[w][t] += fpDeathTL[t][max(0, idx)]
            inc fpLivesAtN[w][t]
          fpLivesHalf[t] += fpDeathTL[t][halfIdx]
          fpLivesEnd[t] += fpDeathTL[t][^1]
          fpCapsTotal[t] += fpCapTL[t][^1]
          fpCapsLate[t] += fpCapTL[t][^1] - fpCapTL[t][lateIdx]
        # WIPE: every slot of the team out of lives AND dead at the end.
        var alive: array[4, int]
        for sl in r.slots:
          if sl.team in 0 .. 3:
            alive[sl.team] += sl.lives + (if sl.alive: 1 else: 0)
        for t in 0 ..< min(4, nTeams):
          if alive[t] == 0: inc fpWiped[t]
    when defined(aoeprobe):
      # ── ⭐⭐ AoE FF: engine truth + the join that makes the futility bound exact.
      let ffd = engine.aoeFfDamage()
      aoGunFf += ffd.gunFf; aoSprayFf += ffd.sprayFf; aoNadeFf += ffd.nadeFf
      aoGunAll += ffd.gunAll; aoSprayAll += ffd.sprayAll; aoNadeAll += ffd.nadeAll
      aoNadeSelf += ffd.nadeSelf
      aoTeamEps += clamp(evalTeams, 2, 4)
      # GRENADE: every burst is attributed to the release row that produced it,
      # so its friendly AND enemy hit points land in the hot (veto would have
      # stopped it) or cold (it would not) bucket. Unmatched bursts are reported
      # separately and never silently folded into either — an unmatched row is a
      # broken join, not a cold throw.
      for row in engine.aoeNadeRows():
        inc aoNadeThrows
        var hit = -1
        var bestGap = 1 shl 30
        for i in 0 ..< nfRel.len:
          if nfRel[i].slot != row.slot: continue
          let gap = abs(nfRel[i].tick - row.throwTick)
          if gap <= 6 and gap < bestGap:
            bestGap = gap
            hit = i
        if hit < 0:
          aoNMissFf += row.ffDmg; aoNMissFoe += row.foeDmg
        else:
          inc aoNadeMatched
          if nfRel[hit].hot[2]:
            inc aoNHotN; aoNHotFf += row.ffDmg; aoNHotFoe += row.foeDmg
          else:
            inc aoNColdN; aoNColdFf += row.ffDmg; aoNColdFoe += row.foeDmg
      # SPRAY: the cone re-picks victims every active tick, so each damage tick
      # is folded back onto the LATEST press by that seat inside the activation
      # window (PlasmaArcActiveTicks, plus slack for the frame/step offset).
      for row in engine.aoeSprayRows():
        inc aoSprayEv
        var hit = -1
        var bestTick = -1 shl 30
        for i in 0 ..< sfFire.len:
          if sfFire[i].slot != row.slot: continue
          let dt = row.tick - sfFire[i].tick
          if dt >= -3 and dt <= 8 and sfFire[i].tick > bestTick:
            bestTick = sfFire[i].tick
            hit = i
        if hit < 0:
          aoSMissFf += row.ffDmg; aoSMissFoe += row.foeDmg
        else:
          inc aoSprayMatched
          if sfFire[hit].hot[2]:
            aoSHotFf += row.ffDmg; aoSHotFoe += row.foeDmg
          else:
            aoSColdFf += row.ffDmg; aoSColdFoe += row.foeDmg
    totRedGrab += r.redGrabs; totBlueGrab += r.blueGrabs
    totRedCap += r.redCaptures; totBlueCap += r.blueCaptures
    totRedShot += r.redShots; totBlueShot += r.blueShots
    totRedHit += r.redHits; totBlueHit += r.blueHits
    if r.isDraw or r.winnerTeam < 0: inc draws
    elif r.winnerTeam == 0: inc redWins
    else: inc blueWins
    if r.winnerTeam in 0 .. 3: inc teamWins[r.winnerTeam]
    for s in r.slots:
      if s.team in 0 .. 3:
        teamCaps[s.team] += s.captures
        teamKills[s.team] += s.kills
        teamDeaths[s.team] += s.deaths
    when defined(shapeprobe):
      var perGame: array[2, string]
      for t in 0 .. 1:
        let sc = engine.shapeCounts(t)
        shCross[t] += sc.cross
        shDeathOwn[t] += sc.deathOwn
        shDeathEnemy[t] += sc.deathEnemy
        shDeepSum[t] += sc.deepSum
        shTicks[t] += sc.ticks
        if sc.deepMax > shDeepMax[t]: shDeepMax[t] = sc.deepMax
        perGame[t] = &"cross {sc.cross} deaths own/enemy {sc.deathOwn}/{sc.deathEnemy} " &
          &"deep {(sc.deepSum.float / max(1, sc.ticks).float):.2f} (max {sc.deepMax})"
      echo &"  SHAPE red:  {perGame[0]}"
      echo &"  SHAPE blue: {perGame[1]}"
    when defined(roleprobe):
      # Per-SEAT K/D. teamSeat is the engine's own slotIdentityIndex
      # (slot div teams) — the same formula roleForSeat is fed — so this is the
      # seat the roster scan's Α..Θ letters name, not a re-derived guess.
      for s in r.slots:
        if s.team notin 0 .. 1: continue
        let st = clamp(s.slot div max(2, evalTeams), 0, 7)
        rpKills[s.team][st] += s.kills
        rpDeaths[s.team][st] += s.deaths
        inc rpEps[s.team][st]
      let ff = engine.friendlyFireCounts()
      rpKillsAll += ff.kills; rpFfKills += ff.ffKills
      rpFfGun += ff.ffGun; rpFfNade += ff.ffNade; rpFfSpray += ff.ffSpray
      rpDmgAll += ff.dmg; rpFfDmg += ff.ffDmg
    echo &"game {g}: winner={r.winnerTeam} ticks={r.ticks} " &
      &"grabs R{r.redGrabs}/B{r.blueGrabs} caps R{r.redCaptures}/B{r.blueCaptures}"
    when defined(doorprobe):
      dpEntryLine(&"afterGame{g}")
    flushFile(stdout)

  when defined(roleprobe):
    # ── ⭐⭐ MID-QUAD REPORT. Three things, in the order they have to be true:
    #   1) the levers FIRED (a compiled-but-inert lever reads exactly like a
    #      broken one, and the reverts must read ZERO),
    #   2) nothing became a STATUE (per-seat frames + travel, the silent
    #      seat-contract failure),
    #   3) the separation actually moved (the mirror-measurable target).
    const RpRoleName = ["MidTop", "MidBottom", "MidGuard", "FlankTop",
                        "FlankBottom", "Overwatch", "HomeDefender"]
    echo "==================================================="
    echo "--- MID-QUAD PROBE ---"
    echo &"  arm: NOSEAT4={getEnv(\"NOSEAT4\")} NOROLESEP={getEnv(\"NOROLESEP\")} " &
      &"NOMIDSPREAD={getEnv(\"NOMIDSPREAD\")} NODOOR1={getEnv(\"NODOOR1\")} " &
      &"SEAT4TEAM={getEnv(\"SEAT4TEAM\")}"
    for tm in 0 .. 1:
      let tname = (if tm == 0: "RED " else: "BLUE")
      echo &"  team {tname}  seat  role          eps    K     D    K/D    K-D/ep" &
        &"   sepFire  midFire  midTrailMean  PARK"
      var tk, td = 0
      for st in 0 .. 7:
        if rpEps[tm][st] == 0: continue
        tk += rpKills[tm][st]; td += rpDeaths[tm][st]
        # Match the per-team K/D convention already used below: with zero deaths
        # the ratio is undefined, so report the kills rather than a 0.00 that
        # reads as "this seat did nothing" when it in fact went unkilled.
        let kd = (if rpDeaths[tm][st] > 0:
                    rpKills[tm][st].float / rpDeaths[tm][st].float
                  else: rpKills[tm][st].float)
        let kdep = (rpKills[tm][st] - rpDeaths[tm][st]).float / rpEps[tm][st].float
        let rn = (if dpRole[tm][st] in 0 .. 6: RpRoleName[dpRole[tm][st]] else: "-")
        let mtm = (if rpMidFrames[tm][st] > 0:
                     rpMidTrailSum[tm][st] / rpMidFrames[tm][st].float else: 0.0)
        echo &"          {st:>6}  {rn:<12} {rpEps[tm][st]:>3} {rpKills[tm][st]:>5} " &
          &"{rpDeaths[tm][st]:>5} {kd:>6.2f} {kdep:>9.2f} {rpSepFrames[tm][st]:>9} " &
          &"{rpMidFrames[tm][st]:>8} {mtm:>13.1f} {rpPark[tm][st]:>5}"
      let skd = (if td > 0: tk.float / td.float else: tk.float)
      var park = 0
      for st in 0 .. 7: park += rpPark[tm][st]
      echo &"  team {tname}  SQUAD  K {tk} D {td}  K/D {skd:.2f}  " &
        &"PARK-INVARIANT {(if park == 0: \"OK (0 frames)\" else: \"*** VIOLATED: \" & $park & \" frames ***\")}"
      # SEPARATION — the geometric target. A pair inside RpNadePairPx can be
      # taken by ONE grenade; bodyNade is the per-body version of the field's
      # "58.4% of nade impacts caught 2+ of ours".
      let pa = max(1, rpPairAll[tm])
      let ba = max(1, rpBodyAll[tm])
      let ysp = (if rpYSpreadN[tm] > 0:
                   rpYSpreadSum[tm] / rpYSpreadN[tm].float else: 0.0)
      echo &"  team {tname}  SEPARATION  pairs n={rpPairAll[tm]}  " &
        &"within{RpNadePairPx.int}px {100.0 * rpPairNade[tm].float / pa.float:.2f}%  " &
        &"within{RpTightPairPx.int}px {100.0 * rpPairTight[tm].float / pa.float:.2f}%  |  " &
        &"BODIES n={rpBodyAll[tm]} with a mate inside one blast " &
        &"{100.0 * rpBodyNade[tm].float / ba.float:.2f}%  |  live-mate y-STDEV {ysp:.1f}"
    # ⭐⭐ FRIENDLY FIRE — the crowding metric, and the one the FIELD reports:
    # 8.1% of half4 deaths were own-colour on the deal where three of four seats
    # are mids. Friendly fire is ON in this engine, so this is not a proxy for
    # crowding, it IS crowding: a mate on the ray, or a blast that caught two.
    let ka = max(1, rpKillsAll)
    let da = max(1, rpDmgAll)
    echo &"  FRIENDLY FIRE  kills n={rpKillsAll}  own-colour {rpFfKills} " &
      &"({100.0 * rpFfKills.float / ka.float:.2f}%)  [gun {rpFfGun} " &
      &"nade {rpFfNade} spray {rpFfSpray}]  |  damage events n={rpDmgAll}  " &
      &"own-colour {rpFfDmg} ({100.0 * rpFfDmg.float / da.float:.2f}%)"
    flushFile(stdout)

  when defined(doorprobe):
    # ── ⭐ ONE-DOOR REPORT. The target metric is ENTRY-Y STDEV: the spread of
    # the y at which our seats cross the midline into the enemy half. Field
    # baseline vs daveey: ours 5/17/31px, his 148-242px, target >100.
    # SUBSET is the number that matters: in "1v1 (8 per team)" paintbot we hold
    # slots {0,2,4,6} => teamSeats {0,1,2,3}, so seats 4..7 are a DIFFERENT
    # entrant's and must not be averaged into our score. This rig seats our
    # policy on all 8, so the subset is taken by filtering, not by re-seating.
    const RoleName = ["MidTop", "MidBottom", "MidGuard", "FlankTop",
                      "FlankBottom", "Overwatch", "HomeDefender"]
    let statOf = dpStat
    echo "==================================================="
    echo "--- ONE-DOOR PROBE (entry-y = midline crossing into the enemy half) ---"
    for tm in 0 .. 1:
      var allY: seq[float]
      var subY: seq[float]
      let tname = (if tm == 0: "RED " else: "BLUE")
      echo &"  team {tname}   seat  role          entries  meanY   stdevY   " &
        &"aliveFrames  travelPx  hotArm  hotFire  doorDeaths  hold  rel  exp"
      for st in 0 .. 7:
        var ys: seq[float]
        for i in 0 ..< dpEntryN[tm][st]: ys.add dpEntryY[tm][st][i]
        allY.add ys
        if st <= 3: subY.add ys
        let (mn, sd) = statOf(ys)
        let rn = (if dpRole[tm][st] in 0 .. 6: RoleName[dpRole[tm][st]] else: "-")
        echo &"           {st:>6}  {rn:<12} {ys.len:>8} {mn:>7.1f} {sd:>8.1f} " &
          &"{dpAliveFrames[tm][st]:>12} {dpTravel[tm][st]:>9.0f} " &
          &"{dpHotDoorArm[tm][st]:>7} {dpHotDoorFire[tm][st]:>8} " &
          &"{dpDoorDeaths[tm][st]:>11} {dpWaveHold[tm][st]:>5} " &
          &"{dpWaveRelease[tm][st]:>4} {dpWaveExpire[tm][st]:>4}"
      let (am, asd) = statOf(allY)
      let (sm, ssd) = statOf(subY)
      echo &"  team {tname}  ALL8   entries {allY.len:>5}  meanY {am:>7.1f}  " &
        &"ENTRY-Y STDEV {asd:>7.1f}"
      echo &"  team {tname}  SUBSET entries {subY.len:>5}  meanY {sm:>7.1f}  " &
        &"ENTRY-Y STDEV {ssd:>7.1f}   <-- the league seats {{0,1,2,3}}"
      # The DOOR reading (+90px past the midline). On r1692 e20 the midline
      # spread was 81.6px and the same seats' door spread was 6.8px — the
      # midline number alone would have called a one-door game "spread".
      var subD: seq[float]
      for st in 0 .. 3:
        for i in 0 ..< dpDoorN[tm][st]: subD.add dpDoorY[tm][st][i]
      let (dm, dsd) = statOf(subD)
      echo &"  team {tname}  DOOR   crossings {subD.len:>5}  meanY {dm:>7.1f}  " &
        &"DOOR-Y  STDEV {dsd:>7.1f}   <-- +90px past the midline"
    var hArm, hFire, dDeath, wHold, wRel, wExp = 0
    for tm in 0 .. 1:
      for st in 0 .. 7:
        hArm += dpHotDoorArm[tm][st]; hFire += dpHotDoorFire[tm][st]
        dDeath += dpDoorDeaths[tm][st]; wHold += dpWaveHold[tm][st]
        wRel += dpWaveRelease[tm][st]; wExp += dpWaveExpire[tm][st]
    echo &"  LEVER FIRES  doorDeaths {dDeath}  hotDoorArmed {hArm}  " &
      &"hotDoorMovedTarget {hFire}  waveHoldFrames {wHold}  " &
      &"waveReleases {wRel}  waveCapExpiries {wExp}"
    echo &"  NOSEATFIX diffFrames {dpSeatFixDiff}  (the arcBreach seat-divisor " &
      &"fix; provably 0 whenever EVAL_TEAMS<=2 — max(GameTeams,2)==2 makes the " &
      &"two formulas byte-identical by construction. Re-run with EVAL_TEAMS=4 " &
      &"to see it fire.)"
    echo &"  NODOOR1 seat-swap: read the per-seat role table above — armed " &
      &"(env NODOOR1 unset, 2-team) means teamSeat 1 = FlankTop and " &
      &"teamSeat 6 = MidGuard; NODOOR1=1 reverts to the old table (teamSeat 1 " &
      &"= MidGuard, teamSeat 6 = FlankTop). This is a STATIC seat assignment, " &
      &"not a per-frame fire — there is nothing to count beyond the table."
    # ── SEAT LIVENESS. "2 of 6 bots stood perfectly still with zero errors"
    # after a silent seat-contract change; travel==0 or frames==0 is that
    # signature. Indexed by physical SLOT so it is unambiguous on 4-team too.
    echo "  --- SEAT LIVENESS (every slot must have frames>0 AND travel>0) ---"
    var dead = 0
    for sl in 0 ..< numPlayers:
      let rn = (if dpSlotRole[sl] in 0 .. 6: RoleName[dpSlotRole[sl]] else: "-")
      let ok = dpSlotFrames[sl] > 0 and dpSlotTravel[sl] > 0.0
      if not ok: inc dead
      echo &"    slot {sl:>2}  team {engineTeamOfSlot[sl]:>2}  teamSeat " &
        &"{dpSlotSeat[sl]:>2}  role {rn:<13} frames {dpSlotFrames[sl]:>7}  " &
        &"travel {dpSlotTravel[sl]:>9.0f}px  entries {dpSlotEntries[sl]:>4}  " &
        &"{(if ok: \"ACTS\" else: \"*** STATUE ***\")}"
    echo &"    STATUES: {dead} of {numPlayers}"

  when defined(commsprobe):
    # ── COMMS BUS + v56 PLAY EXECUTORS, on the grabprobe rig. Mirrors
    # harness.nim's -d:commsprobe report verbatim (same module-level counters,
    # incremented from the shared baseline.nim decide() — grabprobe just never
    # printed them before). grabprobe always runs shippedCombatTune() (see
    # newDriver above), so commsBus/commsPlay/stackConverge/playMove/playLatch/
    # eCallout are ON here by construction, unlike harness.nim's default
    # defaultCombatTune() control (which needs CONTROL_SHIPPED=1 to match).
    echo "==================================================="
    echo &"  COMMS-PROBE: classify stack {csStack} wipe {csWipe} peel {csPeel} line {csLine} -> " &
      &"EMIT {csEmit} -> HEARD {csHeard} -> ADOPT {csAdopt} -> WIPE-ARM {csWipeArm} " &
      &"LINE-ARM {csLineArm} NADE-CLUSTER {csNadeLine} ARC-SEEK {csArcSeek} ARC-FIRE {csArcFire}"
    echo &"    (classify>0 => the scenario read fires (incl. LINE = standing enemy line); EMIT>0 => " &
      &"codewords broadcast; HEARD>0 => mates decode them; ADOPT>0 => a heard play drove a mate's flank; " &
      &"WIPE-ARM/LINE-ARM>0 => a HEARD wipe/line armed a mate's rally it never saw itself)"
    let stackPx = (if csStackMove > 0: csStackMovePx / csStackMove.float else: 0.0)
    let wipePx = (if csWipeMove > 0: csWipeMovePx / csWipeMove.float else: 0.0)
    let linePx = (if csLineMove > 0: csLineMovePx / csLineMove.float else: 0.0)
    echo &"  PLAY-EXEC (v56): STACK-CONVERGE {csStackMove} frames / {csStackMovePx:.0f}px " &
      &"(mean {stackPx:.0f}px)  STACK-GATE {csStackGate}  " &
      &"WIPE-LANE {csWipeMove} / {csWipeMovePx:.0f}px (mean {wipePx:.0f}px)  " &
      &"LINE-DIVERT {csLineMove} / {csLineMovePx:.0f}px (mean {linePx:.0f}px)"
    echo &"  PLAY-HYGIENE (v56): LATCH-DROP {csLatchDrop} (different-token overwrites refused)  " &
      &"ECHO-SKIP {csEchoSkip} (redundant emits suppressed)  E-CALLOUT {csECall} emitted / " &
      &"{csESeed} tracks seeded from a heard one"
    echo &"    (⭐ every count on these two lines is FEET MOVED or a SLOT FREED, not eligibility — " &
      &"a frame count >0 with a ~0px mean is still a no-op, so read the px.)"
    echo &"  STACK-WATERFALL: EMIT-STACK {csEmitStack} -> HEARD-STACK-RAW {csStackHeardRaw} -> " &
      &"FRESH-ENTRY {csStackFreshEntry} -> [TOO-CLOSE {csStackTooClose}  TOO-FAR {csStackTooFar}  " &
      &"BAND-OK {csStackBandOk}] -> NO-DELTA {csStackNoDelta} -> MOVE {csStackMove}"
    echo &"    (EMIT-STACK>0 => this bot's own classifier called STACK; HEARD-STACK-RAW>0 => a mate's " &
      &"STACK token decoded; FRESH-ENTRY = heardFresh true + heardPlay==RpStack, i.e. reached the " &
      &"stackConverge if; TOO-CLOSE/TOO-FAR partition FRESH-ENTRY by the 70-460px callD band; " &
      &"NO-DELTA = band ok but d<=1.0, already on target. 2026-08-17 verdict: EMIT-STACK is the " &
      &"bottleneck, not the band — see the STACK-CONVERGE section of the investigation memo.)"

  when defined(ndprobe):
    # ── v56 NADE PACKAGE, on the grabprobe rig. Mirrors harness.nim's
    # -d:ndprobe report; the engine-truth half (throws/pickups/impacts/spacing)
    # is now collected in the tick loop + episode tail above.
    let
      staleConv = (if ndStaleThrows > 0:
                     100.0 * ndStaleHit.float / ndStaleThrows.float else: 0.0)
      freshConv = (if ndFreshThrows > 0:
                     100.0 * ndFreshHit.float / ndFreshThrows.float else: 0.0)
      staleVpt = (if ndStaleThrows > 0:
                    ndStaleVictims.float / ndStaleThrows.float else: 0.0)
      freshVpt = (if ndFreshThrows > 0:
                    ndFreshVictims.float / ndFreshThrows.float else: 0.0)
      bunchPct = (if ndImpactDmg > 0:
                    100.0 * ndImpactBunch.float / ndImpactDmg.float else: 0.0)
      meanNear = (if ndSpaceBots > 0: ndSpaceSum / ndSpaceBots.float else: 0.0)
      underPct = (if ndSpaceBots > 0:
                    100.0 * ndSpaceUnder.float / ndSpaceBots.float else: 0.0)
    echo "==================================================="
    echo &"  ND-PROBE 1/stale funnel: carryFrames {ndCarryFrames} -> " &
      &"staleWallCamper-tracks {ndStaleSeen} -> withCluster>=2 {ndStaleCluster} -> " &
      &"STALE-AIM {ndStaleAim} (fresh-aim {ndFreshAim}) -> " &
      &"RELEASED stale {ndStaleRelease} / fresh {ndFreshRelease}"
    echo &"    DISCRIMINATION (engine truth, joined by actionId): " &
      &"stale throws {ndStaleThrows} conv {staleConv:.1f}% victims/throw {staleVpt:.2f}  |  " &
      &"fresh throws {ndFreshThrows} conv {freshConv:.1f}% victims/throw {freshVpt:.2f}  " &
      &"(unjoined {ndUnjoined})"
    echo &"  ND-PROBE 2/supply funnel: eligible-role frames {ndSupplyRole} -> " &
      &"depot-known {ndSupplyDepot} -> DETOUR {ndSupplySeek}  " &
      &"(seen-sprite grabs {ndSupplySeen}; depots seeded {ndDepotSeeded} learned {ndDepotLearned})"
    echo &"    engine truth pickups per team: R{ndPickups[0]} B{ndPickups[1]} " &
      &"G{ndPickups[2]} Y{ndPickups[3]}   throws: R{ndThrows[0]} B{ndThrows[1]} " &
      &"G{ndThrows[2]} Y{ndThrows[3]}"
    echo &"  ND-PROBE 3/anti-bunch: stimulus mate-inside-blast frames {ndPairFrames} -> " &
      &"band-push {ndBunchBand} / STEP-APART {ndBunchStep}"
    echo &"    spacing (ground truth, all living bots): mean nearest-mate {meanNear:.1f}px  " &
      &"inside one blast {underPct:.1f}% of bot-ticks  " &
      &"hist[<26|26-52|52-66|66-100|100-200|200+] " &
      &"{ndSpaceHist[0]} {ndSpaceHist[1]} {ndSpaceHist[2]} {ndSpaceHist[3]} " &
      &"{ndSpaceHist[4]} {ndSpaceHist[5]}"
    echo &"    blast multiplicity: impacts that damaged someone {ndImpactDmg}, " &
      &"of which caught 2+ of one team {ndImpactBunch} ({bunchPct:.1f}%), victims {ndVictims}"

  when defined(tempoprobe):
    # ── L2/L4 ffa4 TEMPO MANDATE — behavioural PROOF the two levers actually
    # fire a decision, not just a counter (navSteer has silently absorbed
    # waypoint writes before). Every number here is a DISCRIMINATING count:
    # frames where the lever's presence changed what the old logic would have
    # done, not just frames the branch was merely evaluated.
    echo "==================================================="
    echo "--- TEMPO PROBE (L2 volume gate; L4 late-flag clock RETIRED 2026-08-17) ---"
    echo &"  L2 tradeGate: fireSuperiority-branch evals {tgEval}  " &
      &"oldMarginWouldPress {tgWouldPress}  DECLINED-ANYWAY {tgDeclined}" &
      (if tgWouldPress > 0:
         &"  ({100.0*tgDeclined.float/tgWouldPress.float:.1f}% of press-worthy-by-the-old-bar frames now decline)"
       else: "  (0 press-worthy frames seen this run)")
    echo "  L4 flagClock: RETIRED — lever and counters deleted. See the tombstone at " &
      "LateFlagClockTick in baseline.nim before re-deriving it: armed on ONE team it " &
      "produced episodes IDENTICAL to the all-off control in 8 of 9, its commit-hard " &
      "bypass fired 0 times in every arm ever run, and its premise is refuted on our " &
      "own hosted episodes (more early steals => fewer lives spent AND more wins)."
    echo "  (0 in any BLOCKED/DECLINED column with a non-zero stimulus column beside it means the gate compiled but never fired)"
    # ── ⭐⭐⭐ TGEV (the ffa4 TRADE-EV GATE, 2026-08-20) ────────────────────────
    echo "--- TGEV: ffa4 TRADE-EV GATE ---"
    echo &"  arm: TGEV={getEnv(\"TGEV\")} TGSQ={getEnv(\"TGSQ\")} TGCON={getEnv(\"TGCON\")} " &
      &"TGHP={getEnv(\"TGHP\")} TGSHADOW={getEnv(\"TGSHADOW\")} TGCONBURN={getEnv(\"TGCONBURN\")} " &
      &"TGEVTEAM={getEnv(\"TGEVTEAM\")} | NOTGSQ={getEnv(\"NOTGSQ\")} NOTGCON={getEnv(\"NOTGCON\")} " &
      &"NOTGHP={getEnv(\"NOTGHP\")} NOVOLUME={getEnv(\"NOVOLUME\")}"
    echo &"  bar: teams={GameTeams}  requiredWinP={(if GameTeams>2: (GameTeams.float-1.0)/GameTeams.float else: 0.5):.3f}  " &
      &"mul(solo)={tradeEdgeMul(GameTeams, 0.0):.3f}  mul(contested,c={TradeContestBurn:.2f})=" &
      &"{tradeEdgeMul(GameTeams, TradeContestBurn):.3f}   (evenTradeCost dM=" &
      &"{(if GameTeams>2: -(GameTeams.float-2.0)/(GameTeams.float-1.0) else: 0.0):.3f})"
    echo &"  SHAPE   squarePressesWhereAdditiveDeclines {tgSquarePress}   " &
      &"squareDeclinesWhereAdditivePresses {tgSquareDecl}   |  hpSymmetryFlips {tgHpFlip}" &
      &"   <= each term scored against the SAME tally, so the three never blend"
    echo &"  CONTEST evalFrames {tgEval}  contested {tgContestFrames} " &
      &"({(100.0*tgContestFrames.float/max(1,tgEval).float):.1f}%)   " &
      &"freshLocalEnemyTracksWithNOcolour {tgColorUnknown}  <= a big number here " &
      &"invalidates the CONTEST term (not the gate)"
    echo &"  FIRE    decisions(rising edge) {tgEnter}  contested {tgEnterContest}   " &
      &"heldFrames {tgDeclined}   ratio {(tgDeclined.float/max(1,tgEnter).float):.1f} " &
      &"frames/decision  <= per-FRAME rates are the 88.7%-bind trap; decisions are the unit"
    echo &"  ⚠️ WHEN  firstFireTick {tgFirstFire}   decisions by tick band: " &
      &"[0-199] {tgBucket[0]}  [200-399] {tgBucket[1]}  [400-799] {tgBucket[2]}  " &
      &"[800-1199] {tgBucket[3]}  [1200-2399] {tgBucket[4]}  [2400+] {tgBucket[5]}"
    echo "     <= the discriminating window is 200-400. A firstFireTick past ~200, " &
      "or an empty [200-399] bucket, means the gate ARMS LATE and misses the effect " &
      "however well it fires later."
    echo &"  COST    feetDropsOnALIVETarget {tgFeetDrop}   <= frames the gate took the " &
      &"CLOSE off a target the engage branch had already selected. The gun still fires; " &
      &"what is spent is the advance, and 'more early kills = +32..+42pp' is the field " &
      &"fact this has to beat."
    if tgEpsJoined > 0:
      let covPct = 100.0 * tgEarlyDeathsCovered.float / max(1, tgEarlyDeaths).float
      let covArmPct = 100.0 * tgEarlyDeathsArmedCov.float / max(1, tgEarlyDeathsArmed).float
      echo &"  ⭐ FUTILITY BOUND (eps {tgEpsJoined}, window T<={TgEarlyWindow}, " &
        &"lookback {TgFollowJoin}t)"
      echo &"     earlyDeaths {tgEarlyDeaths}  PRECEDED-BY-A-DECISION {tgEarlyDeathsCovered} " &
        &"({covPct:.1f}%)   |  on ARMED teams {tgEarlyDeathsArmed} -> " &
        &"{tgEarlyDeathsArmedCov} ({covArmPct:.1f}%)"
      echo &"     => CEILING: at most {covArmPct:.1f}% of our early lives are even " &
        &"REACHABLE by this lever. Multiply by our livesSpentBy1200 to get lives/team-Ep; " &
        &"anything the gate cannot get in front of is unreachable at ANY effect size."
      echo &"     decisions {tgDecisions} of which followed within {TgFollowJoin}t by the " &
        &"DECIDER'S OWN death {tgDecFollowedByOwnDeath} " &
        &"({(100.0*tgDecFollowedByOwnDeath.float/max(1,tgDecisions).float):.1f}%)  " &
        &"<= the same bound from the decision side"
      echo &"  ⭐ MEASURED c (the source TradeContestBurn does not have): rival deaths " &
        &"within {TgJoinRadius:.0f}px of a declined fight, next {TgFollowJoin}t —"
      echo &"     contested n={tgBurnContestN} mean {(tgBurnContestSum.float/max(1,tgBurnContestN).float):.3f}   " &
        &"solo n={tgBurnSoloN} mean {(tgBurnSoloSum.float/max(1,tgBurnSoloN).float):.3f}   " &
        &"(TGCONBURN=<contested mean> re-pins the constant with no rebuild)"
    else:
      echo "  FUTILITY BOUND: no episodes joined (build with -d:tempoprobe and run the rig)"

  when defined(doorprobe) and defined(commsprobe) and defined(ndprobe):
    # ── ⭐ UNIFIED LEVER FIRE TABLE — the 12 NOxxx-gated v56 levers in one
    # place, so nobody has to cross-reference three probe sections to answer
    # "which levers actually fired this run". ARMED reads the env exactly as
    # shippedCombatTune() does (NOxxx=1 reverts; HOTDOOR/WAVEGATE are opt-IN).
    echo "==================================================="
    echo "--- LEVER FIRE TABLE (12 NOxxx-gated v56 levers) ---"
    template armed(name: string): bool = getEnv(name).len == 0
    let hotDoorArmed = getEnv("HOTDOOR").len > 0 and getEnv("NOHOTDOOR").len == 0
    let waveGateArmed = getEnv("WAVEGATE").len > 0 and getEnv("NOWAVEGATE").len == 0
    # Re-sum from the per-(team,seat) arrays — the doorprobe report block above
    # totals these into locals (hArm/wHold/...) SCOPED to its own `when` block,
    # out of reach here, so this re-derives the same totals rather than reach
    # across a closed scope.
    var tblHotArm, tblWaveHold = 0
    for tm in 0 .. 1:
      for st in 0 .. 7:
        tblHotArm += dpHotDoorArm[tm][st]
        tblWaveHold += dpWaveHold[tm][st]
    echo &"  {\"lever\":<14} {\"env\":<12} {\"armed\":<6} {\"fires\":>10}  evidence"
    echo &"  {\"door1(seat)\":<14} {\"NODOOR1\":<12} {$armed(\"NODOOR1\"):<6} {\"n/a\":>10}  static — see per-seat role table"
    echo &"  {\"hotDoor\":<14} {\"HOTDOOR\":<12} {$hotDoorArmed:<6} {tblHotArm:>10}  hotDoorArmed (opt-IN, off by default)"
    echo &"  {\"waveGate\":<14} {\"WAVEGATE\":<12} {$waveGateArmed:<6} {tblWaveHold:>10}  waveHoldFrames (opt-IN, off by default)"
    echo &"  {\"seatFix\":<14} {\"NOSEATFIX\":<12} {$armed(\"NOSEATFIX\"):<6} {dpSeatFixDiff:>10}  diffFrames (0 by construction on <=2 teams)"
    echo &"  {\"stackConverge\":<14} {\"NOSTACKCONV\":<12} {$armed(\"NOSTACKCONV\"):<6} {csStackMove:>10}  csStackMove frames ({csStackMovePx:.0f}px total)"
    echo &"  {\"stackHoldGate\":<14} {\"NOSTACKGATE\":<12} {$armed(\"NOSTACKGATE\"):<6} {csStackGate:>10}  csStackGate frames"
    echo &"  {\"playMove\":<14} {\"NOPLAYMOVE\":<12} {$armed(\"NOPLAYMOVE\"):<6} {(csWipeMove + csLineMove):>10}  csWipeMove+csLineMove frames"
    echo &"  {\"playLatch\":<14} {\"NOPLAYLATCH\":<12} {$armed(\"NOPLAYLATCH\"):<6} {(csLatchDrop + csEchoSkip):>10}  csLatchDrop+csEchoSkip"
    echo &"  {\"eCallout\":<14} {\"NOECALL\":<12} {$armed(\"NOECALL\"):<6} {csECall:>10}  csECall emitted ({csESeed} tracks seeded)"
    echo &"  {\"staleNade\":<14} {\"NOSTALENADE\":<12} {$armed(\"NOSTALENADE\"):<6} {(ndStaleAim + ndStaleRelease):>10}  ndStaleAim+ndStaleRelease (stimulus: staleWallCamper-tracks {ndStaleSeen})"
    echo &"  {\"nadeSupply\":<14} {\"NOSUPPLY\":<12} {$armed(\"NOSUPPLY\"):<6} {ndSupplySeek:>10}  ndSupplySeek detours (stimulus: eligible-role frames {ndSupplyRole})"
    echo &"  {\"antiBunch\":<14} {\"NOBUNCH\":<12} {$armed(\"NOBUNCH\"):<6} {(ndBunchBand + ndBunchStep):>10}  ndBunchBand+ndBunchStep (stimulus: mate-inside-blast frames {ndPairFrames})"
    echo "  (comms-bus prerequisite: EMIT " & $csEmit & " — every play-executor row above is" &
      " gated behind a HEARD play, so EMIT=0 would zero all five of them regardless of their own wiring)"

  echo "==================================================="
  echo &"{games} games  seed {seed}  ticks {ticks}"
  echo &"WINS  Red {redWins}  Blue {blueWins}  Draw {draws}"
  echo &"GRABS total  Red {totRedGrab}  Blue {totBlueGrab}  (per game " &
    &"{totRedGrab/games:.1f}/{totBlueGrab/games:.1f})"
  echo &"CAPS  total  Red {totRedCap}  Blue {totBlueCap}  (per game " &
    &"{totRedCap/games:.2f}/{totBlueCap/games:.2f})"
  let
    redAcc = (if totRedShot > 0: 100.0 * totRedHit.float / totRedShot.float else: 0.0)
    blueAcc = (if totBlueShot > 0: 100.0 * totBlueHit.float / totBlueShot.float else: 0.0)
  echo &"SHOTS total  Red {totRedShot}  Blue {totBlueShot}"
  echo &"HITS  total  Red {totRedHit}  Blue {totBlueHit}"
  echo &"ACCURACY     Red {redAcc:.1f}%  Blue {blueAcc:.1f}%  " &
    &"(hits/shots — the wall-vs-body aim metric)"
  if evalTeams > 2:
    echo &"--- PER-TEAM ({evalTeams} teams; Red/Blue lines above lump teams 1.." &
      &"{evalTeams-1} into 'Blue') ---"
    const tn = ["red", "blue", "green", "yellow"]
    for t in 0 ..< evalTeams:
      let kd = (if teamDeaths[t] > 0: teamKills[t].float / teamDeaths[t].float
                else: teamKills[t].float)
      echo &"  {tn[t]:<7} wins {teamWins[t]:>2}  caps {teamCaps[t]:>2}  " &
        &"kills {teamKills[t]:>4}  deaths {teamDeaths[t]:>4}  K/D {kd:.2f}"
  echo "==================================================="
  echo "--- L2/L4 ffa4 TEMPO MANDATE SCORE (2026-08-17) ---"
  block:
    let spent = totLivesStart - totLivesHalf
    let spentFrac = (if totLivesStart > 0: spent / totLivesStart else: 0.0)
    let meanStart = totLivesStart / (games * evalTeams).float
    let meanSpent = spent / (games * evalTeams).float
    echo &"  LIVES SPENT BY TICK {FfaFixedWindow} (FIXED absolute window, arm-invariant — " &
      &"NOT K/D, NEVER accuracy): mean starting pool/team {meanStart:.2f}  " &
      &"mean SPENT/team {meanSpent:.2f}  ({100.0*spentFrac:.1f}% of the pool)"
    let capShareLate = (if totCaptures > 0:
                          100.0 * totCapturesLate.float / totCaptures.float else: 0.0)
    echo &"  CAPTURES total {totCaptures}  (per game {totCaptures.float/games.float:.2f})  " &
      &"in the FINAL 20% of the clock: {totCapturesLate} ({capShareLate:.1f}% of total)"
  when defined(shapeprobe):
    echo "--- SHAPE (engine geometry: who actually crosses the midline) ---"
    echo "team     cross/ep   deaths own   deaths enemy   own%   meanDeep   maxDeep"
    for t in 0 .. 1:
      let
        tn = (if t == 0: "red" else: "blue")
        dTot = shDeathOwn[t] + shDeathEnemy[t]
        ownPct = (if dTot > 0: 100.0 * shDeathOwn[t].float / dTot.float else: 0.0)
        meanDeep = shDeepSum[t].float / max(1, shTicks[t]).float
      echo &"{tn:<7} {shCross[t] / games:>9.2f} {shDeathOwn[t]:>12} {shDeathEnemy[t]:>14}" &
        &" {ownPct:>6.1f} {meanDeep:>10.2f} {shDeepMax[t]:>9}"
    echo "  cross/ep = own->enemy half transitions per episode; meanDeep = mean bodies"
    echo "  standing in the ENEMY half per tick (the SHAPE: 1.0 = one committed runner)."
    when defined(shapefire):
      echo "--- SHAPE LEVER FIRING (baseline-side counters) ---"
      for t in 0 .. 1:
        let tn = (if t == 0: "red" else: "blue")
        echo &"  {tn:<5} armed(seats w/ lever) {spArmed[t]:>9}  runnerFrames {spRunner[t]:>9}" &
          &"  holdFrames {spHold[t]:>9}  holdDroveTarget {spHoldFired[t]:>9}"
      echo "  holdDroveTarget must be NON-ZERO or the hold never touched a single foot."
  when defined(rngprobe):
    const bandName = ["<150", "150-300", "300-600", "600-1000", ">=1000"]
    for side in 0 .. 1:
      echo "--- RANGED CORRIDOR  team ", (if side == 0: "RED" else: "BLUE"),
        "   cappedTraverses ", rpCap[side],
        "  meanCapSlotErr ", (if rpCap[side] > 0: rpCapErr[side] / rpCap[side] else: 0.0)
      echo "band       frames     open   open%     fire   fire%  meanErrBrads  meanD"
      var tf2, to2, tfi2 = 0
      for b in 0 .. 4:
        let f = rpFrames[side][b]
        tf2 += f; to2 += rpOpen[side][b]; tfi2 += rpFire[side][b]
        let
          op = (if f > 0: 100.0 * rpOpen[side][b].float / f.float else: 0.0)
          fp = (if f > 0: 100.0 * rpFire[side][b].float / f.float else: 0.0)
          me = (if f > 0: rpErrSum[side][b].float / f.float else: 0.0)
          md = (if f > 0: rpDistSum[side][b] / f.float else: 0.0)
        echo &"{bandName[b]:>9} {f:>9} {rpOpen[side][b]:>8} {op:>7.2f} {rpFire[side][b]:>8} {fp:>7.2f} {me:>13.2f} {md:>6.0f}"
      let
        farF2 = rpFrames[side][2] + rpFrames[side][3] + rpFrames[side][4]
        farO2 = rpOpen[side][2] + rpOpen[side][3] + rpOpen[side][4]
        farFi2 = rpFire[side][2] + rpFire[side][3] + rpFire[side][4]
      echo &"    TOTAL {tf2:>9} {to2:>8} {100.0*to2.float/max(1,tf2).float:>7.2f} {tfi2:>8} {100.0*tfi2.float/max(1,tf2).float:>7.2f}"
      echo &"BEYOND300  frames {farF2}  open {farO2} ({100.0*farO2.float/max(1,farF2).float:.2f}%)  fire {farFi2}  shareOfShots {100.0*farFi2.float/max(1,tfi2).float:.2f}%"
    echo "--- RANGED CORRIDOR (all 16 bots pooled) ---"
    echo "band       frames     open   open%     fire   fire%  meanErrBrads  meanD"
    var tf, to, tfi = 0
    for b in 0 .. 4:
      let f = rpFrames[0][b] + rpFrames[1][b]
      tf += f; to += rpOpen[0][b] + rpOpen[1][b]; tfi += rpFire[0][b] + rpFire[1][b]
      let
        ob = rpOpen[0][b] + rpOpen[1][b]
        fb = rpFire[0][b] + rpFire[1][b]
        op = (if f > 0: 100.0 * ob.float / f.float else: 0.0)
        fp = (if f > 0: 100.0 * fb.float / f.float else: 0.0)
        me = (if f > 0: (rpErrSum[0][b] + rpErrSum[1][b]).float / f.float else: 0.0)
        md = (if f > 0: (rpDistSum[0][b] + rpDistSum[1][b]) / f.float else: 0.0)
      echo &"{bandName[b]:>9} {f:>9} {ob:>8} {op:>7.2f} {fb:>8} {fp:>7.2f} {me:>13.2f} {md:>6.0f}"
    echo &"    TOTAL {tf:>9} {to:>8} {100.0*to.float/max(1,tf).float:>7.2f} {tfi:>8} {100.0*tfi.float/max(1,tf).float:>7.2f}"
    let farF = rpFrames[0][2]+rpFrames[1][2]+rpFrames[0][3]+rpFrames[1][3]+rpFrames[0][4]+rpFrames[1][4]
    let farO = rpOpen[0][2]+rpOpen[1][2]+rpOpen[0][3]+rpOpen[1][3]+rpOpen[0][4]+rpOpen[1][4]
    let farFi = rpFire[0][2]+rpFire[1][2]+rpFire[0][3]+rpFire[1][3]+rpFire[0][4]+rpFire[1][4]
    echo &"BEYOND300  frames {farF}  open {farO} ({100.0*farO.float/max(1,farF).float:.2f}%)  fire {farFi}"
    echo &"SHOTSHARE  fire<150 {rpFire[0][0]+rpFire[1][0]}  fire>=300 {farFi}  share>=300 {100.0*farFi.float/max(1,tfi).float:.2f}%"
    echo &"SPINCAP    cappedFrames {rpCap[0]+rpCap[1]}  sumSlotErr {rpCapErr[0]+rpCapErr[1]}"

  when defined(wleadprobe):
    const WlTeamName = ["red   ", "blue  ", "green ", "yellow"]
    const WlBinName = ["0-100 ", "100-200", "200-300", "300-500", "500+  "]
    echo "==================================================="
    echo "--- WINDUP LEAD: gun hit rate BY RANGE BIN (-d:wleadprobe, ENGINE TRUTH) ---"
    echo &"  arm: NOWLEAD={getEnv(\"NOWLEAD\")} WLEADTICKS={getEnv(\"WLEADTICKS\")} " &
      &"WLEADSELF={getEnv(\"WLEADSELF\")} WLEADTEAM={getEnv(\"WLEADTEAM\")}"
    echo "  range is the distance to the shot's INTENDED target at the TRIGGER PULL " &
      "(the enemy closest to the locked bearing) — a MISS has no target, so a " &
      "tracer-length range cannot bin one."
    echo "  in14 = the ray passed inside PlayerHalf+BulletHalfWidth of the body at RELEASE " &
      "(the engine's own acceptance window)."
    echo "  team    bin      hits/shots     hit%    in14%   mean|perp|"
    for t in 0 ..< min(4, max(2, evalTeams)):
      for b in 0 ..< 5:
        let n = wlShots[t][b]
        if n == 0: continue
        echo &"  {WlTeamName[t]} {WlBinName[b]}  {wlHits[t][b]:>6}/{n:<6}  " &
          &"{(wlHits[t][b].float / n.float):.3f}   {(wlIn[t][b].float / n.float):.3f}   " &
          &"{(wlPerp[t][b] / n.float):>7.1f}"
      var tn = 0
      var th = 0
      for b in 0 ..< 5:
        tn += wlShots[t][b]; th += wlHits[t][b]
      if tn > 0:
        echo &"  {WlTeamName[t]} ALL     {th:>6}/{tn:<6}  {(th.float / tn.float):.3f}"

  when defined(fpprobe):
    const TeamName = ["red   ", "blue  ", "green ", "yellow"]
    echo "==================================================="
    echo "--- FFA4 LIFE ECONOMY (-d:fpprobe, GROUND TRUTH) ---"
    echo &"  arm: NOFFAMEDSEE={getEnv(\"NOFFAMEDSEE\")} NOLASTLIFE={getEnv(\"NOLASTLIFE\")} " &
      &"NOVOLUME={getEnv(\"NOVOLUME\")} NOFLAGCLOCK={getEnv(\"NOFLAGCLOCK\")} " &
      &"NOMIDGUARD8={getEnv(\"NOMIDGUARD8\")} FFA4TEAM={getEnv(\"FFA4TEAM\")} " &
      &"FFA4ONLY={getEnv(\"FFA4ONLY\")}"
    echo &"  FINGERPRINT  mask=0x{fpMask:016x}  traj=0x{fpTraj:016x}  " &
      &"games={fpGames} meanTicks={(fpTicksSum.float / max(1, fpGames).float):.0f}"
    echo &"    (mask hashes EVERY emitted button mask in (tick,slot) order; traj hashes " &
      &"ground-truth x/y/hp every {FpTrajStride} ticks. Equal on both arms => provably inert.)"
    let perTeam = max(1, numPlayers div max(2, evalTeams))
    echo &"  team    eps   livesSpentByHalf(of {perTeam * 3})  livesSpentEnd   WIPED%   " &
      &"caps/ep  lateCapShare  hp1 n  P(escape|hp1)  P(die|hp1)  heals/ep"
    for t in 0 ..< min(4, max(2, evalTeams)):
      let e = max(1, fpEps[t])
      let h1 = max(1, fpHp1Enter[t])
      echo &"  {TeamName[t]} {fpEps[t]:>5}   {(fpLivesHalf[t].float / e.float):>18.2f}   " &
        &"{(fpLivesEnd[t].float / e.float):>12.2f}   " &
        &"{(100.0 * fpWiped[t].float / e.float):>6.1f}   " &
        &"{(fpCapsTotal[t].float / e.float):>7.2f}  " &
        &"{(100.0 * fpCapsLate[t].float / max(1, fpCapsTotal[t]).float):>11.1f}%  " &
        &"{fpHp1Enter[t]:>5}  {(100.0 * fpHp1Escape[t].float / h1.float):>12.1f}%  " &
        &"{(100.0 * fpHp1Death[t].float / h1.float):>9.1f}%  " &
        &"{(fpHeals[t].float / e.float):>7.2f}"
    when defined(kselprobe):
      echo "==================================================="
      echo "--- ⭐⭐⭐ kitSel PLACEBO-CONTROLLED APPROACH (-d:kselprobe) ---"
      echo &"  arm: KITSEL={getEnv(\"KITSEL\")} KITSELTEAM={getEnv(\"KITSELTEAM\")} " &
        &"NOKITSEL={getEnv(\"NOKITSEL\")}"
      echo "  Net px CLOSED during an hp==1 segment toward a target LATCHED at onset."
      echo "  REAL = nearest STOCKED spawn. LOCKED/PHANTOM are placebos. The number"
      echo "  that matters is REAL-LOCKED: a policy that steers to kits closes px on"
      echo "  a stocked spawn and not on an empty one. ⚠️ PHANTOM is diagnostic only —"
      echo "  it sits on the contested centre column and every policy drifts there."
      echo &"  team    segs   onsetPx   REAL px   LOCKED px   PHANTOM px   REAL-LOCKED   noStocked%"
      for t in 0 ..< min(4, max(2, evalTeams)):
        let
          n = max(1, ksApN[t])
          nl = max(1, ksApNLocked[t])
          np = max(1, ksApNPhantom[t])
          mReal = ksApReal[t] / n.float
          mLock = ksApLocked[t] / nl.float
          segTot = max(1, ksApN[t] + ksApNoReal[t])
        echo &"  {TeamName[t]} {ksApN[t]:>6}   {(ksApOnset[t] / n.float):>7.1f}   " &
          &"{mReal:>7.1f}   {mLock:>9.1f}   {(ksApPhantom[t] / np.float):>11.1f}   " &
          &"{(mReal - mLock):>11.1f}   " &
          &"{(100.0 * ksApNoReal[t].float / segTot.float):>10.1f}"
      echo &"  MECHANISM  learnedSpots={ksLearned} dryBeliefs={ksDry} " &
        &"selectorFrames={ksScan} withKnownSpot={ksKnown} pickedReal={ksPickReal} " &
        &"allDryOrFar={ksDryAll}"
      echo &"  REALIZED COVERAGE  oldWouldPickPhantom={ksOldPhantomWin} " &
        &"oldHadNothing={ksOldHadNothing} destinationMOVED={ksMoved} " &
        &"...andReachable={ksMovedReachable}"
      echo &"    (coverage = destinationMOVED / selectorFrames = " &
        &"{(100.0 * ksMoved.float / max(1, ksScan).float):.1f}% — a FRAME count where the" &
        &" two arbitrations disagreed, NOT a state-class share.)"
    when defined(kselprobe):
      echo "==================================================="
      echo "--- ⭐⭐ TWO-VALUE `Team` ENUM: address error and its COST ---"
      echo "  Policy `Team = enum Red, Blue`; engine has four. Colour -> Team is"
      echo "  SLOT PARITY, so GREEN inherits RED's address and YELLOW inherits"
      echo "  BLUE's. addrErr = px from the address the policy walks to, to the"
      echo "  spawn the ENGINE gave THAT team. Grabs are crossed with TEAM SEAT"
      echo "  because ShieldRushSeat(0) dominates shield grabs and would other-"
      echo "  wise masquerade as a colour effect."
      echo "  ⚠️ ARC IS LATENT: arcSpawn is reached only via arcBreach, which is"
      echo "  `when defined(arcOn)` and unreachable in every shipped image."
      echo "  team   addrErrShield  addrErrArc   shieldGrabs(by seat 0..3)   arc"
      for t in 0 ..< min(4, max(2, evalTeams)):
        let n = max(1, ksAddrN[t])
        var shTot = 0
        var arcTot = 0
        var seats = ""
        for k in 0 ..< 4:
          shTot += ksShieldGrab[t][k]
          arcTot += ksArcGrab[t][k]
          seats.add(&"{ksShieldGrab[t][k]:>4}")
        for k in 4 ..< 8:
          shTot += ksShieldGrab[t][k]
          arcTot += ksArcGrab[t][k]
        echo &"  {TeamName[t]} {(ksAddrErrShield[t] / n.float):>12.1f} " &
          &"{(ksAddrErrArc[t] / n.float):>11.1f}   {seats}  (tot {shTot:>4})  " &
          &"{arcTot:>4}"
    echo &"  --- FIXED-WINDOW life spend (the arm-invariant comparator; " &
      &"'by half-time' moves with an episode length the lever itself changes) ---"
    echo &"  team    eps   meanEpisodeTicks   livesSpentBy1000   livesSpentBy1500   livesSpentBy2000"
    for t in 0 ..< min(4, max(2, evalTeams)):
      let e = max(1, fpEps[t])
      echo &"  {TeamName[t]} {fpEps[t]:>5}   {(fpTicksByTeam[t].float / e.float):>16.0f}   " &
        &"{(fpLivesAt[0][t].float / max(1, fpLivesAtN[0][t]).float):>16.2f}   " &
        &"{(fpLivesAt[1][t].float / max(1, fpLivesAtN[1][t]).float):>16.2f}   " &
        &"{(fpLivesAt[2][t].float / max(1, fpLivesAtN[2][t]).float):>16.2f}"
    var lh, le, ep, wp, ct, cl, e1, es, ed, hl = 0
    for t in 0 ..< min(4, max(2, evalTeams)):
      lh += fpLivesHalf[t]; le += fpLivesEnd[t]; ep += fpEps[t]; wp += fpWiped[t]
      ct += fpCapsTotal[t]; cl += fpCapsLate[t]
      e1 += fpHp1Enter[t]; es += fpHp1Escape[t]; ed += fpHp1Death[t]; hl += fpHeals[t]
    let epf = max(1, ep).float
    echo &"  ALL     {ep:>5}   {(lh.float / epf):>18.2f}   {(le.float / epf):>12.2f}   " &
      &"{(100.0 * wp.float / epf):>6.1f}   {(ct.float / epf):>7.2f}  " &
      &"{(100.0 * cl.float / max(1, ct).float):>11.1f}%  {e1:>5}  " &
      &"{(100.0 * es.float / max(1, e1).float):>12.1f}%  " &
      &"{(100.0 * ed.float / max(1, e1).float):>9.1f}%  {(hl.float / epf):>7.2f}"
    flushFile(stdout)

  when defined(ffa4probe):
    echo "==================================================="
    echo "--- FFA4 FIRE TABLE (-d:ffa4probe policy-side, DISCRIMINATING) ---"
    echo &"  POPULATION  decideFrames {f4Frames}  onFfa4Board {f4Ffa4}"
    echo &"  READBACK    selfLives() parsed {f4LivesRead} frames  " &
      &"lives hist x0={f4LivesHist[0]} x1={f4LivesHist[1]} x2={f4LivesHist[2]} " &
      &"x3={f4LivesHist[3]} x4={f4LivesHist[4]}"
    echo &"    (parsed==0 => the `lives <hp>hp x<n>` HUD marker never reached the policy " &
      &"and L3 is structurally inert, whatever its flag says.)"
    echo &"  L3 lastLifeGuard  onLastLife frames {f4OnLastLife}  |  rushGeomWanted " &
      &"{f4RushGeom}  VETOED-BY-LAST-LIFE {f4RushVetoLL}  |  medEcon commits {f4MedFire} " &
      &"(lastLife {f4MedLastLife})"
    echo &"  L1 ffaMedSee      medEcon commits {f4MedFire}  from VISIBLE family " &
      &"{f4MedPickVis}  of which OFF both formula spots {f4MedPickVisOff}  <= the " &
      &"addresses the pre-lever code could never produce"
  when defined(tempoprobe):
    echo "--- FFA4 FIRE TABLE (-d:tempoprobe, from the tempo branch) ---"
    echo &"  L2 tradeGate   eval {tgEval}  wouldPress(old margin) {tgWouldPress}  " &
      &"DECLINED-ANYWAY {tgDeclined}  <= the frames the two rules DISAGREE"
    echo "  L4 flagClock   RETIRED 2026-08-17 — see the tombstone in baseline.nim"
    flushFile(stdout)
  when defined(lifeprobe):
    echo "==================================================="
    echo "--- ffa4 LIVES PROBE (ffaMedSee/lastLifeGuard, 2026-08-17) ---"
    echo &"  arm: NOFFAMEDSEE={getEnv(\"NOFFAMEDSEE\")} NOLASTLIFE={getEnv(\"NOLASTLIFE\")} " &
      &"FFAMEDTEAM={getEnv(\"FFAMEDTEAM\")} LASTLIFETEAM={getEnv(\"LASTLIFETEAM\")}  " &
      &"(unset NOxxx + unset xTEAM = every team ships hot, GameTeams>2-gated)"
    const tn2 = ["red", "blue", "green", "yellow"]
    for t in 0 .. 3:
      if lpEpisodes[t] == 0: continue
      let totalLives = 3 * lpSeatsPerTeam[t]
      let spentAvg = lpHalfSpentSum[t] / lpEpisodes[t].float
      let allElimPct = 100.0 * lpFinalAllElim[t].float / lpEpisodes[t].float
      echo &"  {tn2[t]:<7} eps {lpEpisodes[t]:>3}  seats {lpSeatsPerTeam[t]}  " &
        &"livesSpentByHalf {spentAvg:>6.2f} of {totalLives}  " &
        &"P(all-slots-eliminated by game end) {allElimPct:>5.1f}%"
    echo "  (half-time = tick ticks/2, or game end if earlier; " &
      "all-slots-eliminated = every seat lives==0 and not alive at game end)"
    echo &"  LEVER FIRE: lastLifeGuard onLastLife-frames {llOnLastLifeFrames}  " &
      &"wantPocketRush-suppressed {llWantSuppressed}  " &
      &"widerDetour DROPPED (see tombstone)  |  " &
      &"ffaMedSee target-supplied {ffaMedFireCount}"
    echo "  (suppressed>0 proves the veto changed a real decision, not a no-op; " &
      "the widened-detour half (L3b) is DELETED — it fired 819-913x per arm and " &
      "normal cap would have missed; ffaMedSee fires>0 proves the visible-kit " &
      "union chose a target the formula-spot-only base would not have)"

  echo "==================================================="
  echo "--- CONTROL IDENTITY (FNV-1a over every emitted mask, (tick,slot) order, " &
    "+ trajectory) ---"
  echo &"  maskFnv 0x{maskFnv.toHex()}  frames {maskFrames}"
  echo "  (a lever whose NO* opt-out is a true revert reproduces this number EXACTLY " &
    "against the pre-lever commit, built in a SEPARATE nimcache)"

  when defined(msprobe):
    echo "==================================================="
    echo "--- MEDKIT HEALS (msprobe, tune-independent global — msHeals) ---"
    echo &"  woundedFrames {msWoundedFrames}  heals(wounded->full) {msHeals}  " &
      &"medkits/episode(pooled, all teams) {msHeals.float / games.float:.3f}  " &
      &"medkits/episode/team(approx, /{max(1, evalTeams)}) " &
      &"{msHeals.float / games.float / max(1, evalTeams).float:.3f}"

  when defined(shprobe):
    echo "==================================================="
    echo "--- shieldAddr: LEARNED SHIELD ADDRESS + medEncum (2026-08-20) ---"
    echo &"  arm: SHIELDADDR={getEnv(\"SHIELDADDR\")} NOSHIELDADDR={getEnv(\"NOSHIELDADDR\")}" &
      &"  MEDENCUM={getEnv(\"MEDENCUM\")} NOMEDENCUM={getEnv(\"NOMEDENCUM\")}"
    echo &"  OUTCOME (tune-independent): aliveFrames {shFrames}  shieldAcquisitions {shAcquired}" &
      &"  shields/episode(pooled) {shAcquired.float / max(1, games).float:.3f}" &
      &"  /episode/team {shAcquired.float / max(1, games).float / max(1, evalTeams).float:.3f}"
    echo &"  LEARNING: spawnsBanked {shLearned}  dryBeliefsFormed {shDry}"
    let shTot = max(1, shScan)
    echo &"  ADDRESS ARBITRATION: rushFrames {shScan}  " &
      &"pickedLEARNED {shPickLearned} ({100.0 * shPickLearned.float / shTot.float:.1f}%)  " &
      &"pickedFORMULA {shPickFormula} ({100.0 * shPickFormula.float / shTot.float:.1f}%)  " &
      &"REFUSED {shRefuse} ({100.0 * shRefuse.float / shTot.float:.1f}%)"
    echo &"  * REALIZED COVERAGE: destinationMoved {shMoved} of {shScan} rush frames " &
      &"({100.0 * shMoved.float / shTot.float:.1f}%) — frames where the address moved more " &
      &"than 12px off the old formula, or vanished. NOT a state class."
    let seTot = max(1, seWounded)
    echo &"  medEncum COVERAGE: woundedMedEconFrames(non-gear yields clear) {seWounded}  " &
      &"gear-vetoed {seWoundedGear} ({100.0 * seWoundedGear.float / seTot.float:.1f}%)"
    echo "  (a run whose REFUSED and destinationMoved are both 0 has the WRONG map family " &
      "- the defect is layout/symmetry-derived, so an arena-family board cannot score it; " &
      "use EVAL_MAPSPEC with a byte-exact hosted board)"

  when defined(wbprobe):
    echo "==================================================="
    echo "--- P(escape | hp==1) (wbprobe, tune-independent global) ---"
    let hp1Total = wbHp1Heals + wbHp1Deaths
    let escapePct = (if hp1Total > 0: 100.0 * wbHp1Heals.float / hp1Total.float else: 0.0)
    echo &"  hp1 segments resolved {hp1Total}  healedToFull {wbHp1Heals}  " &
      &"diedFromHp1 {wbHp1Deaths}  P(escape|hp==1) {escapePct:.2f}%"

  when defined(wuffprobe):
    echo "==================================================="
    echo "--- wuff: WINDUP FRIENDLY-FIRE VETO (2026-08-19) ---"
    echo &"  arm: WUFF={getEnv(\"WUFF\")} NOWUFF={getEnv(\"NOWUFF\")} " &
      &"WUFFTEAM={getEnv(\"WUFFTEAM\")} WUFFSHADOW={getEnv(\"WUFFSHADOW\")} " &
      &"WUFFAXIS={getEnv(\"WUFFAXIS\")} WUFFLEAD={getEnv(\"WUFFLEAD\")} " &
      &"WUFFSELF={getEnv(\"WUFFSELF\")} " &
      &"WUFFMATERANGE={getEnv(\"WUFFMATERANGE\")} WUFFUNION={getEnv(\"WUFFUNION\")}"
    var offTot = 0
    for v in wuffOffHist: offTot += v
    var offStr = ""
    for i in 0 .. 8:
      if wuffOffHist[i] > 0:
        offStr.add &"{i - 4:+d}:{wuffOffHist[i]} "
    echo &"  CLOCK JOIN  released gun shots matched to a policy pull frame " &
      &"{offTot}  offset histogram (botTick - triggerTick): {offStr}"
    echo "  (one sharp mode = the two clocks align and the bound below is a real " &
      "join; a smear = do NOT believe it)"
    echo &"  OUT OF REACH  friendly-fire impacts with NO engage-branch pull frame " &
      &"{wuffFfNoPull}  <= fired from another branch, this lever cannot touch them"
    echo "  Per-episode/per-team detail is on the WUFFROW lines (counts, never rates):"
    echo "  WUFFROW seed team ticks | shots enemyHits ffHits geometry | " &
      "ffJoined ffFlagA ffFlagB ffFlagC ffFlagD | cand blkA blkB blkC blkD newD " &
      "sup stale re3 re6 re12 | kills deaths caps lives"
    echo "  A = selection ray @T0   B = estAim @T0 (axis term alone)   " &
      "C = estAim + mate lead   D = C + muzzle lead   U = C OR D (the union)"

  when defined(sprayab):
    echo ""
    echo "=== SPRAYAB — carried-can conversion, per RAW ENGINE TEAM ==="
    echo "  team  epTeams  carryT   press  press/1kT  landed  land%   hits   dmg  kills  d/press  k/press   ffDmg  ffKills  ff/press"
    for t in 0 .. 3:
      if sabEps[t] == 0: continue
      let pr = max(1, sabPress[t])
      echo &"  {t:>4}  {sabEps[t]:>7}  {sabCarryT[t]:>6}  {sabPress[t]:>6}  " &
        &"{1000.0*sabPress[t].float/max(1,sabCarryT[t]).float:>9.2f}  {sabLanded[t]:>6}  " &
        &"{100.0*sabLanded[t].float/pr.float:>5.1f}  {sabHits[t]:>5}  {sabDmg[t]:>4}  " &
        &"{sabKills[t]:>5}  {sabDmg[t].float/pr.float:>7.3f}  {sabKills[t].float/pr.float:>7.3f}  " &
        &"{sabFfDmg[t]:>6}  {sabFfKills[t]:>7}  {sabFfDmg[t].float/pr.float:>8.4f}"
    echo "  (press = a RISE in arcTicksLeft, the only honest press counter;"
    echo "   land% = presses that drew >=1 spray damage inside their 5-tick window;"
    echo "   ff/press = friendly hp per press — the cost side of a wider gate.)"
  when defined(aoeprobe):
    echo "==================================================="
    echo "--- AoE FRIENDLY-FIRE VETO (-d:aoeprobe, 2026-08-19) ---"
    echo &"  arm: NADEFF={getEnv(\"NADEFF\")} NONADEFF={getEnv(\"NONADEFF\")} " &
      &"SPRAYFF={getEnv(\"SPRAYFF\")} NOSPRAYFF={getEnv(\"NOSPRAYFF\")} " &
      &"NADEFFTEAM={getEnv(\"NADEFFTEAM\")} SPRAYFFTEAM={getEnv(\"SPRAYFFTEAM\")}"
    echo &"  games {games}  teams {evalTeams}  team-episodes {aoTeamEps}"
    let te = max(1, aoTeamEps).float
    echo "  --- ENGINE TRUTH: damage in HIT POINTS (the finding's own unit) ---"
    echo &"    gun     ff {aoGunFf:>6}  all {aoGunAll:>7}  ff/team-Ep {aoGunFf.float/te:>7.3f}"
    echo &"    spray   ff {aoSprayFf:>6}  all {aoSprayAll:>7}  ff/team-Ep {aoSprayFf.float/te:>7.3f}"
    echo &"    grenade ff {aoNadeFf:>6}  all {aoNadeAll:>7}  ff/team-Ep {aoNadeFf.float/te:>7.3f}" &
      &"   (self-blast, excluded from ff: {aoNadeSelf})"
    let aoeFf = aoSprayFf + aoNadeFf
    let allFf = aoGunFf + aoeFf
    echo &"    AoE share of all friendly fire: {aoeFf}/{allFf} = " &
      &"{(if allFf > 0: 100.0*aoeFf.float/allFf.float else: 0.0):.1f}%"
    echo "  --- POLICY FUNNEL (lever-INDEPENDENT: both arms score the same world) ---"
    echo &"    grenade  candidate impact points {nfCand}   dropped-by-armed-veto {nfCandVeto}"
    var line = "      ...of which a mate is in the burst, by slack px:"
    for k in 0 ..< AoeSlackN:
      line &= &"  {AoeSlack[k]:+.0f}={nfCandHot[k]}"
    echo line
    echo &"    grenade  RELEASES {nfRelease}   held-by-armed-veto(ticks) {nfHoldTicks}" &
      &"   threw-anyway-at-cap {nfHoldBail}"
    line = "      ...of which a mate is in the burst AT BURST, by slack px:"
    for k in 0 ..< AoeSlackN:
      line &= &"  {AoeSlack[k]:+.0f}={nfReleaseHot[k]}"
    echo line
    echo &"    spray    PRESSES {sfPress}   declined-by-armed-veto {sfVeto}"
    line = "      ...of which a mate is in the wedge, by slack px:"
    for k in 0 ..< AoeSlackN:
      line &= &"  {AoeSlack[k]:+.0f}={sfPressHot[k]}"
    echo line
    echo "  --- FUTILITY BOUND (join of the ledger to the burst it produced) ---"
    echo &"    grenade bursts {aoNadeThrows}  joined to a release row {aoNadeMatched}" &
      &"  (unjoined ff {aoNMissFf} foe {aoNMissFoe} — a broken join, NOT a cold throw)"
    echo &"      VETO-HOT throws {aoNHotN}: friendly {aoNHotFf} hp REACHED, " &
      &"enemy {aoNHotFoe} hp FORGONE"
    echo &"      cold     throws {aoNColdN}: friendly {aoNColdFf} hp OUT OF REACH, " &
      &"enemy {aoNColdFoe} hp kept"
    echo &"    spray damage ticks {aoSprayEv}  joined to a press {aoSprayMatched}" &
      &"  (unjoined ff {aoSMissFf} foe {aoSMissFoe})"
    echo &"      VETO-HOT: friendly {aoSHotFf} hp REACHED, enemy {aoSHotFoe} hp FORGONE"
    echo &"      cold    : friendly {aoSColdFf} hp OUT OF REACH, enemy {aoSColdFoe} hp kept"
    let reach = aoNHotFf + aoSHotFf
    let cost = aoNHotFoe + aoSHotFoe
    echo &"    => AoE friendly hp the veto REACHES {reach} of {aoeFf} " &
      &"({(if aoeFf > 0: 100.0*reach.float/aoeFf.float else: 0.0):.1f}%), " &
      &"enemy hp it FORGOES {cost}  (exchange {(if cost > 0: reach.float/cost.float else: 0.0):.2f} " &
      "friendly hp saved per enemy hp given up)"
    echo "    (REACHED is the CEILING for this geometry+perception. A cold burst that " &
      "still hurt a mate is one the mate track was too stale or too wrong to predict — " &
      "raise slack, not the flag.)"
    flushFile(stdout)

when isMainModule:
  main()
