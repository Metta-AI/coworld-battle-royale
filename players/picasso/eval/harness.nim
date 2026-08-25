## Headless in-process A/B eval harness for Coworld CTF.
##
## Runs a full 8v8 game with no websocket, no real-time clock: the engine
## wrapper builds each slot's real fogged sprite packet, this driver feeds it
## into a real ProtocolClient and runs the SHIPPED baseline `decide()` — the
## byte-identical decision path — then steps the sim. Reports per-team kills /
## captures / shots / wins so it is BOTH the "do they actually hit" accuracy
## proof AND the A/B rig (control = baseline on both sides).
##
## The baseline player module is `include`d (not imported) so this driver sees
## its private `Bot`, `decide`, `roleForSeat`, `spawnAim`, and the per-frame
## bookkeeping constants (`AimRate`, `AimBrads`) WITHOUT editing the shipped
## file. Its `when isMainModule` block stays dormant here. The engine lives
## behind `harness_engine`, whose primitive-typed surface keeps the engine's
## `Team`/`enemy`/`flagHome` from colliding with the baseline's own.
##
## Usage:
##   nim c -d:release --opt:speed -o:players/baseline/eval/harness.out \
##     players/baseline/eval/harness.nim
##   ./players/baseline/eval/harness.out --games 20 --seed 7 --ticks 10000
##
## Env knobs let a forked "hunter" A/B against baseline without a rebuild:
##   HUNTER_SLOTS="0,2,4,..."  -> which slots run the hunter policy (Red seats
##                                are even). Unset => all-baseline control run.

import std/[os, random, strutils, strformat, math]
import ./harness_engine

when defined(lkprobe):
  import std/algorithm     # median of the switch-separation ledger

# The shipped baseline bot, included verbatim. `isMainModule` is false here so
# its runBot entrypoint never fires; we drive `decide` directly.
include "../baseline.nim"

when defined(maskhash):
  # ⭐ -d:maskhash (ported from maxwell/leveraudit 80e7667): FNV-1a over EVERY
  # emitted mask in (tick, slot) order plus the hp/lives trajectory. The ONLY
  # accepted proof that a "behaviour-neutral" edit really is byte-identical.
  # ⚠️ SEPARATE --nimcache per arm: a shared cache has faked an identity match.
  var mhHash: uint64 = 14695981039346656037'u64
  var mhMasks = 0
when defined(maskfp):
  # ⭐⭐⭐ CONTROL IDENTITY, the house method (-d:maskfp). Two independent
  # fingerprints, because either one alone can lie:
  #   * maskFp  — FNV-1a over EVERY emitted button mask in (tick, slot) order.
  #     This is the DECISION channel: it moves the instant any bot presses a
  #     different button, even if the world has not diverged yet.
  #   * trajFp  — FNV-1a over the engine's own gameHash() after every advance().
  #     This is the WORLD channel: positions, velocities, aim, hp, lives, flags,
  #     pickup timers. A mask fingerprint cannot see a divergence that has not
  #     yet reached a button; a state hash cannot distinguish "same world" from
  #     "different decision that happened not to matter this tick".
  # ⚠️ Each arm MUST be built into its OWN --nimcache. A shared nimcache has
  # faked an identity match in this tree before.
  ## Both are reset PER EPISODE and echoed as an FPGAME line, then folded into
  ## the run-wide accumulators. Per-seed lines are what let two arms be compared
  ## as "identical on N/N seeds" and name the FIRST seed that diverges, instead
  ## of collapsing the whole batch into one bit of information.
  var
    maskFp = 14695981039346656037'u64
    trajFp = 14695981039346656037'u64
    gMaskFp = 14695981039346656037'u64
    gTrajFp = 14695981039346656037'u64
  proc fpMix(h: var uint64, v: uint64) =
    h = h xor v
    h = h * 1099511628211'u64

when defined(lkprobe):
  # ⭐ THE SWITCH LEDGER — the OWN INSTRUMENT for the lockPos fix, and the only
  # thing this lever may be gated on. It is built here, in the harness, and not in
  # the policy, because the whole defect is that the POLICY HAS NO TARGET IDENTITY:
  # scoring "did we switch off a live body" from another Vec match would inherit
  # exactly the ambiguity under test. The engine has identity, so the ledger reads
  # ground truth (slotPos/alive) and attributes the bot's own committed aim
  # (bot.lockPos, refreshed to the engage target every frame) to the NEAREST live
  # enemy body. Counted identically in both arms.
  const
    LkSwitchWindow = 20        ## ticks — the field instrument's own gap window
  var
    lkPrevTgt: array[64, int]
    lkPrevTick: array[64, int]
    lkOpp = 0                  ## frames where we re-picked with the previous
                               ## target STILL ALIVE (the denominator)
    lkSwitch = 0               ## ...of those, frames where the pick CHANGED body
    lkSwitchInside = 0         ## ...of those switches, new body <=60px from old
    lkSepSum = 0.0
    lkSeps: seq[float]

var
  campTicksRed = 0        ## diagnostic: ticks a RED bot spent frozen (<0.8px
  campTicksBlue = 0       ## moved) while holding a live enemy track — the
                          ## "grind a corner / camp" pathology, tallied per team.

type
  BotDriver = object
    bot: Bot
    client: ProtocolClient
    lastMask: uint8
    navBuilt: bool
    rng: Rand              ## this bot's OWN RNG stream, isolated per slot.

proc newDriver(slot, team, episodeSeed: int, tune: CombatTune): BotDriver =
  ## Mirrors runBot's setup for one seat: role from seat, a fresh
  ## ProtocolClient, transient reset, and — critically — a PER-BOT RNG.
  ##
  ## Hosted bots run as SEPARATE processes with independent streams
  ## (`randomize(slot*7919+1)`); giving each driver its own `Rand` (swapped
  ## into the global around `decide`) reproduces that isolation, so one bot's
  ## draws never perturb another's — the interleaving a single shared global
  ## stream would introduce.
  ##
  ## CTF gameplay is fully input-deterministic (the sim's own `rng` field is
  ## never consumed), and the bots seed by SLOT only — so a fixed seating
  ## replays bit-identically every episode. To get per-episode variety for a
  ## statistically meaningful batch WITHOUT breaking the paired A/B (both the
  ## baseline control and a hunter must face IDENTICAL conditions so only the
  ## swapped decisions differ), the episode seed salts every seat's stream.
  ## Team: raw ENGINE team index (0 Red / 1 Blue / 2 Green / 3 Yellow).
  ##
  ## ⭐⭐ RIG-FIDELITY FIX (2026-08-20, the homeSign audit). This used to read
  ## `if team == 0: Red else: Blue`, which collapses EVERY non-zero engine team
  ## to Blue. The hosted policy does not do that: `runBot` seeds `bot.team` from
  ## SLOT PARITY (`slot mod 2 == 0 -> Red`), and the engine deals colours round
  ## the teams in enum order (`roster.nim teamForSlot: Team(order mod
  ## teamCount())`), so colour-index parity IS slot parity and green (index 2)
  ## gets Red in the field, not Blue.
  ##
  ## The collapse therefore handed GREEN the wrong `homeSign` on every 4-team
  ## rig episode ever run here — measured on six real hosted mapSpecs before the
  ## fix: green INVERTED on 46,401 of 46,401 frames, red/blue/yellow correct on
  ## all of theirs. That is a defect this RIG manufactures and the field does not
  ## have: it is the "a mirror rig can LACK the disease" trap running backwards,
  ## and it will fabricate a positional finding on any 4-team A/B measured here.
  ## 2-team is untouched: `team mod 2` and `team == 0` agree exactly on {0, 1}.
  let t = (if team mod 2 == 0: Red else: Blue)
  let role = roleForSeat(clamp(slot div 2, 0, 7), t)
  result.bot = Bot(slot: slot, team: t, role: role, tune: tune)
  result.bot.resetTransient()
  result.client = initProtocolClient()
  result.lastMask = 0xff'u8
  result.navBuilt = false
  result.rng = initRand(slot * 7919 + 1 + episodeSeed * 1_000_003)

proc frame(driver: var BotDriver, packet: string): uint8 =
  ## One frame for one bot: feed the packet, run runBot's per-frame preamble
  ## (tick advance, aim dead-reckon, lobby gate, nav build), then `decide`.
  ## Returns the chosen button mask (level mask, same as the live wire value).
  let bot = driver.bot
  let client = driver.client
  if not client.feedInProcessPacket(packet):
    return driver.lastMask                 # malformed frame: hold last input.
  let advance = max(1, client.frameAdvance)
  bot.tick += advance
  bot.estAim = floorMod(bot.estAim + bot.rotSign * AimRate * advance, AimBrads)
  if not client.mapCameraReady:
    bot.resetTransient()                   # lobby / game-over interstitial.
    return driver.lastMask
  if not driver.navBuilt and client.walkabilityReady:
    bot.buildNavGrid(client)
    driver.navBuilt = true
  # Swap this bot's private RNG into the global stream `decide` draws from,
  # then save it back — each seat consumes its OWN sequence (buildNavGrid above
  # is rand-free, so it needs no swap).
  randState() = driver.rng
  result = bot.decide(client)
  driver.rng = randState()
  driver.lastMask = result
  # Diagnostic: is this bot frozen (~0.6s of no movement) while it holds a
  # fresh enemy track? That is the "grind a corner / camp while it has someone
  # to shoot" pathology. decide() maintains stuckTicks; a fresh enemy is one
  # seen within FreshShotTicks.
  if bot.stuckTicks >= 15:
    for t in bot.enemies:
      if bot.tick - t.lastSeen <= FreshShotTicks:
        if bot.team == Red: inc campTicksRed else: inc campTicksBlue
        break

proc parseSlotSet(spec: string): seq[int] =
  for part in spec.split(','):
    let s = part.strip()
    if s.len > 0:
      result.add(parseInt(s))

proc envFloat(name: string, dflt: float): float =
  let v = getEnv(name)
  if v.len > 0: parseFloat(v.strip()) else: dflt

proc envInt(name: string, dflt: int): int =
  let v = getEnv(name)
  if v.len > 0: parseInt(v.strip()) else: dflt

proc deadKnob(name, why: string) =
  ## ⛔ A/B KNOB THAT CANNOT MOVE ANYTHING — the fourth way a lever goes dark
  ## (tests/test_lever_liveness.nim, guard 4). The harness used to expose these
  ## as ordinary `envInt` overrides for CombatTune fields the policy does not
  ## read, so setting one produced a run that was byte-identical to its control
  ## and the A/B reported "no effect" instead of "not wired". FAIL LOUD instead:
  ## a null you cannot distinguish from a no-op is worse than a crash.
  if getEnv(name).len > 0:
    quit("⛔ " & name & " is a DEAD A/B knob and this run would have been a " &
      "guaranteed null.\n   " & why & "\n   (lever-liveness audit 2026-08-20; " &
      "remove the env var to run the intended control.)", 2)

proc hunterTune(): CombatTune =
  ## The hunter's fire/engage knobs. Starts from the baseline default and
  ## sharpens the FIRE DISCIPLINE that the ground-truth diagnosis blamed for
  ## the ~80% miss rate: (1) stop shooting at stale linearly-extrapolated
  ## phantoms of juking targets, (2) require the aim to settle tighter inside
  ## the 14px corridor before pulling. Every field is overridable by an env
  ## var (HUNT_* ) so hypotheses A/B without a rebuild. Defaults below encode
  ## the leading hypothesis; a control-vs-hunter run isolates their effect.
  # SHIPBASE=1 starts the hunter from the SHIPPED v3 champion (commit + aimLock +
  # unstuckEngaged + carrierGrabDetect) instead of the pure baseline, so a v4 A/B
  # can layer ONLY the new SEAL4 levers on top of v3 — the candidate = v3 + v4,
  # the control = v3 (CONTROL_SHIPPED=1), so the run isolates the v4 delta alone.
  result = (if envInt("SHIPBASE", 0) != 0: shippedCombatTune() else: defaultCombatTune())
  # Knob sweep (both directions of fire-discipline were falsified 2026-07-14 —
  # defaults now sit at the baseline so a SMART run isolates the LOGIC change).
  result.freshShotTicks = envInt("HUNT_FRESH", FreshShotTicks)
  result.fireSlackPx = envFloat("HUNT_SLACK", FireSlackPx)
  result.leadTicks = envFloat("HUNT_LEAD", LeadTicks)
  result.combatDeadband = envInt("HUNT_DEAD", CombatDeadband)
  result.fireRange = envFloat("HUNT_RANGE", FireRange)
  # Fork 1 — target commitment. SMART=1 turns it on; HUNT_COMMIT sweeps the
  # priority credit for the locked target. The default is the value ALREADY in
  # `result` — so under SHIPBASE=1 (start = v3 champion) an unset SMART keeps the
  # shipped commit=true instead of silently reverting it to baseline. (This
  # reverts the void v4 run where SHIPBASE=1 still stripped the v3 core because
  # SMART/AIMLOCK/UNSTUCK/GRABFIX defaulted to 0.)
  result.commit = envInt("SMART", (if result.commit: 1 else: 0)) != 0
  result.commitBonus = envFloat("HUNT_COMMIT", CommitBonus)
  # Fork 2 — local force balance ("don't feed a 1-vs-N"). BALANCE=1 turns it
  # on; HUNT_MARGIN sweeps the outnumber threshold (2 => retreat at 1v3 / 2v4).
  result.forceBalance = envInt("BALANCE", 0) != 0
  result.outnumberMargin = envInt("HUNT_MARGIN", OutnumberMargin)
  # Fork 3 — corner-grind BUG FIX: allow the stuck-jink to fire while engaged.
  # Default = the value already in `result` (shipped=true under SHIPBASE=1).
  result.unstuckEngaged = envInt("UNSTUCK", (if result.unstuckEngaged: 1 else: 0)) != 0
  # SEAL gunfighter forks (2026-07-14). SEAL=1 turns the whole bundle on; each
  # also has its own env override so an A/B can isolate a single lever. aimLock
  # defaults to its shipped value so SHIPBASE=1 keeps the v3 lock unless SEAL/
  # AIMLOCK explicitly moves it.
  let seal = envInt("SEAL", 0) != 0
  result.aimLock = envInt("AIMLOCK", (if seal or result.aimLock: 1 else: 0)) != 0
  result.huntSweep = envInt("HUNT", (if seal: 1 else: 0)) != 0
  result.fireOnRealBody = envInt("REALBODY", (if seal: 1 else: 0)) != 0
  result.threatFacingBonus = envInt("THREATFACE", (if seal: 1 else: 0)) != 0
  result.unstuckEngaged = result.unstuckEngaged or seal
  # Comms + awareness forks (2026-07-15). SHOUT=1 turns the whole bundle on
  # (emit + react + callouts + oh-shit + die + damage-aware); each lever also
  # has its own env override so an A/B isolates one at a time. shout is the
  # master EMIT switch; reactContact is the master RECEIVE switch. The Picasso
  # champion (shippedCombatTune) still runs with all of these OFF until an A/B
  # proves one, so control vs SHOUT run isolates the whole comms layer.
  let comms = envInt("SHOUT", 0) != 0
  # Each shout flag defaults to its SHIPPED value (the vanity emitters shout/
  # shoutSurprise/shoutDie are ON in the v4 champion), so SHIPBASE=1 KEEPS them
  # unless SHOUT/the per-flag knob moves it — same void-A/B fix as the v3 core
  # and SEAL4 levers. shoutCallout (strategic) stays shipped-off.
  result.shout = envInt("SHOUT_EMIT", (if comms or result.shout: 1 else: 0)) != 0
  result.shoutCallout = envInt("SHOUT_CALLOUT", (if comms or result.shoutCallout: 1 else: 0)) != 0
  result.shoutSurprise = envInt("SHOUT_SURPRISE", (if comms or result.shoutSurprise: 1 else: 0)) != 0
  result.shoutDie = envInt("SHOUT_DIE", (if comms or result.shoutDie: 1 else: 0)) != 0
  result.reactContact = envInt("REACT", (if comms: 1 else: 0)) != 0
  result.damageAware = envInt("DMGAWARE", (if comms: 1 else: 0)) != 0
  # COMMS BUS (C1/C2, 2026-07-22, Track B): event-driven scenario codewords over
  # the shout channel. COMMS=1 turns on the full bus (emit + adopt); the per-part
  # knobs bisect it. commsBus emits, commsPlay adopts a heard play (needs playbook),
  # commsCrypto rotates the codeword table. All default OFF (not in shippedCombatTune)
  # so SHIPBASE=1 keeps the champion byte-identical unless a knob moves it. This is a
  # COORDINATION lever: the mirror can only prove no-regression + liveness + graceful
  # degradation — the real edge is a hosted mixed-field xreq (REF-comms). A/B:
  # SHIPBASE=1 COMMS=1 vs CONTROL_SHIPPED=1 (on BOTH seatings).
  let comms2 = envInt("COMMS", 0) != 0
  result.commsBus = envInt("COMMSBUS", (if comms2 or result.commsBus: 1 else: 0)) != 0
  result.commsPlay = envInt("COMMSPLAY", (if comms2 or result.commsPlay: 1 else: 0)) != 0
  result.commsCrypto = envInt("COMMSCRYPTO", (if comms2 or result.commsCrypto: 1 else: 0)) != 0
  # commsPlay extends the playbook flank machinery, so turn playbook on when adopting.
  if result.commsPlay: result.playbook = true
  # Shout-reaction GATE fork (2026-07-16). CALLGATE=1 turns the distraction bar
  # on: a heard callout still SEEDS the enemy track (intel is always banked), but
  # the REACTION (turn the cone / move the feet) must clear a task-priority gate —
  # a committed carrier/grabber banks and keeps going, only a free gun chases.
  # Requires REACT (something to gate). Default = shipped value, so SHIPBASE=1
  # keeps whatever the champion runs unless CALLGATE explicitly moves it.
  result.calloutGate = envInt("CALLGATE", (if result.calloutGate: 1 else: 0)) != 0
  # Aim-dot threat (2026-07-16, task #19). AIMTHREAT=1 replaces the coarse
  # facingRight half-plane in the dangerScore block with a precise gun-on-me cone
  # read from the enemy's aim-dot line. Mirror-measurable (both teams render aim
  # dots). Default = shipped value so SHIPBASE=1 keeps the champion unless
  # AIMTHREAT moves it; requires DANGER (dangerScore) on to have a block to sharpen.
  result.aimThreat = envInt("AIMTHREAT", (if result.aimThreat: 1 else: 0)) != 0
  # Capture-conversion fork (2026-07-15). CARRIERFLEE=1: a carrier keeps moving
  # home while engaged instead of advancing into a point-blank enemy — targets
  # the drop@home~2% leak (carriers die AT the robbed pedestal, in the respawn
  # nest). Isolated so an A/B measures grab->cap% directly.
  result.carrierFlee = envInt("CARRIERFLEE", 0) != 0
  # ⛔ CLEARBAND — DEAD KNOB, removed 2026-08-20. It armed `carrierClearBand`,
  # whose v47 remnant was an if/else with two byte-identical arms, so the knob
  # could not move a mask on any board. Field deleted; see the tombstone in
  # baseline.nim's carrier-home branch.
  deadKnob("CLEARBAND",
    "carrierClearBand's body was deleted in v47; the flag guarded an if/else " &
    "whose two arms were byte-identical, so this A/B could never differ from " &
    "its control. The field is gone — there is nothing left to arm.")
  # SPRINT=1: carrier NEVER enters combat (engage 0). Survival instrumentation
  # showed carriers live ~110t but travel ~4% of the run — PINNED firing at the
  # invulnerable spawn-protected respawner (wasted shots) while advancing into
  # the nest instead of running. Drop combat: pure-navigate home at full speed.
  # FALSIFIED (net -3): the gun buys survival; a pure runner dies faster.
  result.carrierSprint = envInt("SPRINT", 0) != 0
  # SCREEN=1: the rear escort body-blocks the respawn cone at the carrier's EXACT
  # y (one body toward the robbed pocket) so the invulnerable respawner's shot
  # kills the ESCORT, not the carrier. The one mechanism the self-play mirror
  # can't cancel — a friendly body on the ray is physics. Coordination lever.
  result.carrierScreen = envInt("SCREEN", 0) != 0
  # GRABFIX=1: the wakeup deadlock fix. The self-carry test only fired when the
  # heart was >16px off its pedestal; a carrier standing ON the robbed pedestal
  # keeps the heart ~7px away so iCarry stayed FALSE and the bot camped the
  # pedestal it already robbed until timeout (hosted replays: our carrier frozen
  # at the enemy pedestal 67-75% of a game -> a DRAW that should have been a win).
  # Recognize carry via the auto-pickup invariant (living player in pickup range
  # of an un-carried pedestal heart is instantly the carrier). Asymmetric fix, so
  # a seat-rotated self-play A/B CAN measure it (unlike the six combat levers).
  # ⛔ GRABFIX — DEAD KNOB, removed 2026-08-20. `carrierGrabDetect` was
  # STILLBORN: it shipped true with ZERO read sites in every shipped build
  # (`git log --all -S "tune.carrierGrabDetect"` -> one commit, 80e7f87, not an
  # ancestor of HEAD). The fix described above is real and STILL ACTIVE — it
  # ships as the unconditional constant `CarrySelfRadius = 26.0`, so it is not
  # switchable and never was. Any A/B run through GRABFIX was a guaranteed null.
  deadKnob("GRABFIX",
    "carrierGrabDetect has no read site in baseline.nim and never had one in a " &
    "shipped build; the wakeup-deadlock fix it names ships unconditionally as " &
    "CarrySelfRadius = 26.0. Nothing to toggle.")
  # SEAL/CQB v4 bundle (2026-07-16). SEAL4=1 turns the whole set on; each lever
  # also has its own env override so a regression can be bisected without a
  # rebuild. The Picasso v4 champion runs all six ON together (shippedCombatTune),
  # so each defaults to its SHIPPED value: SHIPBASE=1 KEEPS the v4 levers unless
  # SEAL4/the per-lever knob explicitly moves it. (Same void-A/B fix as the v3
  # core knobs — a "start from shipped then override" default of 0 would silently
  # STRIP the six levers from the candidate that claims to build on them.)
  let seal4 = envInt("SEAL4", 0) != 0
  result.dangerScore       = envInt("DANGER",   (if seal4 or result.dangerScore: 1 else: 0)) != 0
  result.twoSpeedScan      = envInt("TWOSCAN",  (if seal4 or result.twoSpeedScan: 1 else: 0)) != 0
  result.boundingOverwatch = envInt("BOUND",    (if seal4 or result.boundingOverwatch: 1 else: 0)) != 0
  # HOLDVSGUN / STICKYCOMMIT / SMARTGRAB / ARMEDRUSH (2026-07-24 dive-death + focus-fire fixes).
  # Default to shipped value so SHIPBASE keeps them unless the knob moves it; the A/B toggles them.
  result.holdVsGun         = envInt("HOLDVSGUN", (if result.holdVsGun: 1 else: 0)) != 0
  result.stickyCommit      = envInt("STICKYCOMMIT", (if result.stickyCommit: 1 else: 0)) != 0
  result.smartGrab         = envInt("SMARTGRAB", (if result.smartGrab: 1 else: 0)) != 0
  result.armedRush         = envInt("ARMEDRUSH", (if result.armedRush: 1 else: 0)) != 0
  # DIVEFIX=1 turns on the whole dive-death bundle at once (the shipped fix set) for a clean A/B.
  if envInt("DIVEFIX", 0) != 0:
    result.smartGrab = true; result.armedRush = true
    result.holdVsGun = true; result.stickyCommit = true
  # CARRIER-RUN survival levers (2026-07-24 grab->cap conversion leak). Individual knobs + a
  # CARRIERFIX bundle so the A/B can isolate the carrier fixes from the dive fixes.
  result.carrierFlee       = envInt("CARRIERFLEE", (if result.carrierFlee: 1 else: 0)) != 0
  result.carrierSerpentine = envInt("CARRIERSERP", (if result.carrierSerpentine: 1 else: 0)) != 0
  result.escortRun         = envInt("ESCORTRUN", (if result.escortRun: 1 else: 0)) != 0
  result.carrierScreen     = envInt("CARRIERSCREEN", (if result.carrierScreen: 1 else: 0)) != 0
  if envInt("CARRIERFIX", 0) != 0:
    result.carrierFlee = true; result.carrierSerpentine = true
    result.escortRun = true; result.carrierScreen = true
  result.pointOfDomination = envInt("DOMINATE", (if seal4 or result.pointOfDomination: 1 else: 0)) != 0
  result.tempoPress        = envInt("TEMPO",    (if seal4 or result.tempoPress: 1 else: 0)) != 0
  result.fireSuperiority   = envInt("FIRESUP",  (if seal4 or result.fireSuperiority: 1 else: 0)) != 0
  # Carry-conversion forks (2026-07-17, round-624 decode). Each targets ONE of the
  # two field-confirmed carry failures and is NOT in shippedCombatTune (untested),
  # so under SHIPBASE=1 both default OFF — an unset knob keeps the champion, ESCORTRUN
  # /HUNTCARRIER explicitly move them. A/B: SHIPBASE=1 CONTROL_SHIPPED=1 vs +one knob.
  #   ESCORTRUN=1 — the KILL case (ep 3dcdd7eb): interpose on the midfield threat->carrier ray.
  #   HUNTCARRIER=1 — the OUT-RACE case (ep 8b6b080e): keep chasing the exposed enemy carrier.
  result.escortRun    = envInt("ESCORTRUN",   (if result.escortRun: 1 else: 0)) != 0
  result.huntCarrier  = envInt("HUNTCARRIER", (if result.huntCarrier: 1 else: 0)) != 0
  # v14 combat-parity levers ported onto the live engine (2026-07-18). preSlew =
  # "fire first" OODA half-beat: bias target-pick toward the enemy whose gun points
  # most OFF us. staggerFire = staggered bounding: hold to overwatch only when a
  # covering mate's muzzle is down (muzzle-bloom read). Both default OFF (not in
  # shippedCombatTune); unproven on this engine, so A/B before shipping.
  result.preSlew      = envInt("PRESLEW",     (if result.preSlew: 1 else: 0)) != 0
  result.staggerFire  = envInt("STAGGERFIRE", (if result.staggerFire: 1 else: 0)) != 0
  # regroupPush (2026-07-18): post-wipe consolidation — hold a shallow rally when
  # over-extended alone into a cleared enemy half, then push deep with the re-formed
  # wave (fixes the v14 "feed the respawn wave piecemeal" squander). COORDINATION
  # lever: the mirror gives both teams the regroup (benefit cancels) and its clean-
  # wipe trigger barely occurs in self-play — validate on a hosted/asymmetric field.
  result.regroupPush  = envInt("REGROUP",     (if result.regroupPush: 1 else: 0)) != 0
  # grabTiming (2026-07-20, the dive-death finding): hold the unarmed pedestal dive
  # when the pocket is STACKED and a covering mate is inbound (96% of our carrier
  # deaths are at the pedestal, 0% cap in every loss). Default OFF (not in shipped
  # Tune); asymmetric so the mirror measures grab->cap, but the "vs a real stacked
  # defense" edge is field-only. A/B: SHIPBASE=1 GRABTIMING=1 vs CONTROL_SHIPPED=1.
  # ⛔ GRABTIMING — DEAD KNOB, removed 2026-08-20. See the grabTiming tombstone
  # in baseline.nim: smartGrab superseded both hard-threshold gates and their
  # read sites went with them, so the field is declared but never read.
  deadKnob("GRABTIMING",
    "grabTiming has ZERO read sites in baseline.nim — smartGrab replaced it. " &
    "Every A/B ever run through this knob was a guaranteed null. Sweep the " &
    "smartGrab standoff instead.")
  # holdLine (2026-07-22, the h006 line-defense finding): the OPPOSITE trigger to
  # regroupPush — rally a shallow wave when over-extended into the enemy half AND a
  # fresh enemy LINE is to our front AND we lack local fire-superiority, so the mid hits
  # the line together instead of trickling in one body at a time to be farmed. Default
  # OFF (not in shippedCombatTune); COORDINATION lever, so the mirror gives both teams
  # the hold and part of the benefit cancels — validate the edge on a hosted/asymmetric
  # field. A/B: SHIPBASE=1 HOLDLINE=1 vs CONTROL_SHIPPED=1 (on BOTH seatings).
  result.holdLine     = envInt("HOLDLINE",     (if result.holdLine: 1 else: 0)) != 0
  # grabGate (2026-07-22, the h006 grab-discipline finding): gate the unarmed pedestal
  # open on LOCAL fire-superiority around the pocket (hold when fresh enemy guns near
  # the pedestal outnumber fresh mates by >= GrabGateDeficit — the diagnosed suicide-grab
  # state, 72-82% of our carriers die there). Default OFF (not in shippedCombatTune);
  # asymmetric so the mirror measures grab->cap. A/B: SHIPBASE=1 GRABGATE=1 vs CONTROL_SHIPPED=1.
  # ⛔ GRABGATE — DEAD KNOB, removed 2026-08-20. Same cause as GRABTIMING.
  deadKnob("GRABGATE",
    "grabGate has ZERO read sites in baseline.nim — smartGrab replaced it. " &
    "Every A/B ever run through this knob was a guaranteed null. Sweep the " &
    "smartGrab numbers gate instead.")
  # medTopOff (2026-07-20, v9 med-kit): a wounded, out-of-contact bot detours to a
  # visible center med kit (heals to full on a 12px touch; a healthy bot never
  # consumes one, so the kit is never wasted). Pure-upside MOVEMENT lever, default
  # OFF (not in shippedCombatTune) so SHIPBASE=1 keeps the champion unless MEDKIT=1
  # turns it on. Asymmetric survival edge (the healthier survivor wins the next
  # contact) so the mirror measures it. A/B: SHIPBASE=1 MEDKIT=1 vs CONTROL_SHIPPED=1.
  result.medTopOff    = envInt("MEDKIT",      (if result.medTopOff: 1 else: 0)) != 0
  # ── SEAL-lens v9 bundle (2026-07-20, the unabsorbed-doctrine backlog top tier).
  # Each defaults OFF (not in shippedCombatTune) so SHIPBASE=1 keeps the champion
  # unless the knob turns it on. A/B: SHIPBASE=1 <KNOB>=1 vs CONTROL_SHIPPED=1.
  #   SATCAP     — distributed-fire saturation cap (backlog #2)
  #   NOMASK     — don't-mask-fires, mover-side (backlog #3)
  #   ASSAULT    — near-ambush assault-through (backlog #6)
  #   OFFCONE    — off-cone approach bearing (backlog #4; needs aimThreat)
  #   FUNNEL     — defensive fatal-funnel pre-aim (backlog #5; mirror-PARTIAL)
  result.satCap         = envInt("SATCAP",  (if result.satCap: 1 else: 0)) != 0
  result.noMask         = envInt("NOMASK",  (if result.noMask: 1 else: 0)) != 0
  result.assaultThrough = envInt("ASSAULT", (if result.assaultThrough: 1 else: 0)) != 0
  result.offCone        = envInt("OFFCONE", (if result.offCone: 1 else: 0)) != 0
  result.fatalFunnel    = envInt("FUNNEL",  (if result.fatalFunnel: 1 else: 0)) != 0
  # AIMROT (2026-07-20): restore ALL aim-intel reads (observedAim resync,
  # mateAimBrads focus-fire rays, enemy aimBrads for aimThreat/preSlew) from
  # the v9 soldier rotation-sprite ids — the "aim dot" labels those reads were
  # built on were RETIRED in GameVersion 7, so the champion has been running
  # the degraded facingRight fallbacks live. Default OFF (not in shipped tune).
  # A/B: SHIPBASE=1 AIMROT=1 vs CONTROL_SHIPPED=1.
  result.aimRotRead     = envInt("AIMROT",  (if result.aimRotRead: 1 else: 0)) != 0
  # counterArc (Play C, GameVersion 15): prioritize a disarmed enemy plasma-arc
  # carrier beyond 136px. Default OFF (not in shippedCombatTune) so SHIPBASE=1
  # keeps the champion unless COUNTERARC=1. Needs dangerScore (sharpens it).
  # A/B: SHIPBASE=1 COUNTERARC=1 vs CONTROL_SHIPPED=1 (full v16), seat-rotated.
  result.counterArc     = envInt("COUNTERARC", (if result.counterArc: 1 else: 0)) != 0
  # arcStandoff (2026-08-07): the MOVEMENT companion to counterArc — back off a DISARMED
  # enemy arc-carrier to just past its 136px cone (ArcStandoffRing 196px) and keep shooting,
  # since one cone touch == MaxHp == instant death while its own gun is dead for life.
  # Movement-intent only; requires COUNTERARC (same sprite read) so ARCSTANDOFF=1 alone is
  # inert by design. Default = shipped value (ON) so SHIPBASE=1 keeps it unless ARCSTANDOFF=0.
  # Verify not-blind with -d:asoprobe (asoNear>0 = carriers came in range; asoBack>0 = the
  # feet reacted; asoInCone should fall vs the lever OFF).
  result.arcStandoff    = envInt("ARCSTANDOFF", (if result.arcStandoff: 1 else: 0)) != 0
  # arcAlways (DIAGNOSTIC ONLY, 2026-08-07): arm the breacher unconditionally, ignoring the
  # line-memory gate. Never shipped (shippedCombatTune never sets it); exists solely so the
  # ARCFOE rig below can field a real cone for arcStandoff to react to in self-play.
  result.arcAlways      = envInt("ARCALWAYS", (if result.arcAlways: 1 else: 0)) != 0
  # arcBreach (2026-07-22, anti-line OFFENSE): on a called line the fixed breacher
  # seat grabs the plasma arc and cones the cluster. Default = shipped value so
  # SHIPBASE=1 keeps it unless ARCBREACH moves it. Needs commsPlay (the line read).
  result.arcBreach      = envInt("ARCBREACH", (if result.arcBreach: 1 else: 0)) != 0
  # gv21Press (2026-07-23): widen the fire-superiority break threshold (press through a
  # 1-gun deficit) for the GV21 kill-economy. Default = shipped value; GV21PRESS moves it.
  result.gv21Press      = envInt("GV21PRESS", (if result.gv21Press: 1 else: 0)) != 0
  # shieldRush (2026-07-23): the rusher pre-grabs our own endzone shield → carries home
  # at 6 HP (the grab→cap conversion fix). Mirror-measurable via grab->cap. SHIELDRUSH
  # moves it; default = shipped value. Reaches only HUNTER_SLOTS seats (per-team A/B).
  result.shieldRush     = envInt("SHIELDRUSH", (if result.shieldRush: 1 else: 0)) != 0
  # planLayer (2026-07-23): the contingency state machine (teamPhase). PLANLAYER moves
  # it; default = shipped value. A/B: SHIPBASE=1 CONTROL_SHIPPED=1 PLANLAYER=0 (hunters
  # strip the plan) vs shipped-on control → a NEGATIVE hunter delta means the plan helps.
  result.planLayer      = envInt("PLANLAYER", (if result.planLayer: 1 else: 0)) != 0
  # v7 sword/shield adaptation (2026-07-19). avoidDisarm is the pure-downside fix
  # (mirror-measurable via SS-PROBE pickup count → ~0); shieldTank/swordAmbush are
  # coordination/positional levers, validate hosted. Knobs reach only HUNTER_SLOTS.
  result.avoidDisarm  = envInt("AVOIDDISARM", (if result.avoidDisarm: 1 else: 0)) != 0
  result.shieldTank   = envInt("SHIELDTANK",  (if result.shieldTank: 1 else: 0)) != 0
  result.swordAmbush  = envInt("SWORDAMBUSH", (if result.swordAmbush: 1 else: 0)) != 0
  # v7 BUNDLE ISOLATION (2026-07-17). These six shipped together in v7 (all true
  # in shippedCombatTune) and won rounds 621/624, but were NEVER A/B'd one at a
  # time — so we can't say which earn their place or bisect a regression. Unlike
  # escortRun/huntCarrier (field-only triggers), these are asymmetric geometry
  # levers the mirror CAN measure. Each defaults to its SHIPPED value, so under
  # SHIPBASE=1 the champion is intact unless a knob explicitly STRIPS one lever.
  # Isolation A/B: candidate = SHIPBASE=1 <KNOB>=0 (champion MINUS that lever),
  # control = CONTROL_SHIPPED=1 (full champion). If the minus-side LOSES on both
  # seatings, the lever earns its place; flat/positive => it doesn't (or hurts).
  result.carrierHomeStretch = envInt("HOMESTRETCH", (if result.carrierHomeStretch: 1 else: 0)) != 0
  result.chaseThief         = envInt("CHASETHIEF",  (if result.chaseThief: 1 else: 0)) != 0
  result.cornerPreAim       = envInt("CORNERAIM",   (if result.cornerPreAim: 1 else: 0)) != 0
  result.sentryDisplace     = envInt("SENTRYDISP",  (if result.sentryDisplace: 1 else: 0)) != 0
  result.topBias            = envInt("TOPBIAS",     (if result.topBias: 1 else: 0)) != 0
  result.playbook           = envInt("PLAYBOOK",    (if result.playbook: 1 else: 0)) != 0
  # ── v29 CONTINGENCY-MACHINE DEEPENING (2026-07-29). Two loose ends the v21 design doc
  # flagged and v26 only half-closed. Each is isolated so a seat-rotated A/B measures ONE.
  # DEFTEETH=1: PhDefend's recapture collapse aims at the REAL thief fix (bot.carrierPos)
  # instead of v26's mateCarryPos — which is our own mate carrying the ENEMY heart, and
  # (0,0) when nobody carries, so the collapse degenerated to "walk to mid at my height".
  result.defendTeeth = envInt("DEFTEETH", 0) != 0
  # FORCETIME=1: move the PhForce trigger off the never-firing 3800 (MEASURED 0 frames of
  # 266k — GV23 games end by wipe at mean 2410t). FORCE_TICK sweeps the replacement so the
  # constant gets an actual sweep rather than a second guess.
  result.forceTiming = envInt("FORCETIME", 0) != 0
  result.forceClockTick = envInt("FORCE_TICK", ForceClockTickTuned)

when defined(ohshitprobe):
  var ohshitTotal = 0
  var ohshitEnemyClose = 0   # nearest ENEMY within 95px at emit
  var ohshitMateCloser = 0   # a teammate was closer than the nearest enemy

when defined(ssprobe):
  # v7-only: does the UNADAPTED Picasso bot accidentally grab a sword/shield
  # (auto-pickup on touch => canFire=false, silent disarm)? Count alive-ticks
  # spent holding each, split Red/Blue, plus the number of distinct pickup
  # EVENTS (a rising edge of possession). If these are ~0 the auto-disarm risk
  # is marginal; if material, avoidance is urgent.
  var ssRedSwordTk = 0
  var ssBlueSwordTk = 0
  var ssRedShieldTk = 0
  var ssBlueShieldTk = 0
  var ssRedSwordEv = 0
  var ssBlueSwordEv = 0
  var ssRedShieldEv = 0
  var ssBlueShieldEv = 0
  var ssAliveTk = 0
  var ssPrevSword: array[64, bool]
  var ssPrevShield: array[64, bool]

when defined(canprobe):
  # -d:canprobe: engine-truth spray-can possession, to sit beside the policy's
  # own cpGate/cpSeen/cpSeek funnel. Held-ticks and rising-edge pickup EVENTS,
  # split Red/Blue so a one-sided A/B (HUNTER_SLOTS) is readable.
  var cpRedHeldTk = 0
  var cpBlueHeldTk = 0
  var cpRedPickEv = 0
  var cpBluePickEv = 0
  var cpAliveTk = 0
  var cpPrevCan: array[64, bool]

when defined(wkprobe):
  # -d:wkprobe (kept permanently — utility-weapon kill-share audit tool):
  # per-team, per-weapon KILL totals across the whole run, drained from the
  # engine's tier-2 event stream. Never spray_use.amount (always 0).
  var wkRedGun, wkBlueGun, wkRedSpray, wkBlueSpray, wkRedNade, wkBlueNade: int

when defined(ndprobe):
  # -d:ndprobe (2026-08-14, the v56 nade package): ENGINE-TRUTH totals for
  # throws / supply / blast multiplicity, plus a ground-truth mate-spacing
  # histogram. The policy-side counters live in baseline.nim; these are the
  # ones that answer "did the FIELD move", not "did the bot believe".
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

when defined(rangehitprobe):
  # -d:rangehitprobe (2026-08-07, v45 A/B reporting): range-banded shots/hits
  # per PER-GAME (not just pooled) so the caller can compute accuracy VARIANCE
  # across games, not just an aggregate mean — that per-game spread is the
  # study's own key metric (ours measured 24pp vs daveey's 3pp).
  var rhGameNearPct: seq[tuple[seed: int, redPct, bluePct: float,
    redShots, redHits, blueShots, blueHits: int]]

when defined(v59ab):
  ## The episode's engine-truth split, stashed here because `engine` is local to
  ## runEpisode and EpisodeResult is a shared type this lane must not widen.
  var v59EpDeathEnemy, v59EpDeathOwn, v59EpDeathSelf: array[4, int]
  var v59EpMed, v59EpShield, v59EpCan: array[4, int]
  var v59EpKills, v59EpCaps, v59EpLives: array[4, int]
  var v59EpWinner = -1

proc runEpisode(seed, maxTicks, numPlayers: int, hunterSlots: seq[int]):
    EpisodeResult =
  ## Runs one headless game. Seats listed in hunterSlots run the HUNTER tune
  ## (sharpened fire discipline); every other seat runs the baseline default.
  ## With no hunterSlots this is the all-baseline control (byte-identical to
  ## the shipped decide), so paired seeds isolate the hunter's fire discipline.
  let
    engine = newEvalEngine(numPlayers, seed, maxTicks)
    # HUNTER_MATEPOS=1 (2026-08-07, v45 Audit-2 A/B): repurposes the existing
    # hunterSlots per-slot-tune mechanism to isolate JUST the mate-pos proxy —
    # hunterSlots' side gets shippedCombatTune() with mateAimPos forced true,
    # every other field identical to the (CONTROL_SHIPPED=1) control side, so
    # the ONLY delta between the two arms is the satCap/FocusFireBonus/noMask
    # input channel the proxy replaces. Distinct from hunterTune() (a totally
    # different fire-discipline hypothesis) — existing HUNT_* workflows are
    # untouched unless this flag is set.
    huntTune =
      if envInt("V59BUNDLE", 0) != 0:
        # ⭐⭐⭐ THE v59 BUNDLE A/B (integration lane, 2026-08-21).
        #
        # THE PROBLEM THIS SOLVES. Every v59 lever is armed inside
        # `shippedCombatTune()` off the PROCESS env, and this rig runs all 16
        # bots in ONE process — so a bare run arms BOTH sides and the "A/B" is a
        # mirror that reports symmetry by construction. That is the
        # WUFFTEAM / NADEFFTEAM / SPRAYCONETEAM trap, one level up: the same
        # re-stamp, but for the whole bundle at once.
        #
        # THE RECIPE, and every part of it is load-bearing:
        #   NOVOLUME=1 NOSPRAYCONE=1 NOSPRAYFIRST=1 NORAIDFRAME=1 NOWLEAD=1 \
        #   NOLOCKONE=1 CONTROL_SHIPPED=1 SHIPBASE=1 V59BUNDLE=1 \
        #   HUNTER_SLOTS=<red or blue seats> harness.out --games 30
        # The NO* opt-outs put `shippedCombatTune()` — and therefore the CONTROL
        # side under CONTROL_SHIPPED=1 — at the exact v58 tune. This block then
        # re-stamps the bundle back ON for the HUNTER seats only. Control = v58,
        # candidate = v58 + the bundle, one process, paired seeds.
        # ⚠️ ASSIGNMENT, never an OR: with the levers ON by default an OR would
        # leave both sides hot and silently restore the mirror.
        #
        # ── MEASURED, n=30/arm, 2026-08-21 (this recipe, seeds 4000-4029, all
        # three arms verified 30/30 complete). PAIRED WITHIN-COLOUR vs the NULL,
        # which removes the seat bias instead of averaging over it:
        #                        RED seating      BLUE seating     sign
        #   wins                   +11 (4.0σ)       +2 (0.7σ)      BOTH +
        #   deaths BY ENEMY *      -77 (-11.3%)    -21 (-3.3%)     BOTH -
        #   shots                 -267 (-7.9%)    -367 (-10.0%)    BOTH -
        #   hit rate             +3.66pp          +1.69pp          BOTH +
        #   lives at end          +135             +43             BOTH +
        #   kills / captures / grabs / medkits     MIXED SIGN — no claim
        # Seat-adjusted mean win delta +6.5; binomial σ at n=30 = 2.74. The null
        # arm's own RED-BLUE split is -6 wins, i.e. BLUE is the STRONGER seat and
        # the bundle's gain lands almost entirely on the WEAK one (+11 vs +2).
        # That asymmetry is the honest caveat on this result, not a footnote.
        #
        # ⚠️ THE woundedBank CHECK, and the bundle PASSES it. Deaths are split by
        # WHO FIRED. Enemy-inflicted deaths fall on BOTH seatings, while own-team
        # kills are 2.1% of all deaths and move in OPPOSITE directions (+6 / -5).
        # So the survival gain is NOT this rig's ~8x-inflated friendly fire being
        # thinned out — it is enemy-inflicted deaths actually falling. Pooled
        # deaths would not have separated those, and that error shipped a lever
        # on a false premise once already.
        #
        # ⚠️ GAME LENGTH MOVES: the candidate arms run +8.0% / +9.4% LONGER than
        # the null. Any per-game RATE computed without the null arm is wrong.
        #
        # ── ⭐⭐⭐ THE 4-TEAM RESULT, n=30/arm, hosted ffa4 board ms1.json,
        # EVAL_TEAMS=4 EVAL_SCORING=pot, all three arms VERIFIED 30/30 unique
        # seeds. THIS is the arm that can see tradeGate and raidFrame. Arm P arms
        # raw teams 0+2, arm Q arms 1+3, each team contrasted against ITSELF in
        # the null so the 8.9/8.9/23.2/58.9% slot-block unfairness cancels
        # exactly rather than being averaged over.
        #                 T0      T1      T2      T3    sign agreement
        #   wins          +0      +9      +9      +4    3 of 4 +, NONE negative
        #   deathsByENEMY -10     -33     -28     -12   ALL FOUR NEGATIVE *
        #   livesEnd      +2      +46     +54     +24   ALL FOUR POSITIVE
        #   sprayCans     +6      +8      +7      +8    ALL FOUR POSITIVE
        #   kills         -5      +47     +57     -3    mixed — no claim
        #   captures      -2      +5      +9      +3    3 of 4 +
        #   medkits       -6      +3      +2      -4    mixed — no claim
        # Summed over the four armed teams: wins +22, deathsByENEMY -83.
        #
        # ⚠️ THE woundedBank CHECK PASSES HERE TOO. Friendly fire is 1.7% of all
        # deaths in the null and the armed teams' own-team kills SUM DOWN (-8), so
        # the survival gain is enemy-inflicted deaths falling, not this rig's
        # inflated friendly fire being thinned and misread as survival.
        #
        # ⚠️ GAME LENGTH MOVES THE OTHER WAY ON ffa4: armed arms run SHORTER
        # (62,809 / 65,479 vs the null's 69,171 = -9.2% / -5.3%) and carry FEWER
        # draws (3 / 2 vs 6). On 2-team the same bundle made games LONGER. Two
        # different boards, two different signs — which is exactly why a per-game
        # rate is only meaningful against the null arm of the SAME board family.
        #
        # ⚠️ T0 IS THE CEILING CASE, and it is the honest caveat: it gains ZERO
        # wins. T0 also wins 14 of 30 in the null, i.e. it is already the dominant
        # seat on this board, and the same pattern appears on 2-team (the strong
        # seat gains +2, the weak seat +11). The bundle lifts weak seats; it does
        # not lift an already-winning one.
        #
        # ⛔ WHAT THIS DOES *NOT* DO: isolate tradeGate or raidFrame individually.
        # All five tune levers are armed together here. Their INDIVIDUAL evidence
        # is the mask-fingerprint differential (each NOxxx arm diverges from the
        # bundle), which proves not-dark, not good. This run scores the BUNDLE on
        # the board family that matters.
        #
        # ⛔ THIS 2-TEAM RUN CANNOT SEE tradeGate OR raidFrame. Both are gated on
        # GameTeams > 2; measured on the default board, tradeGate's guard is
        # evaluated 8,501 times and true ZERO times. The number above is the
        # bundle MINUS those two and minus lockOne. Use the EVAL_TEAMS=4 recipe.
        # ⛔ `lockOne` IS NOT IN THIS LIST, on purpose — it is a separate lever
        # from a separate merge (lockfix) and folding it in would contaminate
        # this bundle's attribution. ⚠️ CORRECTION (2026-08-20 migration): this
        # comment used to say lockOne "IS NOT A CombatTune field... process-wide
        # and COMMON-MODE across both arms" and that claim is now FALSE — it was
        # migrated off the per-frame `getEnv("NOLOCKONE")` decide() read and onto
        # the tune panel (see baseline.nim's field doc), and it CAN now be
        # re-stamped per seat: HUNTER_LOCKONE=1 below, or LOCKONETEAM=<n> in
        # grabprobe. It stays out of THIS recipe only because nobody has re-run
        # the win-delta A/B with it folded in yet, not because it is unreachable.
        # With NOLOCKONE=1 in the recipe it is still OFF on both sides here, i.e.
        # this A/B scores the bundle MINUS lockfix. lockfix's own evidence is
        # its -d:lkprobe switch ledger, not this win delta. Stated here so
        # nobody reads the bundle number as covering it.
        var t = shippedCombatTune()
        t.tradeGate = true            # NOVOLUME  (the v59 default-ON flip)
        t.sprayConeFire = true        # NOSPRAYCONE
        t.sprayFireFirst = true       # NOSPRAYFIRST
        t.raidFrame = true            # NORAIDFRAME
        t.windupLead = WLeadTicks     # NOWLEAD, both halves of wlead
        t.windupSelfLead = WLeadSelfTicks
        t
      elif envInt("HUNTER_MATEPOS", 0) != 0:
        var t = shippedCombatTune()
        t.mateAimPos = true
        t
      elif envInt("HUNTER_LOCKONE", 0) != 0:
        # ⭐⭐⭐ lockOne HUNTER_SLOTS ISOLATION (2026-08-20, the CombatTune
        # migration). lockOne now lives in the tune panel, but
        # shippedCombatTune() still reads NOLOCKONE off the PROCESS env — the
        # SAME env both `baseTune` and `huntTune` read, so without an explicit
        # re-stamp it stays common-mode across the HUNTER_SLOTS partition. Same
        # trap as WLEADTEAM/RAIDFRAMETEAM, one level up: per-SLOT here instead
        # of per-TEAM. Same shape as HUNTER_MATEPOS just above: run with
        # CONTROL_SHIPPED=1 NOLOCKONE=1 (forces the base tune's lockOne OFF)
        # HUNTER_LOCKONE=1 HUNTER_SLOTS=<seats>, and this branch re-stamps
        # ONLY the hunter seats back on — every other field stays identical to
        # the control side.
        var t = shippedCombatTune()
        t.lockOne = true
        t
      else: hunterTune()
  # CONTROL_SHIPPED=1 makes the CONTROL side the full SHIPPED v3 champion, so a
  # v4 A/B pits (v3 + SEAL4) against v3 alone — the ONLY delta is the six new
  # levers. Takes precedence over CONTROL_COMMIT.
  var baseTune =
    if envInt("CONTROL_SHIPPED", 0) != 0: shippedCombatTune()
    else: defaultCombatTune()
  # CONTROL_COMMIT=1 gives the CONTROL side target commitment too, so an A/B
  # isolates a NEW fork (e.g. force balance) as the ONLY delta from the current
  # shipped Picasso (which already runs commit). Left off => pure-baseline control.
  if envInt("CONTROL_COMMIT", 0) != 0:
    baseTune.commit = true
  # TURTLE=1 (2026-07-22): force the CONTROL (non-hunter) team to hold its own half —
  # every control seat becomes a defensive post (HomeDefender / Overwatch spread) so it
  # stays home and lets the HUNTER team over-push into it. NOT a faithful h006, just a
  # standing-line stand-in so we can confirm holdLine's trigger FIRES against a held line
  # (the mirror can't produce a line — both teams attack — so holdLine fires ~0 there).
  # Diagnostic only; win-rate vs a turtle is not a league signal, the HL-PROBE fire is.
  let turtle = envInt("TURTLE", 0) != 0
  # ARCFOE=1 (2026-08-07): force the CONTROL team to field an ARMED plasma-arc carrier —
  # its breacher seat runs arcBreach with the line-memory gate removed (arcAlways), so it
  # grabs the arc and walks the cone at us all game. Same diagnostic class as TURTLE: the
  # mirror otherwise produces NO enemy arc-carrier at all (no opponent policy grabs one),
  # so arcStandoff would read as blind for want of a stimulus rather than a real defect.
  # Win-rate under ARCFOE is not a league signal — the ASO-PROBE funnel is the reading.
  if envInt("ARCFOE", 0) != 0:
    baseTune.arcBreach = true
    baseTune.arcAlways = true
  var drivers: seq[BotDriver]
  for slot in 0 ..< engine.playerCount():
    let tune = (if slot in hunterSlots: huntTune else: baseTune)
    var d = newDriver(slot, engine.teamOfSlot(slot), seed, tune)
    if turtle and slot notin hunterSlots:
      # Defensive spread over the control team's 8 seats: 3 home-choke guards + 5
      # overwatch posts fanned across the lanes = a body wall in its own half.
      #
      # TURTLE_STACK=1 (2026-08-14, the staleNade stimulus): make EVERY control
      # seat a HomeDefender instead. They all post on the same chokeSpot, so the
      # control team stands as a BUNCHED, stationary, cover-backed knot rather
      # than a fanned line — the wall-camper CLUSTER the plain TURTLE spread
      # deliberately never produces (its Overwatch posts are spaced by design).
      # Same diagnostic class as TURTLE/ARCFOE: a rig to field a stimulus the
      # mirror cannot generate, NOT a league signal. The ND-PROBE funnel is the
      # reading, never the win rate.
      let teamSeat = clamp(slot div 2, 0, 7)
      d.bot.role =
        if envInt("TURTLE_STACK", 0) != 0: HomeDefender
        elif teamSeat mod 8 in [0, 3, 7]: HomeDefender
        else: Overwatch
    drivers.add(d)

  when defined(ndprobe):
    ndReleases.setLen(0)     # the release ledger is per-EPISODE (joined below)
  when defined(maskfp):
    maskFp = 14695981039346656037'u64
    trajFp = 14695981039346656037'u64
  when defined(lkprobe):
    for i in 0 ..< lkPrevTgt.len:      # the ledger is per-EPISODE: a target
      lkPrevTgt[i] = -1                # index must never carry across boards
      lkPrevTick[i] = -1000
  var tick = 0
  when defined(hscensus):
    var hsPrevDeaths: array[32, int]
    for s in 0 ..< min(32, drivers.len):
      hsPrevDeaths[s] = engine.hsVitals(s).deaths
  when defined(hscensus):
    var hsPrevPos: array[32, Vec]
  while engine.isPlaying() and tick < maxTicks:
    when defined(hscensus):
      for s in 0 ..< min(32, drivers.len):
        hsStgLive[s] = false
        # Position BEFORE this frame's decide runs and before the sim advances:
        # the closure test below has to compare the same frame's target against
        # the step the sim actually took, or it measures an off-by-one.
        let v0 = engine.hsVitals(s)
        hsPrevPos[s] = vec(v0.x, v0.y)
    for slot in 0 ..< drivers.len:
      let packet = engine.frameFor(slot)
      let mask = drivers[slot].frame(packet)
      when defined(maskhash):
        # FNV-1a over EVERY emitted mask in (tick, slot) order + the body
        # trajectory, so a control arm can be proved byte-identical.
        mhHash = mhHash xor uint64(mask); mhHash = mhHash * 1099511628211'u64
        mhHash = mhHash xor uint64(tick and 0xffff); mhHash = mhHash * 1099511628211'u64
        mhHash = mhHash xor uint64(slot); mhHash = mhHash * 1099511628211'u64
        let ls = engine.slotLifeState(slot)
        mhHash = mhHash xor uint64(ls.hp * 8 + ls.lives); mhHash = mhHash * 1099511628211'u64
        inc mhMasks
      when defined(maskfp):
        maskFp.fpMix(uint64(tick) * 1000003'u64 + uint64(slot))
        maskFp.fpMix(uint64(mask))
      when defined(lkprobe):
        block:
          let b = drivers[slot].bot
          # `engage >= 0` this frame <=> the commit lock was refreshed to THIS
          # tick (baseline.nim only writes lockUntil = tick + LockTtl there), so
          # this reads the chosen target without touching the shipped file.
          var tgt = -1
          if b.tune.commit and b.lockUntil == b.tick + LockTtl:
            var best = 1e18
            for o in 0 ..< engine.playerCount():
              if engine.teamOfSlot(o) == engine.teamOfSlot(slot): continue
              let q = engine.slotPos(o)
              if not q.alive: continue
              let dd = (q.x - b.lockPos.x) * (q.x - b.lockPos.x) +
                       (q.y - b.lockPos.y) * (q.y - b.lockPos.y)
              if dd < best:
                best = dd
                tgt = o
          if tgt >= 0:
            let prev = lkPrevTgt[slot]
            if prev >= 0 and tick - lkPrevTick[slot] <= LkSwitchWindow:
              let pv = engine.slotPos(prev)
              if pv.alive:                     # the field's own denominator:
                inc lkOpp                      # a re-pick with the old body LIVE
                if tgt != prev:
                  let nv = engine.slotPos(tgt)
                  let sep = sqrt((nv.x - pv.x) * (nv.x - pv.x) +
                                 (nv.y - pv.y) * (nv.y - pv.y))
                  inc lkSwitch
                  lkSepSum += sep
                  lkSeps.add(sep)
                  if sep <= LockMatchDist: inc lkSwitchInside
            lkPrevTgt[slot] = tgt
            lkPrevTick[slot] = tick
      engine.setMask(slot, mask)
      # Forward any shout the bot staged this frame, exactly as runBot's WS loop
      # sends chatBlob(shoutWant): the sim buffers it and delivers it to audible
      # mates on the next frame build. Clearing mirrors the shipped path.
      when defined(ohshitprobe):
        if drivers[slot].bot.shoutWant == "oh shit!":
          let (nE, nM) = engine.nearestEnemyMate(slot)
          inc ohshitTotal
          if nE <= 95.0: inc ohshitEnemyClose
          if nM < nE: inc ohshitMateCloser
      if drivers[slot].bot.shoutWant.len > 0:
        engine.applyShout(slot, drivers[slot].bot.shoutWant)
        drivers[slot].bot.shoutWant = ""
    engine.advance()
    when defined(hscensus):
      # ⭐ CONSEQUENCE AT ENGINE TRUTH. Coverage first (how many frames is a seat
      # actually being steered at the mis-placed staging point), then the death
      # ledger, then WHERE each death happened relative to that point. A state
      # -class share is not a bound; only the deaths the fix could actually touch
      # are.
      for s in 0 ..< min(32, drivers.len):
        if hsStgLive[s]:
          hsStgEngTick[s] = tick
          if tick < 200: inc hsStgFrames[0]
          elif tick < 400: inc hsStgFrames[1]
          elif tick < 1200: inc hsStgFrames[2]
          # ⭐⭐ DOES THE STAGING POINT MOVE ANYBODY? Engine truth, this frame's
          # own target against this frame's own step. If the answer is "no",
          # the whole raid-frame lever is moot and should be said so out loud.
          block:
            let
              vNow = engine.hsVitals(s)
              pNow = vec(vNow.x, vNow.y)
              d0 = dist(hsPrevPos[s], hsStgPos[s])
              d1 = dist(pNow, hsStgPos[s])
              step = dist(hsPrevPos[s], pNow)
            hsStgClosePx += (d0 - d1)
            hsStgSpeedPx += step
            if d0 - d1 > 0.05: inc hsStgClose
            elif d0 - d1 < -0.05: inc hsStgFar
            else: inc hsStgFlat
        let v = engine.hsVitals(s)
        if v.deaths > hsPrevDeaths[s]:
          hsPrevDeaths[s] = v.deaths
          if tick < 1200:
            inc hsDeaths
            if tick >= 200 and tick < 400: inc hsDeaths24
            let d = vec(v.x, v.y)
            # OUTSIDE our own territory? (nearest stated endzone is not ours)
            var cell: array[3, int]
            if hsMyColor[s].len > 0:
              hsClassifyCell(cell, d, hsMyColor[s], hsRaidColor[s])
              if cell[0] == 0: inc hsDeathsAway
            # AT / EN ROUTE to the staging point this seat was last sent to.
            if hsStgTick[s] >= 0:
              let
                a = hsStgFrom[s]
                b = hsStgPos[s]
                ab = b - a
                l2 = dot(ab, ab)
              if dist(d, b) <= 200.0:
                inc hsDeathsAtStg
              elif l2 > 1.0:
                let t = clamp(dot(d - a, ab) / l2, 0.0, 1.0)
                if t >= 0.15 and dist(d, a + ab * t) <= 150.0:
                  inc hsDeathsEnRoute
            # ⭐ THE HONEST REALIZED COVERAGE. The two tests above are too
            # strict by construction: the staging target is REWRITTEN every
            # frame, so `hsStgFrom` is this frame's own position and the
            # "en route" segment collapses to the remaining path — a death at
            # the seat's current position lands at t~0 and is filtered out.
            # The question the fix can actually answer is not "did we die on a
            # line" but "were we UNDER THIS TARGET'S CONTROL when we died":
            # was the mis-placed staging point the seat's nav goal within the
            # last 30 ticks. That, and only that, is the set of deaths a
            # re-keyed staging point could have moved.
            if tick - hsStgEngTick[s] <= 30:
              inc hsDeathsUnderStg
              if tick >= 200 and tick < 400: inc hsDeathsUnderStg24
              if hsMyColor[s].len > 0 and cell[0] == 0:
                inc hsDeathsUnderStgAway
    when defined(maskfp):
      trajFp.fpMix(engine.stateHash())
    when defined(canprobe):
      for slot in 0 ..< drivers.len:
        let sp = engine.sprayOf(slot)
        if not sp.alive:
          cpPrevCan[slot] = false   # a death DROPS the can; do not re-count it
          continue
        inc cpAliveTk
        let red = engine.teamOfSlot(slot) == 0
        if sp.can:
          if red: inc cpRedHeldTk else: inc cpBlueHeldTk
          if not cpPrevCan[slot]:
            if red: inc cpRedPickEv else: inc cpBluePickEv
        cpPrevCan[slot] = sp.can
    when defined(ssprobe):
      for slot in 0 ..< drivers.len:
        let ss = engine.swordShieldOf(slot)
        if not ss.alive: continue
        inc ssAliveTk
        let red = engine.teamOfSlot(slot) == 0
        if ss.sword:
          if red: inc ssRedSwordTk else: inc ssBlueSwordTk
          if not ssPrevSword[slot]:
            if red: inc ssRedSwordEv else: inc ssBlueSwordEv
        if ss.shield:
          if red: inc ssRedShieldTk else: inc ssBlueShieldTk
          if not ssPrevShield[slot]:
            if red: inc ssRedShieldEv else: inc ssBlueShieldEv
        ssPrevSword[slot] = ss.sword
        ssPrevShield[slot] = ss.shield
    when defined(ndprobe):
      let sp = engine.ndSpacingSample()
      ndSpaceBots += sp.bots
      ndSpaceUnder += sp.underBlast
      ndSpaceSum += sp.sumNearest
      for b in 0 ..< sp.hist.len: ndSpaceHist[b] += sp.hist[b]
    inc tick
  when defined(ndprobe):
    # ENGINE TRUTH + the stale-vs-fresh DISCRIMINATION join. A gate must
    # discriminate, not just fire: score the stale exception on the SPREAD
    # between converting and whiffing throws, not on trigger count.
    let recs = engine.ndGrenadeRecs()
    for r in recs:
      case r.kind
      of 0:
        if r.team in 0 .. 3: inc ndThrows[r.team]
      of 2:
        if r.team in 0 .. 3: inc ndPickups[r.team]
      of 1:
        var hit = 0
        var bunch = false
        for t in 0 .. 3:
          if t == r.team: continue         # a self-blast is not a punish
          hit += r.victims[t]
          if r.victims[t] >= 2: bunch = true
        if hit > 0:
          inc ndImpactDmg
          ndVictims += hit
          if bunch: inc ndImpactBunch
      else: discard
    # Join the policy release ledger to the engine's throws PER SEAT, in order
    # (a release IS the throw, so the two sequences align 1:1 per slot); then
    # follow actionId to the impact for the victim count.
    var ledger: array[64, seq[bool]]
    for rel in ndReleases:
      if rel.slot in 0 ..< ledger.len: ledger[rel.slot].add rel.stale
    var used: array[64, int]
    for r in recs:
      if r.kind != 0: continue
      if r.slot < 0 or r.slot >= ledger.len: continue
      if used[r.slot] >= ledger[r.slot].len:
        inc ndUnjoined
        continue
      let stale = ledger[r.slot][used[r.slot]]
      inc used[r.slot]
      var v = 0
      for q in recs:
        if q.kind == 1 and q.actionId == r.actionId:
          for t in 0 .. 3:
            if t != r.team: v += q.victims[t]
          break
      if stale:
        inc ndStaleThrows
        ndStaleVictims += v
        if v > 0: inc ndStaleHit
      else:
        inc ndFreshThrows
        ndFreshVictims += v
        if v > 0: inc ndFreshHit
  when defined(wkprobe):
    let wk = engine.weaponKillCounts()
    wkRedGun += wk.redGun; wkBlueGun += wk.blueGun
    wkRedSpray += wk.redSpray; wkBlueSpray += wk.blueSpray
    wkRedNade += wk.redNade; wkBlueNade += wk.blueNade
  when defined(rangehitprobe):
    let rh = engine.rangeHitCounts()
    let redPct = (if rh.redShotsNear > 0: 100.0 * rh.redHitsNear.float / rh.redShotsNear.float else: 0.0)
    let bluePct = (if rh.blueShotsNear > 0: 100.0 * rh.blueHitsNear.float / rh.blueShotsNear.float else: 0.0)
    rhGameNearPct.add((seed: seed, redPct: redPct, bluePct: bluePct,
      redShots: rh.redShotsNear, redHits: rh.redHitsNear,
      blueShots: rh.blueShotsNear, blueHits: rh.blueHitsNear))
    # PER-GAME line (not just the end-of-run aggregate below) so a sharded
    # multi-process A/B (workers > 1, each running a SUBSET of games) can be
    # aggregated correctly afterward by parsing every worker's log, rather
    # than averaging each worker's own partial mean/sd (which would weight
    # workers unequally and lose the true per-game distribution).
    echo &"RHGAME seed={seed} redShotsNear={rh.redShotsNear} redHitsNear={rh.redHitsNear} " &
      &"redPct={redPct:.2f} blueShotsNear={rh.blueShotsNear} blueHitsNear={rh.blueHitsNear} " &
      &"bluePct={bluePct:.2f}"
  when defined(maskfp):
    echo &"FPGAME seed={seed} mask=0x{maskFp:016x} traj=0x{trajFp:016x}"
    gMaskFp.fpMix(maskFp)
    gTrajFp.fpMix(trajFp)
  when defined(v59ab):
    let v59sp = engine.v59Split()
    v59EpDeathEnemy = v59sp.deathsByEnemy
    v59EpDeathOwn = v59sp.deathsByOwn
    v59EpDeathSelf = v59sp.deathsBySelf
    v59EpMed = v59sp.medKits
    v59EpShield = v59sp.shields
    v59EpCan = v59sp.sprayCans
    v59EpKills = v59sp.kills
    v59EpCaps = v59sp.captures
    v59EpLives = v59sp.livesEnd
    v59EpWinner = v59sp.winner
  result = engine.result()

proc main() =
  var
    games = 10
    baseSeed = 7
    maxTicks = 10000
    numPlayers = 16
  let hunterSlots = parseSlotSet(getEnv("HUNTER_SLOTS"))

  var i = 1
  let params = commandLineParams()
  while i <= params.len:
    let a = params[i - 1]
    case a
    of "--games": inc i; games = parseInt(params[i - 1])
    of "--seed": inc i; baseSeed = parseInt(params[i - 1])
    of "--ticks": inc i; maxTicks = parseInt(params[i - 1])
    of "--players": inc i; numPlayers = parseInt(params[i - 1])
    else: discard
    inc i

  echo &"CTF eval harness: games={games} baseSeed={baseSeed} " &
    &"maxTicks={maxTicks} players={numPlayers} " &
    &"hunterSlots={(if hunterSlots.len == 0: \"none (control)\" else: $hunterSlots)}"
  # STATE THE BASE TUNE, every run. "hunterSlots=none (control)" is not enough:
  # it says the two SIDES match, not WHICH policy they are. Without
  # CONTROL_SHIPPED=1 the base tune is defaultCombatTune, where most champion
  # levers are OFF — so a plain `--games N` run measures a policy nobody ships,
  # and any lever-targeted probe reads a clean zero that looks like a null
  # result rather than a lever that never ran. That has burned a measurement
  # before; the funnel counters are what caught it. Cheap to print, so print it.
  let baseIsShipped = envInt("CONTROL_SHIPPED", 0) != 0
  echo &"  base tune: " &
    (if baseIsShipped: "shippedCombatTune (CONTROL_SHIPPED=1) — the CHAMPION"
     else: "defaultCombatTune — most champion levers OFF. " &
           "Set CONTROL_SHIPPED=1 to measure the shipped policy.")
  if hunterSlots.len > 0:
    # ⚠️ STATE THE HUNTER TUNE HONESTLY. This block used to print `hunterTune()`
    # unconditionally, which is a LIE on any run whose candidate comes from a
    # different branch — it prints a tune the run is not using, and the run then
    # looks configured when it is not. That is exactly how a v59 A/B batch was
    # thrown away: `env $E ...` in ZSH does not word-split, so CONTROL_SHIPPED
    # never reached the process, the header said "defaultCombatTune" as designed
    # — and the hunter line said "hunter tune: fresh=24 ..." as if the candidate
    # were configured. One honest line, one dishonest line. Both are printed
    # from resolved state now.
    if envInt("V59BUNDLE", 0) != 0:
      echo "  hunter tune: shippedCombatTune + THE v59 BUNDLE (V59BUNDLE=1) — " &
        "tradeGate/sprayConeFire/sprayFireFirst/raidFrame/windupLead+SelfLead " &
        "forced ON for the hunter seats only. lockOne is NOT in this bundle " &
        "by choice (a separate lever, a separate merge) — it IS a CombatTune " &
        "field now (migrated 2026-08-20) and can be isolated separately via " &
        "HUNTER_LOCKONE=1 or grabprobe's LOCKONETEAM."
      if envInt("CONTROL_SHIPPED", 0) == 0:
        echo "  ⛔ V59BUNDLE WITHOUT CONTROL_SHIPPED=1: the CONTROL side is " &
          "defaultCombatTune, not v58. This run is NOT the bundle A/B."
    elif envInt("HUNTER_MATEPOS", 0) != 0:
      echo "  hunter tune: shippedCombatTune (CONTROL_SHIPPED=1) + mateAimPos=true " &
        "— the MATEPOS proxy A/B, every other field identical to the control side"
    elif envInt("HUNTER_LOCKONE", 0) != 0:
      echo "  hunter tune: shippedCombatTune (CONTROL_SHIPPED=1) + lockOne=true " &
        "— the lockOne HUNTER_SLOTS isolation A/B, every other field identical " &
        "to the control side. Pair with NOLOCKONE=1 so the control side's " &
        "lockOne reads false (shippedCombatTune() ships it default ON)."
    else:
      let h = hunterTune()
      echo &"  hunter tune: fresh={h.freshShotTicks} slack={h.fireSlackPx} " &
        &"lead={h.leadTicks} dead={h.combatDeadband} range={h.fireRange} " &
        &"commit={h.commit} commitBonus={h.commitBonus} " &
        &"forceBalance={h.forceBalance} margin={h.outnumberMargin}"
  echo "seed  ticks  over  winner  redK blueK  redC blueC  redS blueS  " &
    "redHit% blueHit%"

  var
    redWins = 0
    blueWins = 0
    draws = 0
    unfinished = 0
    totRedK, totBlueK, totRedC, totBlueC, totRedS, totBlueS: int
    totRedD, totBlueD, totRedL, totBlueL: int
    totRedG, totBlueG: int
    totRedDropProg, totBlueDropProg: float
    totRedDropN, totBlueDropN: int
    totRedSurv, totBlueSurv: int
    totRedSurvN, totBlueSurvN: int
  when defined(v59ab):
    # ⭐⭐⭐ -d:v59ab accumulators. Per RED/BLUE, so the seat-rotated pair of runs
    # reads as candidate-vs-control on each seating. Deaths are split BY WHO
    # FIRED because friendly fire fakes a survival win (the woundedBank lesson);
    # `byEnemy` is the primary row and the other two are printed beside it so a
    # fake is visible instead of pooled away.
    var
      v59DeathEnemy, v59DeathOwn, v59DeathSelf: array[4, int]
      v59Med, v59Shield, v59Can: array[4, int]
      v59Kills, v59Caps, v59Lives, v59Wins: array[4, int]
      v59GameTicks = 0
  when defined(phprobe):
    var gameTickSum = 0
    var gameTickMin = high(int)
    var gameTickMax = 0
    var gamesPastForce = 0
  for g in 0 ..< games:
    let seed = baseSeed + g
    let r = runEpisode(seed, maxTicks, numPlayers, hunterSlots)
    let
      redHit = (if r.redShots > 0: 100.0 * r.redKills.float / r.redShots.float else: 0.0)
      blueHit = (if r.blueShots > 0: 100.0 * r.blueKills.float / r.blueShots.float else: 0.0)
      winner =
        if not r.phaseOver: "unfin"
        elif r.isDraw: "draw"
        elif r.winnerTeam == 0: "RED"
        else: "BLUE"
    echo &"{seed:>4}  {r.ticks:>5}  {r.phaseOver:>4}  {winner:>6}  " &
      &"{r.redKills:>4} {r.blueKills:>5}  {r.redCaptures:>4} {r.blueCaptures:>5}  " &
      &"{r.redShots:>4} {r.blueShots:>5}  {redHit:>6.1f} {blueHit:>7.1f}"
    if not r.phaseOver: inc unfinished
    elif r.isDraw: inc draws
    elif r.winnerTeam == 0: inc redWins
    else: inc blueWins
    totRedK += r.redKills; totBlueK += r.blueKills
    totRedD += r.redDeaths; totBlueD += r.blueDeaths
    totRedL += r.redLives; totBlueL += r.blueLives
    totRedC += r.redCaptures; totBlueC += r.blueCaptures
    totRedS += r.redShots; totBlueS += r.blueShots
    totRedG += r.redGrabs; totBlueG += r.blueGrabs
    totRedDropProg += r.redDropProgSum; totBlueDropProg += r.blueDropProgSum
    totRedDropN += r.redDropCount; totBlueDropN += r.blueDropCount
    totRedSurv += r.redSurvivalSum; totBlueSurv += r.blueSurvivalSum
    totRedSurvN += r.redSurvivalCount; totBlueSurvN += r.blueSurvivalCount
    when defined(v59ab):
      for t in 0 .. 3:
        v59DeathEnemy[t] += v59EpDeathEnemy[t]
        v59DeathOwn[t] += v59EpDeathOwn[t]
        v59DeathSelf[t] += v59EpDeathSelf[t]
        v59Med[t] += v59EpMed[t]
        v59Shield[t] += v59EpShield[t]
        v59Can[t] += v59EpCan[t]
        v59Kills[t] += v59EpKills[t]
        v59Caps[t] += v59EpCaps[t]
        v59Lives[t] += v59EpLives[t]
      if v59EpWinner in 0 .. 3: inc v59Wins[v59EpWinner]
      v59GameTicks += r.ticks
    when defined(phprobe):
      gameTickSum += r.ticks
      gameTickMin = min(gameTickMin, r.ticks)
      gameTickMax = max(gameTickMax, r.ticks)
      if r.ticks >= ForceClockTick: inc gamesPastForce

  let
    tRedHit = (if totRedS > 0: 100.0 * totRedK.float / totRedS.float else: 0.0)
    tBlueHit = (if totBlueS > 0: 100.0 * totBlueK.float / totBlueS.float else: 0.0)
    decisive = redWins + blueWins
    # GameVersion 2 scoring: +1 to every winner, -1 to every loser, 0 on a
    # draw. Per team the LEAGUE score is simply (wins - losses); K-D and lives
    # award NOTHING now (the timeout tiebreak was removed), so they are printed
    # only as diagnostics below the score.
    redScore = redWins - blueWins
    blueScore = blueWins - redWins
  echo ""
  echo &"TOTals over {games} games:"
  echo &"  SCORE:    RED {redScore:+d}  BLUE {blueScore:+d}  " &
    &"(win-only: +1 win / -1 loss / 0 draw — THE leaderboard metric)"
  echo &"  results:  RED wins {redWins}  BLUE wins {blueWins}  " &
    &"draw {draws}  unfinished {unfinished}  ({decisive}/{games} decisive)"
  echo &"  wins by:  capture RED {totRedC} BLUE {totBlueC}  " &
    &"(rest of the {decisive} decisive games were WIPES)"
  let
    redConv = (if totRedG > 0: 100.0 * totRedC.float / totRedG.float else: 0.0)
    blueConv = (if totBlueG > 0: 100.0 * totBlueC.float / totBlueG.float else: 0.0)
  echo &"  grabs:    RED {totRedG}  BLUE {totBlueG}  " &
    &"(heart pickups — the capture funnel's mouth)"
  echo &"  grab->cap:RED {redConv:.1f}%  BLUE {blueConv:.1f}%  " &
    &"(pickups that became a winning capture — daveey's edge is HERE)"
  let
    redDropAt = (if totRedDropN > 0: totRedDropProg / totRedDropN.float else: 0.0)
    blueDropAt = (if totBlueDropN > 0: totBlueDropProg / totBlueDropN.float else: 0.0)
  echo &"  drop@home:RED {redDropAt * 100:.0f}%  BLUE {blueDropAt * 100:.0f}%  " &
    &"(mean run-home % where a carrier was killed; 0=at robbed pedestal, 100=own edge; " &
    &"n RED {totRedDropN} BLUE {totBlueDropN})"
  let
    redSurv = (if totRedSurvN > 0: totRedSurv.float / totRedSurvN.float else: 0.0)
    blueSurv = (if totBlueSurvN > 0: totBlueSurv.float / totBlueSurvN.float else: 0.0)
  echo &"  survive:  RED {redSurv:.0f}t  BLUE {blueSurv:.0f}t  " &
    &"(mean ticks a carrier LIVED after grabbing before a non-scoring death; " &
    &"few ticks = dies IN the nest, not en route; n RED {totRedSurvN} BLUE {totBlueSurvN})"
  echo "  --- diagnostics (award NO points under v2, for analysis only) ---"
  echo &"  kills:    RED {totRedK}  BLUE {totBlueK}"
  echo &"  deaths:   RED {totRedD}  BLUE {totBlueD}"
  echo &"  K-D diff: RED {totRedK - totRedD:+d}  BLUE {totBlueK - totBlueD:+d}"
  echo &"  lives end:RED {totRedL}  BLUE {totBlueL}"
  echo &"  shots:    RED {totRedS}  BLUE {totBlueS}"
  echo &"  hit rate: RED {tRedHit:.2f}%  BLUE {tBlueHit:.2f}%"
  echo &"  camp-ticks (frozen w/ live target): RED {campTicksRed}  BLUE {campTicksBlue}"
  when defined(v59ab):
    # ⚠️ FOUR TEAMS, per RAW ENGINE TEAM INDEX. The red/blue rows above fold
    # teams 1..3 into BLUE, so on a 4-team board they compare a 4-seat arm
    # against a 12-seat one. These rows do not.
    echo "  --- V59AB per RAW ENGINE TEAM (engine truth: sim.events + sim.players) ---"
    echo "  V59 metric                  T0      T1      T2      T3"
    for (nm, a) in [("wins", v59Wins), ("deathsByENEMY*", v59DeathEnemy),
                    ("deathsByOWN(FF)", v59DeathOwn), ("deathsSelf/Env", v59DeathSelf),
                    ("kills", v59Kills), ("captures", v59Caps), ("livesEnd", v59Lives),
                    ("medkits", v59Med), ("shields", v59Shield), ("sprayCans", v59Can)]:
      echo &"  V59 {nm:<20}{a[0]:>8}{a[1]:>8}{a[2]:>8}{a[3]:>8}"
    echo &"  V59 total game ticks: {v59GameTicks}" &
      "  (* deathsByENEMY is THE primary survival row — pooled deaths let" &
      " friendly fire fake a survival win. Game LENGTH moves with several of" &
      " these levers, so only the NULL arm makes a per-game rate comparable.)"
  when defined(ohshitprobe):
    let mis = (if ohshitTotal > 0: 100.0 * ohshitMateCloser.float / ohshitTotal.float else: 0.0)
    let good = (if ohshitTotal > 0: 100.0 * ohshitEnemyClose.float / ohshitTotal.float else: 0.0)
    echo &"  OHSHIT-PROBE: {ohshitTotal} 'oh shit!'  enemy<=95px {ohshitEnemyClose} ({good:.0f}%)  " &
      &"mate-closer {ohshitMateCloser} ({mis:.0f}% = MISFIRES)"
  when defined(hsprobe):
    echo &"  HS-PROBE: carrierHomeStretch fired {hsFireCount}  moved-target {hsMovedCount}  " &
      &"(fire=0 => field-only trigger; fire>0 moved=0 => no-op vs lane path)"
  when defined(rgprobe):
    echo &"  RG-PROBE guard: mid {rgMid} -> noCarry {rgNoCarry} -> noStolen {rgNoStolen} -> reach {rgReach}"
    echo &"  RG-PROBE funnel: reach {rgReach} -> deep {rgDeep} -> vacuum {rgVac} -> " &
      &"lone {rgLone} -> support {rgJoin} -> FIRED {rgFireCount}"
    echo &"    (a stage that zeroes the count names the gating condition; FIRED>0 => gate live)"
  when defined(gtprobe):
    echo &"  GT-PROBE funnel: want {gtWant} -> eligible {gtEligible} -> stacked {gtStacked} -> " &
      &"noCover {gtNoCover} -> FIRED {gtFireCount}"
    echo &"    (want>0 eligible=0 => grabTiming off/pushOut; stacked=0 => mirror pocket never stacks (field-only); FIRED>0 => gate live)"
  when defined(hscensus):
    echo "  HS-CENSUS: per-call-site reach of homeSign() on the boards played"
    echo &"    frames(ffa4)={hcFrames} corners={hcCorners} plus={hcPlus} " &
      &"byColour r/b/g/y={hcByColor[0]}/{hcByColor[1]}/{hcByColor[2]}/{hcByColor[3]}"
    if hcFrames > 0:
      let den = float(max(hcCorners + hcPlus, 1))
      echo &"    HOMEWARD-AXIS: mean cos(axis,true home)={hcCosSum / den:.3f} " &
        &"pointing-AWAY={hcHomeFlipped} ({100.0*float(hcHomeFlipped)/den:.1f}%) " &
        &"[corners {hcHomeFlippedC} plus {hcHomeFlippedP}] >45deg-off={hcHomeOff45} " &
        &"({100.0*float(hcHomeOff45)/den:.1f}%)"
      echo &"    flippedByColour r/b/g/y={hcHomeFlippedByColor[0]}/" &
        &"{hcHomeFlippedByColor[1]}/{hcHomeFlippedByColor[2]}/{hcHomeFlippedByColor[3]}"
      let tot = float(max(hcTP + hcFP + hcFN + hcTN, 1))
      echo &"    OVER-EXTEND verdict (axis >= HoldLineTrigDepth) vs TRUTH (nearest zone is a rival's):"
      echo &"      TP={hcTP} FP={hcFP} FN={hcFN} TN={hcTN} -> WRONG={hcFP + hcFN} " &
        &"({100.0*float(hcFP + hcFN)/tot:.1f}% of frames) [corners {hcDepthWrongC} plus {hcDepthWrongP}]"
    if h2Frames > 0:
      let d2 = float(h2Frames)
      echo &"    2-TEAM CONTROL frames={h2Frames} mean cos={h2CosSum / d2:.3f} " &
        &"pointing-AWAY={h2HomeFlipped} ({100.0*float(h2HomeFlipped)/d2:.1f}%) " &
        &">45deg-off={h2HomeOff45} ({100.0*float(h2HomeOff45)/d2:.1f}%) " &
        &"depth-WRONG={h2Wrong} ({100.0*float(h2Wrong)/d2:.1f}%)"
    echo &"    ffa4 ROLE histogram (MidTop/MidBottom/MidGuard/FlankTop/FlankBottom/Overwatch/HomeDefender): " &
      &"{hgRole[0]}/{hgRole[1]}/{hgRole[2]}/{hgRole[3]}/{hgRole[4]}/{hgRole[5]}/{hgRole[6]}"
    echo &"    holdLine GATE (first failing conjunct): tune={hgTune} iCarry={hgICarry} " &
      &"mateCarry={hgMateCarry} ownStolen={hgOwnStolen} retreat={hgRetreat} " &
      &"decline={hgDecline} pushOut={hgPushOut} notMid={hgNotMid} pocket={hgPocket} " &
      &"-> OPEN={hgOpen}"
    proc cellPct(a: array[3, int]): string =
      let t = max(a[0] + a[1] + a[2], 1)
      &"own {100.0*float(a[0])/float(t):.1f}% raid {100.0*float(a[1])/float(t):.1f}% " &
        &"THIRD-PARTY {100.0*float(a[2])/float(t):.1f}% (n={a[0]+a[1]+a[2]})"
    echo &"    CONSEQUENCE - Voronoi cell of the emitted opening-nav target:"
    echo &"      flank staging point : {cellPct(hsFlankCell)}"
    echo &"      mid trail anchor    : {cellPct(hsMidCell)}"
    echo &"      (control) BODY pos  : {cellPct(hsBodyCell)}"
    const TeamColorNamesRep = ["red", "blue", "green", "yellow"]
    echo "    SIGN CLAIM per colour (does homeSign match the side our OWN stated zone is on?)"
    for ci in 0 .. 3:
      let t = hsSign[ci][0] + hsSign[ci][1] + hsSign[ci][2]
      if t > 0:
        echo &"      {TeamColorNamesRep[ci]}: agree={hsSign[ci][0]} INVERTED={hsSign[ci][1]} " &
          &"midline={hsSign[ci][2]}  (bot.team==Red on {hsTeamRed[ci]} of {t})"
    let dtot = max(hsDeaths, 1)
    echo &"    DEATH LEDGER (engine truth, t<1200): deaths={hsDeaths} " &
      &"(t in 200..400: {hsDeaths24})  outside-own-territory={hsDeathsAway} " &
      &"({100.0*float(hsDeathsAway)/float(dtot):.1f}%)"
    echo &"      at the flank staging point (<=200px): {hsDeathsAtStg} " &
      &"({100.0*float(hsDeathsAtStg)/float(dtot):.1f}%)  en route to it: {hsDeathsEnRoute} " &
      &"({100.0*float(hsDeathsEnRoute)/float(dtot):.1f}%)"
    # ⭐ MEASURED 2026-08-20, six distinct hosted mapSpecs, 4 episodes each,
    # shipped tune, 849 deaths total. Realized coverage 15.6 / 16.5 / 17.5 /
    # 19.3 / 20.3 / 21.2% -- mean 18.4%, a tight replicate across six boards.
    # ⛔ READ IT ADVERSARIALLY. The flanker is 1 of the 4 seats in our ffa4 deal
    # = 25% of our bodies, so 18.4% is BELOW its per-capita share: the seat
    # under the mis-placed target is NOT dying at an elevated rate, which is the
    # strongest single argument against a large payoff. Only ~33% of those
    # deaths are even in foreign territory, and a correctly-keyed staging point
    # still puts a flanker in contested ground. Ceiling if a re-key avoided
    # EVERY death under the current target (impossible): 0.184 * 5.06 = 0.93
    # lives/team-Ep. Best estimate 0.1-0.3, against a 2.33 gap to relh.
    # ⚠️ Only the SHARE travels. This rig spends ~10.4 of 12 lives per team by
    # t=1200 against the field's 5.06 -- the levels are not field-comparable.
    echo &"      REALIZED COVERAGE - died while UNDER the staging target (<=30t): " &
      &"{hsDeathsUnderStg} ({100.0*float(hsDeathsUnderStg)/float(dtot):.1f}% of deaths); " &
      &"of those, outside own territory: {hsDeathsUnderStgAway}; in t 200..400: " &
      &"{hsDeathsUnderStg24} of {hsDeaths24}"
    echo &"      staging-target frames by window: t<200={hsStgFrames[0]} " &
      &"200..400={hsStgFrames[1]} 400..1200={hsStgFrames[2]}"
    block:
      let stgN = hsStgClose + hsStgFar + hsStgFlat
      if stgN > 0:
        echo &"      FEET CHECK - of {stgN} frames the staging target was written, the body moved " &
          &"CLOSER {hsStgClose} ({100.0*float(hsStgClose)/float(stgN):.1f}%) / " &
          &"FARTHER {hsStgFar} ({100.0*float(hsStgFar)/float(stgN):.1f}%) / " &
          &"flat {hsStgFlat} ({100.0*float(hsStgFlat)/float(stgN):.1f}%); " &
          &"mean signed closure {hsStgClosePx/float(stgN):.3f}px/frame against " &
          &"{hsStgSpeedPx/float(stgN):.3f}px/frame actually travelled " &
          &"(ratio {(if hsStgSpeedPx > 0.0: hsStgClosePx/hsStgSpeedPx else: 0.0):.3f}; " &
          "1.0 = every step went straight at it, 0.0 = the target does not own the feet)"
    echo "    --- reach by source line (baseline.nim, hscensus build) ---"
    for l in 0 ..< 13000:
      if hsHit[l] > 0:
        echo &"      L{l}  n={hsHit[l]}  r/b/g/y=" &
          &"{hsHitC[l][0]}/{hsHitC[l][1]}/{hsHitC[l][2]}/{hsHitC[l][3]}"
  when defined(maskfp):
    # The two arms are compared by these two lines and nothing else. Identical =>
    # the change is a no-op on this corpus; different => report the divergence
    # HONESTLY rather than hunting for a construction that hides it.
    echo &"  MASK-FP  0x{gMaskFp:016x}"
    echo &"  TRAJ-FP  0x{gTrajFp:016x}"
  when defined(lkprobe):
    let
      lkPSwitch = (if lkOpp > 0: lkSwitch.float / lkOpp.float else: 0.0)
      lkInsidePct = (if lkSwitch > 0: 100.0 * lkSwitchInside.float / lkSwitch.float else: 0.0)
      lkMeanSep = (if lkSwitch > 0: lkSepSum / lkSwitch.float else: 0.0)
    var lkMedSep = 0.0
    if lkSeps.len > 0:
      var xs = lkSeps
      xs.sort(system.cmp[float])
      lkMedSep = xs[xs.len div 2]
    let discTot = max(lkLockFrames, 1)
    echo "  LK-PROBE — the lockPos-is-a-PLACE instrument (NEVER gate this on attrition)"
    echo &"    STIMULUS: lock-live frames {lkLockFrames}  in-disc hist[0|1|2|3|4+] " &
      &"{lkDiscHist[0]} {lkDiscHist[1]} {lkDiscHist[2]} {lkDiscHist[3]} {lkDiscHist[4]}  " &
      &"CONTESTED (>=2) {lkContested} ({100.0 * lkContested.float / discTot.float:.2f}%)"
    echo &"    NO-OP PROOF: evals with disc<=1 {lkNoopEvals}, of which old!=new " &
      &"{lkNoopBreak} (MUST BE 0)   |   contested evals {lkContestedEvals}, of which " &
      &"old!=new {lkDivergeEvals} (the BITE)"
    echo &"    SWITCH LEDGER (engine-truth identity): opportunities {lkOpp}  " &
      &"switches {lkSwitch}  P(switch|live) {lkPSwitch:.4f}"
    echo &"    of those switches: INSIDE the 60px lock disc {lkSwitchInside} " &
      &"({lkInsidePct:.1f}%)  mean sep {lkMeanSep:.1f}px  median sep {lkMedSep:.1f}px"
    echo "    (contested=0 => this rig has NO STIMULUS and any null here means nothing " &
      "— compare the rig's BEFORE to the FIELD's BEFORE, 0.188 ffa4 / +0.025 vs field 2-team)"
  when defined(hlprobe):
    echo &"  HL-PROBE funnel: mid {hlMid} -> reach {hlReach} -> deep {hlDeep} -> " &
      &"line {hlLine} -> outgun {hlOutgun} -> support {hlLone} -> FIRED {hlFireCount}"
    echo &"    (deep=0 => never over-extends in mirror; line=0 => no fresh enemy front (vacuum=regroupPush's job); " &
      &"outgun=0 => never locally outgunned (field-only vs a real line); FIRED>0 => gate live)"
  when defined(ggprobe):
    echo &"  GG-PROBE funnel: want {ggWant} -> eligible {ggEligible} -> outgun {ggOutgun} -> FIRED {ggFireCount}"
    echo &"    (want>0 eligible=0 => grabGate off/pushOut/commit-ring; outgun=0 => pocket numbers even in mirror (field-only); FIRED>0 => gate live)"
  when defined(commsprobe):
    echo &"  COMMS-PROBE: classify stack {csStack} wipe {csWipe} peel {csPeel} line {csLine} -> " &
      &"EMIT {csEmit} -> HEARD {csHeard} -> ADOPT {csAdopt} -> WIPE-ARM {csWipeArm} " &
      &"LINE-ARM {csLineArm} NADE-CLUSTER {csNadeLine} ARC-SEEK {csArcSeek} ARC-FIRE {csArcFire}"
    echo &"    (classify>0 => the scenario read fires (incl. LINE = standing enemy line); EMIT>0 => " &
      &"codewords broadcast; HEARD>0 => mates decode them; ADOPT>0 => a heard play drove a mate's flank; " &
      &"WIPE-ARM/LINE-ARM>0 => a HEARD wipe/line armed a mate's rally it never saw itself; " &
      &"NADE-CLUSTER>0 => a grenade carrier lobbed at a multikill cluster — the full bus is LIVE + " &
      &"COORDINATING combined-arms. Mirror = liveness+no-regression only; win-credit is a hosted xreq.)"
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
      &"the v56 answer to 'nobody reacts to our shouts'. A frame count >0 with a ~0px mean is still " &
      &"a no-op, so read the px. STACK-GATE counts ONLY frames where the wire held a dive our own " &
      &"eyes would have walked into. LATCH-DROP>0 => the measured 41% mid-TTL token thrash is being " &
      &"refused; ECHO-SKIP>0 => the 58% echo redundancy is what pays for E-CALLOUT.)"
  when defined(arcprobe):
    let meanCl = (if apFire > 0: apClusterSum.float / apFire.float else: 0.0)
    echo &"  ARC-PROBE funnel: breacher {apBreacher} -> lineLive {apLineLive} -> " &
      &"eligible {apEligible} -> SEEK {apSeek} -> ARMED {apArmed} -> " &
      &"(charge {apCharge} | inReach {apInReach}) -> FIRE {apFire}"
    echo &"    multikill: mean cluster/fire {meanCl:.2f}  fattest {apMaxCluster}  (>=2 => a real cone multikill)"
    echo &"    (SEEK>0 => the breacher navigates to the STATIC arcSpawn (LOS-free, the fires-0 fix); " &
      &"ARMED>0 => the pickup landed (arc held); charge>0 => armed & driving the seam for a cluster; " &
      &"inReach>0 => a cluster sat in cone reach; FIRE>0 => it pressed the multikill cone. " &
      &"A stage that zeroes names the gate. TURTLE=1 makes the control team stand a line to breach.)"
    echo &"  SPRAY-SINGLE (fix C): single-FIRE {apSingleFire}  single-CHARGE {apSingleCharge}  " &
      &"(spraySingle: cluster gate found NOTHING >= ArcConeMinCluster, so the lone-target fallback " &
      &"fired/closed instead of falling to the mute DRY branch — the 87%-unfired-can fix.)"
  when defined(sgprobe):
    let held = (if sgDefended > 0: 100.0 * sgHold.float / sgDefended.float else: 0.0)
    echo &"  SG-PROBE (dive-death fix): want {sgWant} -> defended {sgDefended} -> " &
      &"HOLD-at-standoff {sgHold} | COMMIT-with-advantage {sgCommit}  ({held:.0f}% of defended pockets HELD)"
    echo &"    (defended = a stacked pocket; HOLD = the suicide dive PREVENTED (suppress from range); " &
      &"COMMIT = a real Captain advantage (pickEdge/PhForce/cover) opened the touch. HOLD+COMMIT should " &
      &"cover ~all defended-pocket frames; a defended pocket that neither holds nor commits = a leak.)"
  when defined(fsprobe):
    echo &"  FS-PROBE (focus-fire audit): holdVsGun-catches {fsHold}"
    echo &"    (fsHold = frames a SOLO gun-down bot faced a fresh dead-on gun past DuckRange " &
      &"inside HoldVsGunRange and the guard held it instead of turning its back. >0 with HOLDVSGUN=1 " &
      &"=> the back-turn bug is REAL + frequent; run with HOLDVSGUN=1 -d:fsprobe on the hunter slots.)"
  when defined(mtprobe):
    echo &"  MT-PROBE funnel: on {mtOn} -> wounded {mtWounded} -> safe {mtSafe} -> " &
      &"free {mtFree} -> kitVisible {mtVisible} -> FIRED {mtFireCount}"
    echo &"    (wounded=0 => bots rarely survive hurt; safe=0 => always in contact when hurt; " &
      &"kitVisible=0 => fog hides the kit (field-only); FIRED>0 => detour live)"
  when defined(arprobe):
    echo &"  AR-PROBE: frames {arFrames}  selfRead {arSelfRead} (resync {arResync})  " &
      &"enemy {arEnemyRead}/{arEnemySeen}  mate {arMateRead}/{arMateSeen}"
    echo &"    (enemyRead=0 => the sprite-id pool moved (re-verify RotPlayerSpriteBase); " &
      &"read>0 => aim intel is BACK on the dot-less engine)"
  when defined(caprobe):
    echo &"  CA-PROBE: arcAttrib {caArcAttrib}  seen {caSeen}  bump {caBump}"
    echo &"    (arcAttrib=0 => no plasma-arc carrier ever occurs in self-play (lever " &
      &"field-only, expected in mirror); bump>0 => a disarmed carrier got the credit)"
  when defined(asoprobe):
    echo &"  ASO-PROBE: near {asoNear}  backOff {asoBack}  deadBandHold {asoHold}  " &
      &"caughtInCone {asoInCone}"
    echo &"    (near/caughtInCone are counted whenever COUNTERARC=1, NOT gated on ARCSTANDOFF, so " &
      &"both A/B arms measure the same world. near=0 => no arc-carrier ever came within the 236px " &
      &"band, so there was no stimulus (expected in a plain mirror — run ARCFOE=1 to field one); " &
      &"backOff>0 => the feet actually broke contact; caughtInCone should FALL with ARCSTANDOFF=1 " &
      &"vs 0 — inside 136px one cone touch == MaxHp == instant death)"
  when defined(nmprobe):
    echo &"  NM-PROBE: navFrames {nmNavFrames}  supportRays {nmRays}  repel {nmRepel}"
    echo &"    (rays=0 => no live mate gun-line ever forms (mateGunDown/aim-read dead); " &
      &"repel>0 => movers actually bend off the corridor — lever live)"
  when defined(ocprobe):
    echo &"  OC-PROBE funnel: advance {ocAdvance} -> coneRead {ocConeRead} -> " &
      &"onUs {ocOnUs} -> BEND {ocBend}"
    echo &"    (coneRead=0 => enemy bearing channel dead (needs AIMROT); onUs=0 => cone " &
      &"never on the closer; BEND>0 => the approach actually bends — lever live)"
  when defined(asprobe):
    echo &"  AS-PROBE funnel: surprise {asSurprise} -> gunOnMe {asGunOnMe} -> " &
      &"committed {asNoCover} -> chargeFrames {asCharge}"
    echo &"    (surprise=0 => near-ambushes never happen in the mirror; committed=0 => " &
      &"cover was always nearer (duck stays right); chargeFrames>0 => lever live)"
  when defined(ndprobe):
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
    echo &"  ND-PROBE 1/stale funnel: carryFrames {ndCarryFrames} -> " &
      &"staleWallCamper-tracks {ndStaleSeen} -> withCluster>=2 {ndStaleCluster} -> " &
      &"STALE-AIM {ndStaleAim} (fresh-aim {ndFreshAim}) -> " &
      &"RELEASED stale {ndStaleRelease} / fresh {ndFreshRelease}"
    echo &"    DISCRIMINATION (engine truth, joined by actionId): " &
      &"stale throws {ndStaleThrows} conv {staleConv:.1f}% victims/throw {staleVpt:.2f}  |  " &
      &"fresh throws {ndFreshThrows} conv {freshConv:.1f}% victims/throw {freshVpt:.2f}  " &
      &"(unjoined {ndUnjoined})"
    echo &"    (staleWallCamper-tracks is counted with NOSTALENADE=1 too, so both A/B arms " &
      &"measure the same world. =0 => the wall-camper case never occurs here (no stimulus). " &
      &">0 with STALE-AIM=0 => the cluster/range gate declines it. The gate EARNS its place " &
      &"only if stale conv/victims-per-throw is comparable to fresh — a stale class that " &
      &"whiffs is spent supply, not a lever.)"
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
      &"of which caught 2+ of one team {ndImpactBunch} ({bunchPct:.1f}%), victims {ndVictims}  " &
      &"(the field number this lever targets is 56%)"
  when defined(ffprobe):
    echo &"  FF-PROBE funnel: hold {ffHold} -> idle {ffIdle} -> preLay {ffPreLay}"
    echo &"    (idle=0 => a sentry always has a fresh track (sweep keeps the job); " &
      &"preLay>0 => the turret actually parks on the throat — lever live)"
  when defined(scprobe):
    echo &"  SC-PROBE funnel: engaged {scEngaged} -> satSeen {scSatSeen} -> " &
      &"redirect {scRedirect} / dogpile {scDogpile}"
    echo &"  SC-PROBE coverage (candidate evals): cov1 {scCov1}  cov2 {scCov2}  hp1 {scHp1}"
    echo &"  SC-PROBE dot-read: mateFresh {scMateFresh} -> read {scMateRead} -> rayHit {scRayHit}"
    echo &"    (satSeen=0 => pair-saturation never occurs in range (lever inert); " &
      &"redirect>0 => the cap actually spreads fire; dogpile = commit-held or lone target; " &
      &"cov1>0 cov2=0 => a PAIR of readable mate lines never forms — threshold unreachable)"
  when defined(canprobe):
    let
      canPerK = (if cpAliveTk > 0: 1000.0 * (cpRedHeldTk + cpBlueHeldTk).float / cpAliveTk.float else: 0.0)
      seenPct = (if cpGate > 0: 100.0 * cpSeen.float / cpGate.float else: 0.0)
      seekPct = (if cpSeen > 0: 100.0 * cpSeek.float / cpSeen.float else: 0.0)
    echo &"  CAN-PROBE perception: scan-frames {cpGate}  non-empty {cpSeen} ({seenPct:.1f}%)  " &
      &"objects {cpObjs}  -> sprayGrab seek {cpSeek} ({seekPct:.1f}% of non-empty)"
    echo &"  CAN-PROBE engine truth: alive-ticks {cpAliveTk}  can held-ticks RED {cpRedHeldTk} " &
      &"BLUE {cpBlueHeldTk}  pickups RED {cpRedPickEv} BLUE {cpBluePickEv}  " &
      &"({canPerK:.2f} can-ticks per 1k alive)"
    echo &"    (non-empty=0 with scan-frames>0 => the `spray can` label read is BLIND — the " &
      &"exact 0.7.x rename failure. non-empty>0 with seek=0 => perception fine, gate declines. " &
      &"pickups>0 with non-empty=0 => we only ever get cans by ACCIDENT.)"
  when defined(wkprobe):
    let
      wkRedTot = wkRedGun + wkRedSpray + wkRedNade
      wkBlueTot = wkBlueGun + wkBlueSpray + wkBlueNade
      wkRedSprayPct = (if wkRedTot > 0: 100.0 * wkRedSpray.float / wkRedTot.float else: 0.0)
      wkBlueSprayPct = (if wkBlueTot > 0: 100.0 * wkBlueSpray.float / wkBlueTot.float else: 0.0)
    echo &"  WK-PROBE kills by weapon: RED gun={wkRedGun} spray={wkRedSpray} " &
      &"grenade={wkRedNade} total={wkRedTot}  (spray share {wkRedSprayPct:.1f}%)"
    echo &"  WK-PROBE kills by weapon: BLUE gun={wkBlueGun} spray={wkBlueSpray} " &
      &"grenade={wkBlueNade} total={wkBlueTot}  (spray share {wkBlueSprayPct:.1f}%)"
    echo &"    (compare spray-share vs the daveey-game field number ~16.7%; MIRROR so both " &
      &"sides run the same policy — the question is whether the machinery fires at all.)"
  when defined(rangehitprobe):
    # Pooled 0-150px hit% (all shots, all games) AND the per-game spread
    # (mean/stdev of each game's own hit%) — the study's key metric was the
    # VARIANCE across games (24pp ours vs daveey's 3pp), not just a pooled mean.
    var
      totRedSN, totRedHN, totBlueSN, totBlueHN = 0
      redPcts, bluePcts: seq[float]
    for g in rhGameNearPct:
      totRedSN += g.redShots; totRedHN += g.redHits
      totBlueSN += g.blueShots; totBlueHN += g.blueHits
      redPcts.add(g.redPct)
      bluePcts.add(g.bluePct)
    proc meanOf(xs: seq[float]): float =
      if xs.len == 0: return 0.0
      var s = 0.0
      for x in xs: s += x
      s / xs.len.float
    proc stdevOf(xs: seq[float]): float =
      if xs.len < 2: return 0.0
      let m = meanOf(xs)
      var ss = 0.0
      for x in xs: ss += (x - m) * (x - m)
      sqrt(ss / (xs.len - 1).float)
    let
      pooledRedPct = (if totRedSN > 0: 100.0 * totRedHN.float / totRedSN.float else: 0.0)
      pooledBluePct = (if totBlueSN > 0: 100.0 * totBlueHN.float / totBlueSN.float else: 0.0)
      redMean = meanOf(redPcts)
      redSd = stdevOf(redPcts)
      blueMean = meanOf(bluePcts)
      blueSd = stdevOf(bluePcts)
    echo &"  RANGE-HIT-PROBE 0-150px hit%: RED shots={totRedSN} pooled={pooledRedPct:.1f}% " &
      &"per-game mean={redMean:.1f}% sd={redSd:.1f}pp  BLUE shots={totBlueSN} " &
      &"pooled={pooledBluePct:.1f}% per-game mean={blueMean:.1f}% sd={blueSd:.1f}pp"
    echo "    (per-game sd is the study's key metric: our spread was measured at 24pp vs " &
      "daveey's 3pp)"
  when defined(ssprobe):
    let
      swPerK = (if ssAliveTk > 0: 1000.0 * (ssRedSwordTk + ssBlueSwordTk).float / ssAliveTk.float else: 0.0)
      shPerK = (if ssAliveTk > 0: 1000.0 * (ssRedShieldTk + ssBlueShieldTk).float / ssAliveTk.float else: 0.0)
    echo &"  SS-PROBE alive-ticks {ssAliveTk}"
    echo &"  SS-PROBE sword  held-ticks RED {ssRedSwordTk} BLUE {ssBlueSwordTk}  " &
      &"pickups RED {ssRedSwordEv} BLUE {ssBlueSwordEv}  ({swPerK:.2f} disarmed-ticks per 1k alive)"
    echo &"  SS-PROBE shield held-ticks RED {ssRedShieldTk} BLUE {ssBlueShieldTk}  " &
      &"pickups RED {ssRedShieldEv} BLUE {ssBlueShieldEv}  ({shPerK:.2f} disarmed-ticks per 1k alive)"
    echo &"    (accidental pickups on the UNADAPTED bot => canFire=false. High => avoidance urgent.)"
    echo &"  SS-PROBE levers: avoid-repel-frames {ssAvoidActive}  tank-seek {ssTankSeek}  " &
      &"ambush-seek {ssAmbushSeek}  ambush-swing {ssAmbushSwing}"
    echo &"    (proves the gated v7 levers are LIVE code: >0 => firing even when grabs are ~0)"
  when defined(seatprobe):
    echo "  SEAT-PROBE pocketRush suppression by (team, teamSeat) — wantTrue / wantFalse / " &
      "suppressedByCombo (suppressedByCombo>0 should appear ONLY on ComboGrabSeat's own row):"
    for team in Team:
      for s in 0 .. 7:
        let tot = spWantTrue[team][s] + spWantFalse[team][s]
        if tot == 0: continue
        echo "    " & $team & " seat" & $s & ": true=" & $spWantTrue[team][s] &
          " false=" & $spWantFalse[team][s] & " suppressedByCombo=" & $spSuppressedByCombo[team][s]
  when defined(phprobe):
    # ⭐ v29 PHASE OCCUPANCY — the empirical premise for PhForce timing + PhDefend teeth.
    # Answers what the v21 design doc could only guess: which phases the team actually
    # OCCUPIES, and how late the GV23 clock (MaxTicks 5000 + banked overtimeTicks) runs.
    # Verify occupancy BEFORE tuning any phase constant: a phase at 0% frames is a spec,
    # not a behavior, and its constant is not the bug.
    var phTot = 0
    for p in TeamPhase: phTot += phFrames[p]
    echo ""
    echo &"  PHASE-PROBE: {phTot} plan-layer decide() frames; latest elapsed tick seen {phMaxElapsed}"
    for p in TeamPhase:
      let pct = (if phTot > 0: 100.0 * phFrames[p].float / phTot.float else: 0.0)
      echo &"    {($p)[2..^1]:<7} {phFrames[p]:>9} frames  {pct:>5.1f}%"
    echo &"  game ticks: mean {gameTickSum.float / max(1, games).float:.0f}  " &
      &"min {gameTickMin}  max {gameTickMax}  " &
      &"(>= ForceClockTick {ForceClockTick}: {gamesPastForce}/{games} games)"
    let dtTot = dtFresh + dtStale + dtBlind
    echo &"  DEFTEETH gate funnel: inDefend {dtPhase} -> notCarry {dtNotCarry} -> " &
      &"attacker {dtAttacker} -> teethOn {dtOn}  (the tier that zeroes NAMES the gate)"
    echo &"  DEFTEETH steer: {dtTot} frames  fresh-fix {dtFresh}  " &
      &"stale-crossing {dtStale}  blind-mid {dtBlind}"

proc mhDump() =
  when defined(maskhash):
    echo &"MASKHASH {mhHash:016x} masks={mhMasks}"
  when defined(barrprobe):
    echo &"BARRPROBE maxDepth={bpMaxDepth} depthFrames={bpDepthFrames} " &
      &"postVeto={bpPostVeto} evac={bpEvac}"

  when defined(leverprobe):
    echo "LVPROBE-BEGIN"
    for i in 0 ..< LvSites:
      echo &"LV {i} {lvEval[i]} {lvTrue[i]}"
    echo "LVPROBE-END"

when isMainModule and not defined(tuneCheck):
  main()
  mhDump()
  when defined(mkprobe):
    let den = float(max(mkAliveFrames, 1))
    echo "MKPROBE aliveFrames=" & $mkAliveFrames &
      " koLabels(ourColour)=" & $mkKoLabels &
      " rejRespawn=" & $mkRejRespawn & " rejDedupe=" & $mkRejDedupe &
      " rejNoMateTrack=" & $mkRejNoMate & " STAMPS=" & $mkStamps &
      " doorBandStamps=" & $mkDoorOpp &
      " idleTurretFrames=" & $mkIdleTurret &
      " aimRungOPP=" & $mkAimOpp & " lastManWatchOPP=" & $mkWatchOpp
    echo "MKPROBE rates: idleTurret=" & $(100.0 * float(mkIdleTurret) / den) &
      "% aimRungOPP=" & $(100.0 * float(mkAimOpp) / den) &
      "% watchOPP=" & $(100.0 * float(mkWatchOpp) / den) & "%"
  when defined(identprobe):
    # Printed LAST and unconditionally, so a run that is killed still leaves
    # everything it managed to fold.
    echo identProbeReport()
