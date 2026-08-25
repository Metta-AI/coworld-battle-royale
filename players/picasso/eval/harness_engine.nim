## Headless in-process CTF engine wrapper for the eval / A-B harness.
##
## This module OWNS the engine types (SimServer, InputState, PlayerViewerState)
## and exposes only a primitive-typed surface: `string` packet blobs out,
## `uint8` button masks in, plain ints out for the scoreboard. That keeps the
## engine's `Team`/`enemy`/`flagHome` symbols from ever colliding with the
## baseline bot module (which declares its own `Team`, `enemy`, `flagHome`),
## so the driver can `include` the baseline verbatim and drive its BYTE-
## IDENTICAL decision path with zero edits to the shipped player.
##
## Fidelity contract (matches src/ctf/server.nim's live loop exactly):
##   * one sprite packet built per player per tick via
##     `buildSpriteProtocolPlayerUpdates` (real FOV/fog culling + delete-diffs),
##     so a per-slot `PlayerViewerState` MUST persist across ticks or the
##     bot's retained scene never sheds objects that left its vision;
##   * `sim.step(inputs, prevInputs)` with the bot's own level masks decoded
##     through `decodeInputMask` — a fresh A-press (attack and not prev.attack)
##     arms the 5-tick windup, exactly as the baseline self-pulses fire.

import
  std/[os, strutils],
  bitworld/spriteprotocol,
  ctf/sim,
  ctf/global

export spriteprotocol.InputState, spriteprotocol.decodeInputMask

when defined(aoeprobe):
  import std/tables

when defined(rangehitprobe):
  import std/math
  const RangeHitNearPx = 150.0  ## the study's own band: 0-150px hit%.

when defined(ndprobe):
  import std/math

when defined(wuffprobe):
  import std/tables

when defined(wleadprobe):
  # ⭐⭐⭐ -d:wleadprobe (2026-08-20, the WINDUP LEAD / point-blank crater).
  # Hit rate has to be read BY RANGE BIN, and a MISSED shot has no target and
  # therefore no range: the tracer runs on to the wall, which is why the older
  # rangehitprobe (tracer length) cannot score this lever. So the census
  # reconstructs the shot's INTENDED target the same way tools/pb_shot_probe
  # does on hosted replays — the enemy closest to the LOCKED bearing at the
  # TRIGGER PULL — and bins on that enemy's distance at the pull.
  import std/math
  const
    WlBinEdges* = [100.0, 200.0, 300.0, 500.0, 1e9]
    WlHist = 12

type
  EvalEngine* = ref object
    sim: SimServer
    viewers: seq[PlayerViewerState]  ## one retained viewer state per slot.
    prevInputs: seq[InputState]      ## last tick's decoded inputs (fire edge).
    curInputs: seq[InputState]       ## this tick's decoded inputs.
    redShots: int                    ## fresh tracers, tallied per tick.
    blueShots: int
    redHits: int                     ## shots that LANDED on a body (a "-1" damage
    blueHits: int                    ## pop, amount 1), credited to the SHOOTING team
                                     ## (= enemy of the victim's color; friendly-fire
                                     ## hits are negligible under the friendlyBlocked
                                     ## guard). redHits/redShots = our aim accuracy —
                                     ## the "we shoot the wall, daveey lands on the
                                     ## body" complaint, measured directly.
    redGrabs: int                    ## flag pickups (steals) credited per team,
    blueGrabs: int                   ## by watching flags[*].carrier transitions.
    prevCarrier: array[Team, int]    ## last tick's carrier index per flag.
    lastCarrierProg: array[Team, float]  ## carrier's fraction-of-map progress
                                     ## toward its capture edge, updated each tick.
    dropProgSum: array[Team, float]  ## Σ progress at which non-scoring drops
    dropCount: array[Team, int]      ## happened, per STEALING team (for the mean).
    grabTick: array[Team, int]       ## tick this flag was last grabbed off its
                                     ## pedestal (-1 when home), to age the run.
    survivalSum: array[Team, int]    ## Σ ticks a carrier lived after grabbing
    survivalCount: array[Team, int]  ## before a non-scoring death, per stealer.
    when defined(wleadprobe):
      wlHist: seq[seq[tuple[x, y: float, alive: bool]]]  ## [tick mod WlHist][player]
      wlLastWb: seq[int]                                 ## windupBrads at the last tick
      wlEvCursor: int                                    ## first UNSEEN index in sim.events
      wlShots: array[4, array[5, int]]                   ## [raw team][range bin]
      wlHits: array[4, array[5, int]]
      wlPerpSum: array[4, array[5, float]]               ## Σ|perp at release|
      wlPerpIn: array[4, array[5, int]]                  ## ...of which inside 14px
    when defined(rangehitprobe):
      # -d:rangehitprobe (2026-08-07, v45 A/B reporting): range-banded shots/
      # hits, split at RangeHitNearPx (150px — the study's own band, "24pp vs
      # 3pp accuracy variance" was measured close-in). ShotFx already carries
      # the tracer's own (x0,y0)-(x1,y1) endpoints and whether it connected
      # (`hit`), so the range comes straight off the existing cosmetic tracer
      # — no engine change needed.
      redShotsNear, blueShotsNear: int
      redHitsNear, blueHitsNear: int
      redShotsFar, blueShotsFar: int
      redHitsFar, blueHitsFar: int
    when defined(shapeprobe):
      # -d:shapeprobe (2026-08-14, the Hermes SHAPE study): the geometry the
      # replay read on — how many bodies each side commits ACROSS the midline,
      # and which half its deaths fall in. Read straight off sim.players every
      # tick, so this is ENGINE truth, not a bot's belief about itself.
      #   spCross     own-half -> enemy-half transitions (one "crossing")
      #   spDeathOwn / spDeathEnemy   deaths bucketed by the half they fell in
      #   spDeepSum   Σ over ticks of (alive bodies standing in the enemy half);
      #               spDeepSum/spTicks = MEAN CONCURRENT DEEP BODIES, which is
      #               the shape number itself ("one runner, seven hold" ≈ 1.0)
      #   spDeepMax   most bodies deep at once across the episode
      spCross, spDeathOwn, spDeathEnemy, spDeepSum, spDeepMax: array[Team, int]
      spTicks: int
      spOwnLowX: array[Team, bool]   ## this team's own home sits in the low-x half
      spCenterX: float
      spWasDeep: seq[bool]           ## per slot: last tick's enemy-half flag
      spWasAlive: seq[bool]
      spLastX: seq[int]              ## last x seen ALIVE (i.e. where it died)

  SlotStat* = object
    slot*: int
    team*: int                       ## 0 = Red, 1 = Blue.
    kills*: int
    deaths*: int
    captures*: int
    lives*: int
    alive*: bool

  EpisodeResult* = object
    ticks*: int
    phaseOver*: bool
    winnerTeam*: int                 ## 0 Red, 1 Blue, -1 draw / unfinished.
    isDraw*: bool
    redKills*: int
    blueKills*: int
    redDeaths*: int                  ## deaths taken by each team; the lives
    blueDeaths*: int                 ## differential (kills-deaths) is the tiebreak.
    redLives*: int                   ## total lives remaining at game end
    blueLives*: int                  ## (Σ lives + 1 per still-alive player).
    redCaptures*: int
    blueCaptures*: int
    redShots*: int                   ## fresh tracers credited to Red shooters.
    blueShots*: int
    redHits*: int                    ## bullets that LANDED per team; redHits/redShots
    blueHits*: int                   ## is aim accuracy (the wall-vs-body miss metric).
    redGrabs*: int                   ## enemy-flag pickups by each team; the
    blueGrabs*: int                  ## grab->capture ratio is the conversion metric.
    redDropProgSum*: float           ## Σ progress-home (0..1) at each non-scoring
    blueDropProgSum*: float          ## carrier death, per stealing team, and the
    redDropCount*: int               ## count — mean = where the run home breaks.
    blueDropCount*: int
    redSurvivalSum*: int             ## Σ ticks a carrier lived after grabbing
    blueSurvivalSum*: int            ## before a non-scoring death (mean = how
    redSurvivalCount*: int           ## fast the grab is a death sentence; a
    blueSurvivalCount*: int          ## few ticks = dies IN the nest, not en route).
    slots*: seq[SlotStat]

proc newEvalEngine*(numPlayers: int, seed: int, maxTicks: int): EvalEngine =
  ## Builds a started headless game with `numPlayers` baseline-seatable slots.
  ## Seat i -> team (i mod 2): even Red, odd Blue, matching the live default.
  var config = defaultGameConfig()
  config.seed = seed
  config.maxTicks = maxTicks
  # ⚠️⚠️ LEAGUE PHYSICS, NOT ENGINE DEFAULTS. `defaultGameConfig()` ships
  # aimTurnRate = 1 slot/tick and gunRange = 1050, but every live paintbot
  # config (cfg_default/cfg_4ffa/cfg_4ffa8 + the hosted league) passes
  # aimTurnRate = 5 and gunRange = 1300. At rate 1 the GV36 slot servo is a
  # plain shortest-arc turn and the whole spin-budget family is INERT, so a
  # harness on the defaults silently measures nothing for any aim lever.
  # Override to the league values; AIMRATE / GUNRANGE reproduce the old runs.
  let
    aimRateEnv = getEnv("AIMRATE")
    gunRangeEnv = getEnv("GUNRANGE")
  config.aimTurnRate = (if aimRateEnv.len > 0: parseInt(aimRateEnv) else: 5)
  config.gunRange = (if gunRangeEnv.len > 0: parseInt(gunRangeEnv) else: 1300)
  config.maxGames = 0                # never auto-quit; harness owns the loop.
  # Generated-board probes (plan #16): the league draws a NEW map every episode,
  # and several policy reads (med-kit spots, shield spawns, endzones) are arena
  # formulas that are only true on `arena`. These env overrides let a probe run
  # the deterministic in-process rig on a GENERATED board. Unset = unchanged, so
  # every existing gate/probe output stays byte-identical. Harness-only file: it
  # is never compiled into /bin/baseline (the Dockerfile builds baseline.nim).
  if getEnv("EVAL_MAP").len > 0:
    config.mapPath = getEnv("EVAL_MAP")
  # ⭐ EVAL_MAPSPEC (2026-08-17, one-door validation): run the mirror on the
  # EXACT board a recorded league episode was played on. Every replay's config
  # carries the expanded geometry as `mapSpec` (sim_config.nim:695 fills it for
  # every "gen" map), and resolveCtfMapMetadata gives an explicit mapSpec
  # priority over mapPath/mapSeed — so this is byte-exact, not a regeneration.
  # ⚠️ REGENERATING FROM A SEED CANNOT WORK: the map name "gen-57711" carries
  # the generator's winning ATTEMPT seed, while the hosted config leaves
  # mapSeed at -1 — so `mapSeed=57711` runs generateCtfMap FROM 57711 and can
  # land on a different map. The recorded spec is the only exact handle.
  #
  # ⭐⭐⭐ THE WORKING ffa4 RECIPE (2026-08-20, verified end to end). Use this;
  # the recipe that has been circulating — EVAL_MAPSYM / EVAL_MAPLAYOUT — is
  # DEAD, zero occurrences repo-wide, and configures NOTHING.
  #
  #   1. Dump the board out of a CURRENT-ERA hosted ffa4 replay:
  #        /tmp/door_entry.out <replay-file> --dump-mapspec /tmp/ms1.json
  #      (it writes the JSON and THEN dies on a replay hash mismatch, because
  #      that binary carries a different policy — the dump is already on disk,
  #      do not read the crash as a bad dump. Verified: the dumped JSON is
  #      key-for-key identical, 18/18, to the mapSpec embedded in the replay's
  #      own config header, so this is a pass-through, not a regeneration.)
  #   2. Run the SHIPPED policy on it:
  #        CONTROL_SHIPPED=1 SHIPBASE=1 EVAL_TEAMS=4 \
  #        EVAL_MAPSPEC=/tmp/ms1.json ./harness.out --games 4 --ticks 1200
  #      ⚠️ BOTH CONTROL_SHIPPED=1 AND SHIPBASE=1. Without them the rig runs
  #      defaultCombatTune — holdLine, regroupPush, planLayer and most of the
  #      champion are OFF — and every tune-gated site reads as unreachable.
  #
  # ⚠️ WHY IT MATTERS, not optional: `EVAL_MAP=gen` with EVAL_TEAMS=4 builds a
  # 1728 SQUARE, rot90, with the layout drawn on a coin flip (~45% `plus`).
  # The hosted ffa4 board has been a 1235x659 RECTANGLE, quadmirror, layout
  # PINNED to `corners` in an authored mapSpec, on 2352 of 2352 episodes since
  # coworld 0.7.202 (2026-08-06). Those are different map FAMILIES: on the
  # square the four bases are equidistant, on the real rectangle the nearest
  # rival is always the VERTICAL neighbour (460px vs 862px), which is the whole
  # ballgame for any positional measurement. A gen board is the "mirror rig
  # lacks the disease" trap in its exact shape.
  #
  #   /tmp/door_entry.out <replay> --dump-mapspec /tmp/m.json
  #   EVAL_MAPSPEC=/tmp/m.json EVAL_SCORING=pot /tmp/grabprobe.out ...
  if getEnv("EVAL_MAPSPEC").len > 0:
    config.mapSpec = readFile(getEnv("EVAL_MAPSPEC"))
  if getEnv("EVAL_TEAMS").len > 0:
    config.teams = parseInt(getEnv("EVAL_TEAMS"))
  if getEnv("EVAL_SCORING").len > 0:
    config.scoring = getEnv("EVAL_SCORING")
  # ⭐⭐ EVAL_BARRAGE (2026-08-20, lever-liveness correctness pass): the
  # GRENADE-BARRAGE ENDGAME, which this rig could not previously see AT ALL.
  # The 2026-08-20 audit reported `BarrageDepthPx` as 0.0 on 100% of frames and
  # concluded hazardSense's barrage branch was a constant-false guard. It is
  # not — the RIG was blind. `defaultGameConfig()` ships `barrageMaxPerSec: 0`
  # (sim_config.nim:52) and the overrides above never touched it, while the
  # HOSTED league arms `barrageMaxPerSec: 15` (+ start 4/sec, latch at 30s
  # remaining, saturate over 30s) on the 2v2, 4ffa AND 4ffa8 modes
  # (coworld_manifest_paintbot.json). So every barrage measurement taken on this
  # rig measured a mode that was switched off.
  # ⚠️ THE LATCH IS THE TRAP: the marker states depth 0 until the clock drops to
  # barrageStartSec remaining. On the hosted 7200-tick clock that is ~tick 6480,
  # so a `--ticks 6000` run reads 0 even with the mode ON. Set --ticks past the
  # latch (or shrink EVAL_BARRAGE_START) or you will re-derive the same false
  # null. maxTicks > 0 is REQUIRED by sim_config validation when the mode is on.
  # Unset = unchanged, so every existing gate/probe output stays byte-identical.
  # ⭐ MEASURED 2026-08-20 with -d:barrprobe, ONE episode, seed 101:
  #     EVAL_BARRAGE=15                      -> maxDepth 0, 0 frames  (episode ended
  #                                             before the latch at ~tick 6280)
  #     EVAL_BARRAGE=15 EVAL_BARRAGE_START=280
  #                                          -> maxDepth 330px, 20,136 depth-frames,
  #                                             20,136 post/stand vetoes,
  #                                             14,970 body-EVACUATION frames
  # So hazardSense's barrage branch is not merely reachable, it DOMINATES the feet
  # once the ring is up. Use EVAL_BARRAGE_START to reach it deterministically; the
  # default 30s latch needs an episode that survives to ~tick 6280.
  if getEnv("EVAL_BARRAGE").len > 0:
    config.barrageMaxPerSec = parseInt(getEnv("EVAL_BARRAGE"))
    config.barrageStartPerSec = BarrageStartPerSec
    config.barrageStartSec = BarrageStartSec
    config.barrageSaturateSec = BarrageSaturateSec
    if getEnv("EVAL_BARRAGE_START").len > 0:
      config.barrageStartSec = parseInt(getEnv("EVAL_BARRAGE_START"))
  result = EvalEngine(sim: initSimServer(config))
  result.sim.gameEventLoggingEnabled = false  # keep the run quiet (a SimServer
                                              # field, defaults true post-init).
  when defined(roleprobe):
    # -d:roleprobe (2026-08-14, mid-quad break): the tier-2 sink is the only way
    # to see FRIENDLY FIRE, which is the crowding metric a MIRROR rig can
    # actually move (entry-y cannot — this rig's baseline is already 140-205px
    # where the field shows 5-31px). Field reading: 8.1% of half4 deaths are
    # own-colour (60 Picasso-on-Picasso, 42 from filler teammates) on exactly
    # the deal where three of four seats are mids.
    result.sim.collectEvents = true
  when defined(sprayab):
    result.sim.collectEvents = true
  when defined(v59ab):
    # -d:v59ab (the v59 bundle A/B): Death carries victim AND killer, and Pickup
    # carries the item name — the two channels the deaths-by-shooter split and
    # the medkit/shield uptake rows are built from. Nothing else can supply them
    # (a counter-diff of p.deaths cannot name a killer).
    result.sim.collectEvents = true
  when defined(wkprobe):
    # -d:wkprobe (2026-08-07, kept permanently like canprobe/ssprobe): turn on
    # the tier-2 event sink so weaponKillCounts() below can read weapon-
    # attributed Kill events (weapon="gun"/"spray"/"grenade"). Off by default
    # (collectEvents costs real allocation), so every other probe build stays
    # exactly as fast.
    result.sim.collectEvents = true
  when defined(wuffprobe):
    # ⭐⭐⭐ -d:wuffprobe (2026-08-19, the WINDUP FRIENDLY-FIRE VETO): the tier-2
    # sink is the ONLY engine-truth source for "which body stopped this bullet"
    # and, via GunTrigger's actionId, for WHICH TICK PULLED IT. Both are needed:
    # the futility bound is a join from a friendly-fire IMPACT back to the
    # TRIGGER FRAME, and only that join can say whether the veto could have
    # changed the outcome rather than merely fired.
    result.sim.collectEvents = true

  when defined(wleadprobe):
    # -d:wleadprobe: Shot events are the released-shot ledger (recentShots is a
    # cosmetic tracer and carries no shooter index), and their heading is the
    # LOCKED one, which is the whole subject of the lever.
    result.sim.collectEvents = true
  when defined(aoeprobe):
    # -d:aoeprobe (2026-08-19, the AoE friendly-fire hole): the tier-2 sink is
    # the ONLY source of weapon-attributed friendly DAMAGE (weaponKillCounts and
    # friendlyFireCounts split KILLS by weapon but pool damage into one number,
    # and the finding is stated in hit points, not bodies).
    result.sim.collectEvents = true
  when defined(ndprobe):
    # -d:ndprobe (2026-08-14, the v56 nade package): the tier-2 sink carries
    # GrenadeThrow / GrenadeImpact / Pickup, which is the only ENGINE-TRUTH
    # source for throws, supply and blast multiplicity (a policy-side counter
    # of what the bot BELIEVES is not the field metric).
    result.sim.collectEvents = true
  for i in 0 ..< numPlayers:
    discard result.sim.addPlayer("bot" & $i, trusted = true)
  result.sim.startGame()
  when defined(ndprobe):
    # Print the sim's OWN grenade spawn geometry, once per episode. This is the
    # evidence for nadeSupply's premise: the four corners are derived from map
    # size + layout alone (grenadeSpawnPoints), planted with no
    # nearest-walkable nudge, and never move for the whole episode — i.e. they
    # are STATIC KNOWN POINTS like the shield/plasma-arc spawns, not something
    # the 90px vision bubble has to find.
    var pts = ""
    for sp in result.sim.grenadeSpawns:
      pts.add " " & $sp.x & "," & $sp.y
    echo "NDMAP ", result.sim.gameMap.width, "x", result.sim.gameMap.height,
      " layout=", result.sim.gameMap.layout, " teams=", result.sim.config.teams,
      " grenadeSpawns:", pts
  result.viewers = newSeq[PlayerViewerState](numPlayers)
  for i in 0 ..< numPlayers:
    result.viewers[i] = initPlayerViewerState()
  result.prevInputs = newSeq[InputState](numPlayers)
  result.curInputs = newSeq[InputState](numPlayers)
  for team in Team:
    result.prevCarrier[team] = -1
    result.grabTick[team] = -1
  when defined(shapeprobe):
    # The two pedestals are mirrored across the midline on every board, so their
    # midpoint IS the centre line — no map-width constant needed (and it stays
    # correct on generated boards, which the width constant would not).
    let
      redHomeX = result.sim.gameMap.flagHome(Red).x.float
      blueHomeX = result.sim.gameMap.flagHome(Blue).x.float
    result.spCenterX = (redHomeX + blueHomeX) / 2.0
    result.spOwnLowX[Red] = redHomeX < result.spCenterX
    result.spOwnLowX[Blue] = blueHomeX < result.spCenterX
    result.spWasDeep = newSeq[bool](numPlayers)
    result.spWasAlive = newSeq[bool](numPlayers)
    result.spLastX = newSeq[int](numPlayers)
    for i in 0 ..< numPlayers:
      result.spWasAlive[i] = true
      result.spLastX[i] = result.sim.players[i].x

proc playerCount*(engine: EvalEngine): int =
  engine.sim.players.len

proc teamOfSlot*(engine: EvalEngine, slot: int): int =
  ## 0 Red / 1 Blue, read straight off the seated player.
  ord(engine.sim.players[slot].team)

proc slotLifeState*(engine: EvalEngine, slot: int): tuple[hp, lives: int, alive: bool] =
  ## GROUND-TRUTH hp/lives/alive for one seat, straight off sim.players — for
  ## the ffa4 lives audit (2026-08-17): "lives spent by half-time", medkit
  ## takes, and P(escape|hp==1) all need ground truth sampled every tick, not
  ## the bot's own fogged/label-parsed perception (the 2026-08-05 field-metric
  ## rule). Unconditional, not probe-gated: a read-only accessor with no
  ## gameplay effect, and this module never compiles into the shipped player.
  let p = engine.sim.players[slot]
  (hp: p.hp, lives: p.lives, alive: p.alive)

proc slotPos*(engine: EvalEngine, slot: int): tuple[x, y: float, alive: bool] =
  ## GROUND-TRUTH body position for one seat. Same class as slotLifeState: a
  ## read-only accessor with no gameplay effect, never compiled into the shipped
  ## player. Used by -d:lkprobe to give the target-switch ledger a real target
  ## IDENTITY (nearest engine body to the bot's own lockPos) — the whole point of
  ## the lockPos bug is that the POLICY has no identity, so the instrument that
  ## scores it must get one from the engine rather than from another Vec match.
  let pl = engine.sim.players[slot]
  (x: float(pl.x), y: float(pl.y), alive: pl.alive)

proc stateHash*(engine: EvalEngine): uint64 =
  ## The engine's own deterministic replay hash (sim_state.gameHash): every
  ## player x/y/vel/aim/hp/lives, the flags, and every pickup respawn timer.
  ## This is the TRAJECTORY half of the control-identity proof — a button-mask
  ## fingerprint alone cannot see a divergence that has not yet reached a button.
  engine.sim.gameHash()

proc isPlaying*(engine: EvalEngine): bool =
  engine.sim.phase == Playing

when defined(ohshitprobe):
  import std/math
  proc nearestEnemyMate*(engine: EvalEngine, slot: int): tuple[e, m: float] =
    ## Ground-truth nearest living enemy / mate distance to `slot` (probe only).
    let me = engine.sim.players[slot]
    var nE = 1e9
    var nM = 1e9
    for j in 0 ..< engine.sim.players.len:
      if j == slot or not engine.sim.players[j].alive: continue
      let q = engine.sim.players[j]
      let dd = sqrt(float((me.x - q.x) * (me.x - q.x) +
                          (me.y - q.y) * (me.y - q.y)))
      if q.team == me.team:
        if dd < nM: nM = dd
      else:
        if dd < nE: nE = dd
    (e: nE, m: nM)

when defined(rwtruth):
  proc slotTruth*(engine: EvalEngine, slot: int):
      tuple[x, y: float, alive: bool, team: int] =
    ## GROUND TRUTH position/liveness for one seat, straight off `sim.players` —
    ## never the bot's own fogged perception (the 2026-08-05 field-metric rule:
    ## a `-d:` probe that counts what the bot BELIEVES is not the field metric).
    ## Probe builds only; the shipped player never sees this module.
    let p = engine.sim.players[slot]
    (x: float(p.x), y: float(p.y), alive: p.alive, team: ord(p.team))

when defined(hscensus):
  proc hsVitals*(engine: EvalEngine, slot: int):
      tuple[deaths: int, alive: bool, x, y: float] =
    ## GROUND TRUTH death ledger + position for one seat (census builds only).
    ## Deaths are counted off `sim.players`, never off the bot's own fogged
    ## belief, so "where did we die" is engine truth and not perception.
    let p = engine.sim.players[slot]
    (deaths: p.deaths, alive: p.alive, x: float(p.x), y: float(p.y))

when defined(fpprobe):
  proc slotVitals*(engine: EvalEngine, slot: int):
      tuple[hp: int, alive: bool, deaths: int, lives: int, x, y: int] =
    ## GROUND TRUTH vitals for one seat (probe builds only). The ffa4 metrics
    ## are life-economy metrics — lives spent by half-time, P(escape | hp==1) —
    ## and neither can be read from a bot's own fogged belief. Straight off
    ## sim.players, same source the hosted results JSON is built from.
    let p = engine.sim.players[slot]
    (hp: p.hp, alive: p.alive, deaths: p.deaths, lives: p.lives,
     x: int(p.x), y: int(p.y))

  proc slotCaptures*(engine: EvalEngine, slot: int): int =
    engine.sim.players[slot].captures

when defined(kselprobe):
  proc medKitSpawnsTruth*(engine: EvalEngine): seq[PickupSpawn] =
    ## ⭐⭐⭐ kitSel (2026-08-20): ENGINE-TRUTH med-kit spawns, each with its
    ## `present` flag and `respawnAt` tick. This is the only honest source for
    ## the placebo-controlled approach metric — "px closed toward the nearest
    ## STOCKED kit vs a matched EMPTY control" — because a probe reading the
    ## bot's own fogged view would score the policy against its own beliefs and
    ## could never see the spots it is blind to. Same argument slotVitals makes.
    ## Probe builds only; never compiled into /bin/baseline (the Dockerfile
    ## builds baseline.nim, and this file is harness-only besides).
    engine.sim.medKitSpawns

  proc mapSize*(engine: EvalEngine): tuple[w, h: int] =
    ## The LOADED board's dimensions. The formula addresses the control arm
    ## walks to are derived from these (W div 2, H div 3 / 2H div 3), so the
    ## probe must read them off the same board EVAL_MAPSPEC loaded rather than
    ## hard-code the `arena` pair — otherwise the measured phantom offset is a
    ## property of the probe instead of the map.
    (w: engine.sim.gameMap.width, h: engine.sim.gameMap.height)

  proc shieldSpawnsTruth*(engine: EvalEngine): seq[PickupSpawn] =
    ## ENGINE-TRUTH shield spawns — ONE PER TEAM. sim.shieldSpawnPoints picks
    ## RED's point only and carries every other team's through the map's own
    ## symmetry (teamOrbitPoints, a rot90 on layoutCorners), so on a 4-team
    ## board there are FOUR, in a quarter-turn orbit. The policy addresses them
    ## with `if team == Red: vec(50, y) else: vec(MapW - 50, y)`, which is the
    ## layoutSides x-MIRROR — a different transform on a different layout.
    ## Measuring that gap is the whole point of this accessor.
    engine.sim.shieldSpawns

  proc arcSpawnsTruth*(engine: EvalEngine): seq[PickupSpawn] =
    ## Same for the plasma-arc / spray-can spawns (one per team, the opposite
    ## half of each endzone from that team's shield).
    engine.sim.plasmaArcSpawns

  proc slotItems*(engine: EvalEngine, slot: int):
      tuple[shield, arc, alive: bool] =
    ## Whether this seat is HOLDING a shield / arc right now, straight off
    ## sim.players. A false->true transition is a pickup; counted per RAW TEAM
    ## INDEX and per team-seat so a seat effect cannot masquerade as a colour
    ## effect (ShieldRushSeat alone carries most shield grabs).
    let p = engine.sim.players[slot]
    (shield: p.hasShield, arc: p.hasPlasmaArc, alive: p.alive)

when defined(ssprobe):
  # v7-only: count accidental sword/shield possession (auto-disarm). The
  # hasSword/hasShield fields exist only on the GameVersion 7 engine, so this
  # accessor compiles ONLY in the v7 worktree under -d:ssprobe.
  proc swordShieldOf*(engine: EvalEngine, slot: int):
      tuple[sword, shield, alive: bool] =
    let p = engine.sim.players[slot]
    (sword: p.hasSword, shield: p.hasShield, alive: p.alive)

when defined(wkprobe):
  # -d:wkprobe (2026-08-07, kept permanently — the utility-weapon kill-share
  # audit tool): drains the tier-2 event stream ONCE at episode end and
  # tallies weapon-attributed Kill events (weapon="gun"/"spray"/"grenade")
  # per team. `source` on a SimEvent is the killer's stable JOIN slot
  # (sim_state.eventSlot / player.joinOrder), not necessarily the raw player
  # index, so build the join-slot->team map the same way
  # tools/extract_events.nim does (slotTeam[player.joinOrder] = player.team)
  # rather than assuming they match.
  proc weaponKillCounts*(engine: EvalEngine): tuple[
      redGun, blueGun, redSpray, blueSpray, redNade, blueNade: int] =
    var teamOfJoinSlot = newSeq[Team](engine.sim.players.len)
    for p in engine.sim.players:
      if p.joinOrder >= 0 and p.joinOrder < teamOfJoinSlot.len:
        teamOfJoinSlot[p.joinOrder] = p.team
    for e in engine.sim.events:
      if e.kind != Kill: continue
      if e.source < 0 or e.source >= teamOfJoinSlot.len: continue
      let isRed = teamOfJoinSlot[e.source] == Red
      case e.weapon
      of "gun":
        if isRed: inc result.redGun else: inc result.blueGun
      of "spray":
        if isRed: inc result.redSpray else: inc result.blueSpray
      of "grenade":
        if isRed: inc result.redNade else: inc result.blueNade
      else: discard

when defined(roleprobe):
  # ⭐⭐ FRIENDLY FIRE — the crowding metric, measured not inferred. Friendly fire
  # is ON in this engine (selectFireTarget stops at the FIRST body, whoever it
  # belongs to), so two of ours in one corridor is not a figure of speech: it is
  # a teammate standing on the ray. Field: 8.1% of half4 deaths came from our own
  # colour. Split by weapon because the two mechanisms are different — a `gun`
  # own-kill is a body on the line, a `grenade` own-kill is the blast catching a
  # cluster (the 58.4% stat), and the mid quad predicts BOTH.
  #
  # ⚠️ `source`/`target` are stable JOIN slots, not raw player indices — the same
  # trap weaponKillCounts documents. Build the join-slot map, never assume they
  # match.
  proc friendlyFireCounts*(engine: EvalEngine): tuple[
      kills, ffKills, ffGun, ffNade, ffSpray,
      dmg, ffDmg: int] =
    var teamOfJoinSlot = newSeq[int](engine.sim.players.len)
    for i in 0 ..< teamOfJoinSlot.len: teamOfJoinSlot[i] = -1
    for p in engine.sim.players:
      if p.joinOrder >= 0 and p.joinOrder < teamOfJoinSlot.len:
        teamOfJoinSlot[p.joinOrder] = ord(p.team)
    for e in engine.sim.events:
      if e.kind notin {Kill, Damage}: continue
      if e.source < 0 or e.source >= teamOfJoinSlot.len: continue
      if e.target < 0 or e.target >= teamOfJoinSlot.len: continue
      let st = teamOfJoinSlot[e.source]
      let tt = teamOfJoinSlot[e.target]
      if st < 0 or tt < 0: continue
      # Self-damage (own grenade at own feet) is a different defect from
      # shooting a MATE, and only the second one is crowding. Exclude it.
      let friendly = st == tt and e.source != e.target
      if e.kind == Kill:
        inc result.kills
        if friendly:
          inc result.ffKills
          case e.weapon
          of "gun": inc result.ffGun
          of "grenade": inc result.ffNade
          of "spray": inc result.ffSpray
          else: discard
      else:
        inc result.dmg
        if friendly: inc result.ffDmg

when defined(canprobe):
  # -d:canprobe: engine-side TRUTH for the spray-can pickup path — whether the
  # slot is actually holding a can this tick. Paired with the policy-side
  # cpSeen/cpSeek counters this splits "never saw one" from "saw one, declined"
  # from "sought one and missed". The field name is still the pre-0.7.x
  # `hasPlasmaArc`; only the WIRE label was renamed to `spray can`.
  proc sprayOf*(engine: EvalEngine, slot: int): tuple[can, alive: bool] =
    let p = engine.sim.players[slot]
    (can: p.hasPlasmaArc, alive: p.alive)

when defined(ndprobe):
  # -d:ndprobe: ENGINE TRUTH for the v56 nade package.
  type NdRec* = object
    ## One grenade-relevant tier-2 event, flattened for the harness.
    ## kind: 0 = GrenadeThrow, 1 = GrenadeImpact, 2 = grenade Pickup.
    kind*: int
    tick*: int
    slot*: int                 ## acting player's stable JOIN slot (-1 = n/a)
    team*: int                 ## that player's team ordinal (-1 = n/a)
    actionId*: int64           ## ties a throw to its impact
    victims*: array[4, int]    ## on an impact: bodies damaged, per team

  proc ndGrenadeRecs*(engine: EvalEngine): seq[NdRec] =
    ## Drains the collected event stream into throw / impact / pickup records.
    ## `source` is a stable JOIN slot, not the raw player index, so map it the
    ## same way weaponKillCounts and tools/extract_events.nim do.
    var teamOfJoinSlot = newSeq[int](engine.sim.players.len)
    for i in 0 ..< teamOfJoinSlot.len: teamOfJoinSlot[i] = -1
    for p in engine.sim.players:
      if p.joinOrder >= 0 and p.joinOrder < teamOfJoinSlot.len:
        teamOfJoinSlot[p.joinOrder] = ord(p.team)
    proc teamOf(s: int): int =
      if s >= 0 and s < teamOfJoinSlot.len: teamOfJoinSlot[s] else: -1
    for e in engine.sim.events:
      case e.kind
      of GrenadeThrow:
        result.add NdRec(kind: 0, tick: e.tick, slot: e.source,
                         team: teamOf(e.source), actionId: e.actionId)
      of GrenadeImpact:
        var rec = NdRec(kind: 1, tick: e.tick, slot: e.source,
                        team: teamOf(e.source), actionId: e.actionId)
        for d in e.damages:
          let t = teamOf(d.slot)
          if t in 0 .. 3: inc rec.victims[t]
        result.add rec
      of Pickup:
        if e.item == "grenade":
          result.add NdRec(kind: 2, tick: e.tick, slot: e.source,
                           team: teamOf(e.source), actionId: e.actionId)
      else: discard

  proc ndSpacingSample*(engine: EvalEngine): tuple[
      bots, underBlast: int, sumNearest: float, hist: array[6, int]] =
    ## GROUND-TRUTH nearest-living-mate distance for every living bot this
    ## tick. `underBlast` = bodies whose nearest mate sits inside NadeBlast,
    ## i.e. the population one enemy grenade takes two of. Histogram buckets
    ## (px): 0-26, 26-52, 52-66, 66-100, 100-200, 200+.
    for i in 0 ..< engine.sim.players.len:
      let me = engine.sim.players[i]
      if not me.alive: continue
      var nearest = 1e9
      for j in 0 ..< engine.sim.players.len:
        if j == i: continue
        let q = engine.sim.players[j]
        if not q.alive or q.team != me.team: continue
        let d = sqrt(float((me.x - q.x) * (me.x - q.x) +
                           (me.y - q.y) * (me.y - q.y)))
        if d < nearest: nearest = d
      if nearest > 1e8: continue         # no living mate: not a pair at all
      inc result.bots
      result.sumNearest += nearest
      if nearest <= GrenadeBlastRadius.float: inc result.underBlast
      let b =
        if nearest < 26.0: 0
        elif nearest < 52.0: 1
        elif nearest < 66.0: 2
        elif nearest < 100.0: 3
        elif nearest < 200.0: 4
        else: 5
      inc result.hist[b]

when defined(aoeprobe):
  # ── ⭐⭐ AoE FRIENDLY-FIRE ENGINE TRUTH (2026-08-19). Damage in HIT POINTS,
  # split by weapon and by friend/foe, plus a per-ACTION ledger the rig joins to
  # the policy's own veto flags. That join is what turns "the veto fired" into
  # "the veto would have removed N hit points of friendly fire and M hit points
  # of enemy damage" — the futility bound, with no sweep.
  #
  # ⚠️ e.source / e.target / d.slot are stable JOIN slots, not raw player
  # indices (see emitEvent) — build the map, never assume they match.
  proc aoeTeamMap(engine: EvalEngine): seq[int] =
    result = newSeq[int](engine.sim.players.len)
    for i in 0 ..< result.len: result[i] = -1
    for p in engine.sim.players:
      if p.joinOrder >= 0 and p.joinOrder < result.len:
        result[p.joinOrder] = ord(p.team)

  proc aoeFfDamage*(engine: EvalEngine): tuple[
      gunFf, sprayFf, nadeFf, gunAll, sprayAll, nadeAll, nadeSelf: int] =
    ## Damage in HIT POINTS by weapon. `*Ff` is mate-on-mate only: a blast at
    ## one's OWN feet is a different defect and is broken out as nadeSelf rather
    ## than pooled in (friendlyFireCounts makes the same exclusion).
    let team = engine.aoeTeamMap()
    for e in engine.sim.events:
      if e.kind != Damage: continue
      if e.source notin 0 ..< team.len or e.target notin 0 ..< team.len: continue
      let st = team[e.source]
      let tt = team[e.target]
      if st < 0 or tt < 0: continue
      let selfHit = e.source == e.target
      let friendly = st == tt and not selfHit
      case e.weapon
      of "gun":
        result.gunAll += e.amount
        if friendly: result.gunFf += e.amount
      of "spray":
        result.sprayAll += e.amount
        if friendly: result.sprayFf += e.amount
      of "grenade":
        result.nadeAll += e.amount
        if friendly: result.nadeFf += e.amount
        if selfHit: result.nadeSelf += e.amount
      else: discard

  proc aoeNadeRows*(engine: EvalEngine): seq[tuple[
      slot, throwTick, ffDmg, foeDmg, selfDmg: int]] =
    ## One row per THROW that reached a burst, carrying the hit points that
    ## burst dealt to mates and to enemies. Keyed by the thrower's join slot and
    ## the LAUNCH tick (recovered through actionId, which ties GrenadeThrow to
    ## GrenadeImpact) so it lines up with the policy's release ledger.
    let team = engine.aoeTeamMap()
    var throwTick = initTable[int64, int]()
    for e in engine.sim.events:
      if e.kind == GrenadeThrow: throwTick[e.actionId] = e.tick
    for e in engine.sim.events:
      if e.kind != GrenadeImpact: continue
      if e.source notin 0 ..< team.len: continue
      let st = team[e.source]
      if st < 0: continue
      var row = (slot: e.source,
                 throwTick: throwTick.getOrDefault(e.actionId, e.tick),
                 ffDmg: 0, foeDmg: 0, selfDmg: 0)
      for d in e.damages:
        if d.slot notin 0 ..< team.len: continue
        if d.slot == e.source: row.selfDmg += d.amount
        elif team[d.slot] == st: row.ffDmg += d.amount
        else: row.foeDmg += d.amount
      result.add row

  proc aoeSprayRows*(engine: EvalEngine): seq[tuple[
      slot, tick, ffDmg, foeDmg: int]] =
    ## One row per spray DAMAGE event (the cone re-picks victims every active
    ## tick, so an activation is a burst of these; the rig folds them back onto
    ## the press that started them).
    let team = engine.aoeTeamMap()
    for e in engine.sim.events:
      if e.kind != Damage or e.weapon != "spray": continue
      if e.source notin 0 ..< team.len or e.target notin 0 ..< team.len: continue
      let st = team[e.source]
      let tt = team[e.target]
      if st < 0 or tt < 0 or e.source == e.target: continue
      if st == tt:
        result.add (slot: e.source, tick: e.tick, ffDmg: e.amount, foeDmg: 0)
      else:
        result.add (slot: e.source, tick: e.tick, ffDmg: 0, foeDmg: e.amount)

when defined(idhash):
  proc slotIdState*(engine: EvalEngine, slot: int):
      tuple[x, y, hp: int, alive: bool] =
    ## GROUND TRUTH for the control-identity trajectory hash. Straight off
    ## sim.players, never a bot's fogged belief. -d:idhash builds only.
    let p = engine.sim.players[slot]
    (x: int(p.x), y: int(p.y), hp: p.hp, alive: p.alive)

when defined(sprayab):
  # ⭐⭐⭐ -d:sprayab (2026-08-20, the carried-can funnel A/B). Everything here is
  # PER RAW ENGINE TEAM INDEX (0..3), never Red/Blue: `p.team` collapses teams 2
  # and 3 onto Blue on a 4-team board, and a colour-named metric once compared a
  # 4-seat arm against a 12-seat one. Team identity comes from the sim's own
  # `slotIdentityIndex` basis, i.e. joinOrder mod teams, which is the same basis
  # SPRAYCONETEAM arms.
  proc sprayAbTeamOf*(engine: EvalEngine, slot: int): int =
    let teams = max(engine.sim.config.teams, 2)
    if slot < 0: -1 else: slot mod teams

  proc sprayAbSlot*(engine: EvalEngine, slot: int):
      tuple[can, alive: bool, arcTicks: int] =
    ## Ground truth for one seat: is a can held, and the live cone countdown.
    ## A PRESS is a RISE in arcTicks (startArcFire sets it to
    ## PlasmaArcActiveTicks) — `spray_use.amount` is always 0 and SprayUse fires
    ## once per ACTIVE TICK, so neither can count presses.
    let p = engine.sim.players[slot]
    (can: p.hasPlasmaArc, alive: p.alive, arcTicks: p.arcTicksLeft)

  proc sprayAbEvents*(engine: EvalEngine, cursor: var int): tuple[
      dmg, ffDmg, kills, ffKills, hits: array[4, int],
      dmgSrc: array[32, bool]] =
    ## Spray damage/kills SINCE `cursor`, bucketed by the ATTACKER's raw team.
    ## ⚠️ THE CURSOR IS LOAD-BEARING. Nothing in this rig ever drains
    ## `sim.events` — friendlyFireCounts and weaponKillCounts deliberately scan
    ## the whole accumulated list ONCE at episode end. A per-TICK reader that
    ## rescans from index 0 therefore re-counts every earlier event on every
    ## later tick and reports totals quadratic in episode length (the first cut
    ## of this probe printed 14,532 spray hits from 8 presses). Read forward
    ## from the cursor and leave the list alone.
    ## Self-damage is excluded from the friendly buckets: spraying yourself is a
    ## different defect from spraying a mate, and only the second one is crowding.
    var teamOf = newSeq[int](engine.sim.players.len)
    for i in 0 ..< teamOf.len: teamOf[i] = -1
    for p in engine.sim.players:
      if p.joinOrder >= 0 and p.joinOrder < teamOf.len:
        teamOf[p.joinOrder] = engine.sprayAbTeamOf(p.joinOrder)
    if cursor > engine.sim.events.len: cursor = 0   # new episode
    let startAt = cursor
    cursor = engine.sim.events.len
    for i in startAt ..< engine.sim.events.len:
      let e = engine.sim.events[i]
      if e.weapon != "spray": continue
      if e.source < 0 or e.source >= teamOf.len: continue
      let st = teamOf[e.source]
      if st notin 0 .. 3: continue
      let tt = (if e.target >= 0 and e.target < teamOf.len: teamOf[e.target] else: -1)
      let friendly = tt == st and e.target != e.source
      case e.kind
      of Damage:
        inc result.hits[st]
        if e.source < 32: result.dmgSrc[e.source] = true
        if friendly: result.ffDmg[st] += e.amount
        else: result.dmg[st] += e.amount
      of Kill:
        if friendly: inc result.ffKills[st] else: inc result.kills[st]
      else: discard

proc frameFor*(engine: EvalEngine, slot: int): string =
  ## The exact sprite packet blob the live server would send this slot this
  ## tick: real fogged view, delta-encoded against the slot's retained viewer.
  var nextState: PlayerViewerState
  let packet = engine.sim.buildSpriteProtocolPlayerUpdates(
    slot, engine.viewers[slot], nextState)
  engine.viewers[slot] = nextState
  blobFromBytes(packet)

when defined(identprobe):
  # ⭐⭐ CONTROL-IDENTITY PROBE (2026-08-20). Proves an "inert when gated off"
  # patch really is inert, on the two streams that can possibly differ:
  #   * ipMaskFnv — every emitted button mask folded in strict (tick, slot)
  #     order, so a single flipped button on one slot on one tick diverges it;
  #   * ipHashFnv — the ENGINE's own per-tick gameHash folded the same way, so
  #     a divergence the masks happen to alias still shows up.
  # Both are FNV-1a 64. ⚠️ Build each arm with its OWN --nimcache: a shared one
  # has faked an identity match before.
  var ipMaskFnv: uint64 = 0xcbf29ce484222325'u64
  var ipHashFnv: uint64 = 0xcbf29ce484222325'u64
  var ipMasks = 0
  var ipTicks = 0

  proc ipFold(h: var uint64, v: uint64) =
    for i in 0 ..< 8:
      h = h xor ((v shr (i * 8)) and 0xff'u64)
      h = h * 0x100000001b3'u64

  proc identProbeReport*(): string =
    ## One line, both digests plus their populations. Two arms are byte-identical
    ## iff BOTH digests and BOTH counts match. A count mismatch alone means the
    ## arms did not even play the same number of frames.
    "IDENTPROBE maskFnv=" & $ipMaskFnv & " hashFnv=" & $ipHashFnv &
      " masks=" & $ipMasks & " ticks=" & $ipTicks

proc setMask*(engine: EvalEngine, slot: int, mask: uint8) =
  ## Records one bot's chosen button mask for the pending step.
  when defined(identprobe):
    # Folded BEFORE the decode so the probe reads exactly the byte the live
    # client would have put on the wire.
    ipFold(ipMaskFnv, uint64(engine.sim.tickCount))
    ipFold(ipMaskFnv, uint64(slot))
    ipFold(ipMaskFnv, uint64(mask))
    inc ipMasks
  engine.curInputs[slot] = decodeInputMask(mask)

proc applyShout*(engine: EvalEngine, slot: int, text: string) =
  ## Registers one bot's shout into the sim exactly as the live server does:
  ## the server buffers each player's chat during the tick window and calls
  ## `sim.applyShout(playerIndex, chatText)` for every one just before
  ## `sim.step` (server.nim ~1015-1026). The sim enforces the alive-only,
  ## one-per-second, one-bubble-per-player rules; the shout lands in
  ## `recentShouts` and is delivered to every audible viewer on the NEXT
  ## frame build — so a bot hears a mate's shout the frame after it is made,
  ## matching the hosted timing the reaction logic was tuned against.
  engine.sim.applyShout(slot, text)

proc advance*(engine: EvalEngine) =
  ## Steps the sim one tick with the recorded masks, then rolls the fire edge.
  ## A shot's tracer is stamped with the tick it fired, so tallying tracers
  ## whose firedTick == the just-completed tick counts every shot released
  ## this step exactly once (recentShots is pruned only after ShotFxTicks).
  engine.sim.step(engine.curInputs, engine.prevInputs)
  when defined(identprobe):
    ipFold(ipHashFnv, uint64(engine.sim.tickCount))
    ipFold(ipHashFnv, uint64(engine.sim.gameHash()))
    inc ipTicks
  for i in 0 ..< engine.prevInputs.len:
    engine.prevInputs[i] = engine.curInputs[i]
  let firedTick = engine.sim.tickCount
  for shot in engine.sim.recentShots:
    if shot.firedTick == firedTick:
      if shot.color == teamColor(Red): inc engine.redShots
      elif shot.color == teamColor(Blue): inc engine.blueShots
      when defined(rangehitprobe):
        # ShotFx's own tracer endpoints give the shot's range directly — no
        # cross-referencing against damagePops needed, and `hit` already
        # says whether THIS shot connected.
        let rng = hypot(float(shot.x1 - shot.x0), float(shot.y1 - shot.y0))
        let near = rng < RangeHitNearPx
        if shot.color == teamColor(Red):
          if near:
            inc engine.redShotsNear
            if shot.hit: inc engine.redHitsNear
          else:
            inc engine.redShotsFar
            if shot.hit: inc engine.redHitsFar
        elif shot.color == teamColor(Blue):
          if near:
            inc engine.blueShotsNear
            if shot.hit: inc engine.blueHitsNear
          else:
            inc engine.blueShotsFar
            if shot.hit: inc engine.blueHitsFar
  when defined(wleadprobe):
    # ⭐ RANGE-BINNED HIT CENSUS — engine truth, replicating the hosted-replay
    # forensics. The engine accepts a centred body inside PlayerHalf(6) +
    # BulletHalfWidth(8) = 14px of PERPENDICULAR miss at the RELEASE tick, at any
    # range; `wlPerpIn` is that acceptance and `wlHits` is the engine's verdict.
    block wlead:
      if engine.wlHist.len == 0:
        engine.wlHist = newSeq[seq[tuple[x, y: float, alive: bool]]](WlHist)
        engine.wlLastWb = newSeq[int](engine.sim.players.len)
        for i in 0 ..< engine.wlLastWb.len: engine.wlLastWb[i] = -1
      let t = engine.sim.tickCount
      engine.wlHist[t mod WlHist].setLen(engine.sim.players.len)
      for i, pl in engine.sim.players:
        engine.wlHist[t mod WlHist][i] = (
          x: float(pl.x + CollisionW div 2),
          y: float(pl.y + CollisionH div 2), alive: pl.alive)
      let wu = engine.sim.config.fireWindupTicks
      # ⚠️ This rig NEVER DRAINS sim.events (the harvesters read the whole
      # episode at the end), so an unfiltered rescan every tick both re-counts
      # every shot ever fired — a 100x inflated denominator that still looks
      # plausible as a RATE — and makes the run quadratic. Walk only the tail
      # appended since last tick.
      let evStart = engine.wlEvCursor
      engine.wlEvCursor = engine.sim.events.len
      if t >= WlHist + wu:
        for ei in evStart ..< engine.sim.events.len:
          let ev = engine.sim.events[ei]
          if ev.kind != Shot or ev.weapon != "gun" or ev.source < 0: continue
          # `source` is a stable JOIN slot; the shooter's own windupBrads was
          # cleared by applyFire, so the LOCKED heading is last tick's value.
          var sh = -1
          for i in 0 ..< engine.sim.players.len:
            if engine.sim.players[i].joinOrder == ev.source: sh = i; break
          if sh < 0: continue
          let locked = (if engine.wlLastWb[sh] >= 0: engine.wlLastWb[sh]
                        else: engine.sim.players[sh].aimBrads)
          let
            (ux, uy) = aimVector(locked)
            t0 = t - wu
            m0 = engine.wlHist[t0 mod WlHist][sh]
            m1 = engine.wlHist[t mod WlHist][sh]
            shTeam = ord(engine.sim.players[sh].team)
          var best = -1
          var bestAbs = 1e18
          var bestD = 0.0
          for j in 0 ..< engine.sim.players.len:
            if j == sh or ord(engine.sim.players[j].team) == shTeam: continue
            let s0 = engine.wlHist[t0 mod WlHist][j]
            if not s0.alive or not engine.wlHist[t mod WlHist][j].alive: continue
            let
              vx = s0.x - m0.x
              vy = s0.y - m0.y
              along = vx * ux + vy * uy
              perp = vx * uy - vy * ux
            if along <= 0.0 or along > float(engine.sim.config.gunRange): continue
            if abs(perp) < bestAbs:
              bestAbs = abs(perp); best = j; bestD = hypot(vx, vy)
          if best < 0 or shTeam notin 0 .. 3: continue
          var bin = 0
          while bin < 4 and bestD >= WlBinEdges[bin]: inc bin
          let
            s1 = engine.wlHist[t mod WlHist][best]
            perp1 = (s1.x - m1.x) * uy - (s1.y - m1.y) * ux
          inc engine.wlShots[shTeam][bin]
          engine.wlPerpSum[shTeam][bin] += abs(perp1)
          if abs(perp1) <= float(PlayerHalf) + BulletHalfWidth:
            inc engine.wlPerpIn[shTeam][bin]
          # the paired ShotImpact carries the engine's own verdict.
          for ei2 in evStart ..< engine.sim.events.len:
            let e2 = engine.sim.events[ei2]
            if e2.kind == ShotImpact and e2.source == ev.source and
                e2.actionId == ev.actionId:
              if e2.target >= 0: inc engine.wlHits[shTeam][bin]
              break
      for i, pl in engine.sim.players:
        if i < engine.wlLastWb.len: engine.wlLastWb[i] = pl.windupBrads

  when defined(shapeprobe):
    # SHAPE geometry, sampled after the step so positions are this tick's truth.
    inc engine.spTicks
    var deepNow: array[Team, int]
    for i in 0 ..< engine.sim.players.len:
      let p = engine.sim.players[i]
      let t = p.team
      if p.alive:
        let deep = (if engine.spOwnLowX[t]: p.x.float > engine.spCenterX
                    else: p.x.float < engine.spCenterX)
        if deep:
          inc deepNow[t]
          if not engine.spWasDeep[i]:
            inc engine.spCross[t]     # a fresh own-half -> enemy-half crossing
        engine.spWasDeep[i] = deep
        engine.spLastX[i] = p.x
      else:
        if engine.spWasAlive[i]:
          # Death: bucket it by the half the body was standing in last tick.
          let inEnemy = (if engine.spOwnLowX[t]: engine.spLastX[i].float > engine.spCenterX
                         else: engine.spLastX[i].float < engine.spCenterX)
          if inEnemy: inc engine.spDeathEnemy[t] else: inc engine.spDeathOwn[t]
        engine.spWasDeep[i] = false   # a respawn starts home; re-crossing counts again
      engine.spWasAlive[i] = p.alive
    for t in Team:
      engine.spDeepSum[t] += deepNow[t]
      if deepNow[t] > engine.spDeepMax[t]: engine.spDeepMax[t] = deepNow[t]

  # Gun-hit tally: a fresh "-1" damage pop (amount 1 = a bullet, not the amount-2
  # grenade blast) landed on a body THIS tick. Credit the SHOOTER = the enemy of
  # the victim's color, so redHits counts Red's bullets that connected. Paired
  # with redShots this is the direct aim-accuracy signal.
  for pop in engine.sim.damagePops:
    if pop.tick == firedTick and pop.amount == 1:
      if pop.color == teamColor(Red): inc engine.blueHits    # Red victim -> Blue shot
      elif pop.color == teamColor(Blue): inc engine.redHits
  # Flag-grab tally + drop-location diagnosis. A carrier index rising from -1
  # to a live player is a fresh steal; credit the STEALING team (a flag is
  # stolen by the opposing team, so flagTeam Blue -> a Red grab). A carrier
  # falling to -1 while the game is still Playing is a NON-SCORING DROP (the
  # carrier was killed en route — a capture instead ends the game with the
  # carrier still set), so we log how far home it had gotten: 0.0 = dropped at
  # the enemy pedestal it just robbed, 1.0 = at its own capture edge. The mean
  # drop-progress tells us WHERE the run home breaks down.
  let stillPlaying = engine.sim.phase == Playing
  for team in Team:
    let carrier = engine.sim.flags[team].carrier
    # Update this carrier's progress-home while it holds the flag.
    if carrier >= 0:
      let
        # `enemy(team)` is gone from the engine: with up to four teams there is
        # no single "the opposing team". For this 2-team harness metric the
        # other side of a 2-team board is the only meaningful reading.
        stealer = (if team == Red: Blue else: Red)
        startX = engine.sim.gameMap.flagHome(team).x.float     # robbed pedestal
        endX = engine.sim.gameMap.flagHome(stealer).x.float    # own home edge
        flagX = engine.sim.flags[team].x.float
        span = (if startX != endX: startX - endX else: 1.0)
      engine.lastCarrierProg[team] = clamp((startX - flagX) / span, 0.0, 1.0)
    if carrier >= 0 and engine.prevCarrier[team] < 0:
      engine.grabTick[team] = engine.sim.tickCount    # start the survival clock
      if team == Blue: inc engine.redGrabs else: inc engine.blueGrabs
    elif carrier < 0 and engine.prevCarrier[team] >= 0 and stillPlaying:
      # Non-scoring drop: attribute the failed run to the stealing team.
      let lived = engine.sim.tickCount - engine.grabTick[team]
      if team == Blue:
        engine.dropProgSum[Red] += engine.lastCarrierProg[team]
        inc engine.dropCount[Red]
        engine.survivalSum[Red] += lived
        inc engine.survivalCount[Red]
      else:
        engine.dropProgSum[Blue] += engine.lastCarrierProg[team]
        inc engine.dropCount[Blue]
        engine.survivalSum[Blue] += lived
        inc engine.survivalCount[Blue]
    engine.prevCarrier[team] = carrier

when defined(rangehitprobe):
  proc rangeHitCounts*(engine: EvalEngine): tuple[
      redShotsNear, redHitsNear, blueShotsNear, blueHitsNear,
      redShotsFar, redHitsFar, blueShotsFar, blueHitsFar: int] =
    (redShotsNear: engine.redShotsNear, redHitsNear: engine.redHitsNear,
     blueShotsNear: engine.blueShotsNear, blueHitsNear: engine.blueHitsNear,
     redShotsFar: engine.redShotsFar, redHitsFar: engine.redHitsFar,
     blueShotsFar: engine.blueShotsFar, blueHitsFar: engine.blueHitsFar)

when defined(wuffprobe):
  proc wuffGunShots*(engine: EvalEngine): seq[tuple[
      srcSlot, tgtSlot, srcTeam, tgtTeam, triggerTick, impactTick: int]] =
    ## Every GUN shot RELEASED this episode, as engine truth, with the tick that
    ## PULLED it. `ShotImpact` is emitted for every released gun shot — on a body
    ## (target >= 0) and on geometry/range (target < 0) — so this is the shot
    ## ledger, not just the hits.
    ##
    ## ⚠️ `source`/`target` in the event stream are stable JOIN SLOTS, not player
    ## indices; they are inverted through joinOrder here so the caller gets real
    ## slots it can index wuffTickFlags with.
    ##
    ## triggerTick comes from joining ShotImpact.actionId to the GunTrigger event
    ## emitted by startFireWindup at the pull. That is EXACT, not an assumption
    ## about the windup length — the join is what proves the 5-tick gap rather
    ## than presuming it, and the gap is printed as a histogram by the caller.
    var idxOf = newSeq[int](engine.sim.players.len)
    var teamOf = newSeq[int](engine.sim.players.len)
    for i in 0 ..< idxOf.len:
      idxOf[i] = -1
      teamOf[i] = -1
    for i in 0 ..< engine.sim.players.len:
      let jo = engine.sim.players[i].joinOrder
      if jo >= 0 and jo < idxOf.len:
        idxOf[jo] = i
        teamOf[jo] = ord(engine.sim.players[i].team)
    var trigTick = initTable[int64, int]()
    for e in engine.sim.events:
      if e.kind == GunTrigger and e.actionId != 0:
        trigTick[e.actionId] = e.tick
    for e in engine.sim.events:
      if e.kind != ShotImpact or e.weapon != "gun": continue
      if e.source < 0 or e.source >= idxOf.len: continue
      let
        src = idxOf[e.source]
        st = teamOf[e.source]
      if src < 0 or st < 0: continue
      var
        tgt = -1
        tt = -1
      if e.target >= 0 and e.target < idxOf.len and e.target != e.source:
        tgt = idxOf[e.target]
        tt = teamOf[e.target]
      result.add((srcSlot: src, tgtSlot: tgt, srcTeam: st, tgtTeam: tt,
                  triggerTick: trigTick.getOrDefault(e.actionId, -1),
                  impactTick: e.tick))

when defined(wleadprobe):
  proc wleadCounts*(engine: EvalEngine, team, bin: int):
      tuple[shots, hits, inWindow: int, perpSum: float] =
    (shots: engine.wlShots[team][bin], hits: engine.wlHits[team][bin],
     inWindow: engine.wlPerpIn[team][bin], perpSum: engine.wlPerpSum[team][bin])

when defined(shapeprobe):
  proc shapeCounts*(engine: EvalEngine, team: int): tuple[
      cross, deathOwn, deathEnemy, deepSum, deepMax, ticks: int] =
    ## Per-team SHAPE geometry for the episode just run. `deepSum/ticks` is the
    ## mean number of that team's bodies standing in the ENEMY half at any tick.
    let t = Team(team)
    (cross: engine.spCross[t], deathOwn: engine.spDeathOwn[t],
     deathEnemy: engine.spDeathEnemy[t], deepSum: engine.spDeepSum[t],
     deepMax: engine.spDeepMax[t], ticks: engine.spTicks)

proc result*(engine: EvalEngine): EpisodeResult =
  ## Snapshots the scoreboard from live sim fields (all authoritative — the
  ## same counters the hosted results JSON is built from).
  let sim = engine.sim
  result.ticks = sim.tickCount
  result.phaseOver = sim.phase == GameOver
  result.isDraw = sim.isDraw
  result.winnerTeam =
    if not result.phaseOver or sim.isDraw: -1
    else: ord(sim.winner)
  result.redShots = engine.redShots
  result.blueShots = engine.blueShots
  result.redHits = engine.redHits
  result.blueHits = engine.blueHits
  result.redGrabs = engine.redGrabs
  result.blueGrabs = engine.blueGrabs
  result.redDropProgSum = engine.dropProgSum[Red]
  result.blueDropProgSum = engine.dropProgSum[Blue]
  result.redDropCount = engine.dropCount[Red]
  result.blueDropCount = engine.dropCount[Blue]
  result.redSurvivalSum = engine.survivalSum[Red]
  result.blueSurvivalSum = engine.survivalSum[Blue]
  result.redSurvivalCount = engine.survivalCount[Red]
  result.blueSurvivalCount = engine.survivalCount[Blue]
  for i in 0 ..< sim.players.len:
    let p = sim.players[i]
    let team = ord(p.team)
    result.slots.add SlotStat(
      slot: i, team: team, kills: p.kills, deaths: p.deaths,
      captures: p.captures, lives: p.lives, alive: p.alive)
    let livesNow = p.lives + (if p.alive: 1 else: 0)
    if team == 0:
      result.redKills += p.kills
      result.redDeaths += p.deaths
      result.redLives += livesNow
      result.redCaptures += p.captures
    else:
      result.blueKills += p.kills
      result.blueDeaths += p.deaths
      result.blueLives += livesNow
      result.blueCaptures += p.captures

when defined(v59ab):
  # ⭐⭐⭐ -d:v59ab — THE BUNDLE A/B READOUT (v59 integration lane, 2026-08-21).
  # Everything the integration mandate asks for that the rig did not already
  # have, and nothing else. All of it is ENGINE TRUTH out of `sim.events` /
  # `sim.players`, never a bot's own perception (the 2026-08-05 field-metric
  # rule), and all of it is `when defined` so the shipped player and every other
  # arm compile byte-identical.
  #
  # ⚠️ DEATHS ARE SPLIT BY WHO FIRED. Pooled deaths have shipped a lever whose
  # premise was false before: woundedBank read "deaths -2.9%" pooled and was
  # enemy-inflicted +2.9% (WORSE) with own-team -17.4% — it was pulling bots out
  # of OUR spray, not out of the enemy's line. In this rig friendly fire is
  # ~8x the field rate, so a bundle that merely reduces self-inflicted deaths
  # would post a large, entirely fake survival win. byEnemy is the primary row;
  # byOwn and bySelf are reported beside it so the fake is visible, not hidden.
  #
  # ⚠️ Bucketed by RED/BLUE (the harness is 2-team by default) using the sim's
  # own `p.team`, and by the victim for deaths / the ACTOR for pickups.
  proc v59Split*(engine: EvalEngine): tuple[
      deathsByEnemy, deathsByOwn, deathsBySelf,
      medKits, shields, sprayCans,
      kills, captures, livesEnd: array[4, int],
      winner: int] =
    ## ⚠️ FOUR TEAMS, not two. `EpisodeResult`'s red/blue fields bucket by
    ## `ord(p.team)` with everything non-zero folded into BLUE, so on a 4-team
    ## board they compare a 4-seat arm against a 12-seat one — the exact error
    ## the *TEAM isolation knobs exist to prevent, one level out. Everything here
    ## is per RAW ENGINE TEAM INDEX 0..3.
    let sim = engine.sim
    result.winner =
      if sim.phase == GameOver and not sim.isDraw: ord(sim.winner) else: -1
    for p in sim.players:
      let t = ord(p.team)
      if t notin 0 .. 3: continue
      result.kills[t] += p.kills
      result.captures[t] += p.captures
      result.livesEnd[t] += p.lives + (if p.alive: 1 else: 0)
    var teamOfJoin = newSeq[int](sim.players.len)
    for i in 0 ..< teamOfJoin.len: teamOfJoin[i] = -1
    for p in sim.players:
      if p.joinOrder >= 0 and p.joinOrder < teamOfJoin.len:
        teamOfJoin[p.joinOrder] = ord(p.team)
    for e in sim.events:
      case e.kind
      of Death:
        # Death carries source = VICTIM, target = KILLER (Kill is the credited
        # mirror and omits a self-kill by one's own grenade — so Death, not
        # Kill, is the complete denominator for "who died and to whom").
        if e.source < 0 or e.source >= teamOfJoin.len: continue
        let vt = teamOfJoin[e.source]
        if vt notin 0 .. 3: continue
        if e.target < 0 or e.target >= teamOfJoin.len:
          inc result.deathsBySelf[vt]          # no killer: environment / self
        elif e.target == e.source:
          inc result.deathsBySelf[vt]
        elif teamOfJoin[e.target] == vt:
          inc result.deathsByOwn[vt]           # a MATE fired: friendly fire
        else:
          inc result.deathsByEnemy[vt]         # the real survival row
      of Pickup:
        if e.source < 0 or e.source >= teamOfJoin.len: continue
        let st = teamOfJoin[e.source]
        if st notin 0 .. 3: continue
        case e.item
        of "med_kit": inc result.medKits[st]
        of "shield": inc result.shields[st]
        of "spray_can": inc result.sprayCans[st]
        else: discard
      else: discard
