## The ffa scorebug's honesty test: at sampled ticks of a recorded ffa replay,
## every number the chrome frame carries (`ffaScore`) must equal the score
## derived INDEPENDENTLY from the tier-2 event ledger — kills, deaths, damage
## and the assist window, replayed by the rules in docs/DESIGN.md section 9.
##
## Two walks, on purpose: the ledger comes from `tools/extract_events`, the
## frames from a second `buildStateJson` walk. Nothing is shared but the
## replay, so a scoring bug that lived in the state builder cannot hide by
## being asked to check itself.

import
  helpers,
  std/[algorithm, json, os, tables, unittest],
  ctf/[broadcast, global, replays, sim],
  "../tools/extract_events"

const
  # Recorded against the CURRENT rules with the ffa demo runner:
  #   tools/run_ffa_demo.sh 12 60 I
  # then copied out of demo-artifacts/. Re-record on every GameVersion bump.
  #
  # The recipe is not just "an ffa match": this fixture has to CONTAIN the
  # awards it is here to check, and the scarce one is a SHARED assist. The
  # seed moved to 60 because the rules changed and drop-on-death is armed.
  # It ends on a wipe after 10 credited kills whose assist pools run 0..4
  # damagers, so the +4 pot is split 2, 3 and 4 ways as well as taken whole —
  # an integer-division bug in the split cannot pass here. A seed whose kills
  # are all solo (seed 42 at 8 players was one) passes a weaker test silently,
  # so re-scan the assist pools after re-recording, not just the kill count.
  FfaFixture = GameDir / "tests" / "fixtures" / "ffa-scorebug.bitreplay"
  AssistWindow = 240             ## config.assistWindowTicks, the shipped value.

type
  SeatScore = object
    ## One seat's ledger-derived score at a tick, split the same way the
    ## chrome frame splits it.
    survival, kills, killPts, assists, podium, damage, total: int
    combat: int             ## killPts + assists, the frame's `cb`.
    deathTick: int          ## -1 while alive.

proc phaseStartTick(events: seq[SimEvent], phase: string): int =
  ## The tick the ledger says the game entered `phase`, or -1.
  result = -1
  for event in events:
    if event.kind == PhaseChange and event.weapon == phase:
      return event.tick

proc creditedDamagers(
  events: seq[SimEvent], victim, killer, tick, window: int
): seq[int] =
  ## The victim's OTHER damagers inside the assist window: everyone who dealt
  ## them credited damage within `window` ticks of the kill, minus the killer
  ## (paid the kill) and the victim (self-damage credits nobody). Ring and
  ## puddle damage carry no attacker, so they credit nobody either.
  result = @[]
  for event in events:
    if event.kind != Damage or event.tick > tick or event.tick < tick - window:
      continue
    if event.target != victim or event.source < 0:
      continue
    if event.source == victim or event.source == killer:
      continue
    if event.source notin result:
      result.add event.source
  result.sort()

proc ledgerScores(
  events: seq[SimEvent], config: GameConfig,
  seats, upToTick, gameStart, playingEnd: int
): seq[SeatScore] =
  ## Replays the ledger up to `upToTick` and pays the scoring rules by hand:
  ## +1/sec alive, +10 to the credited killer, the +4 assist pot split among
  ## the victim's other damagers in the window. Podium is added by the caller
  ## at game over — before that it is not earned, so it is not shown.
  result = newSeq[SeatScore](seats)
  for seat in 0 ..< seats:
    result[seat].deathTick = -1
  for event in events:
    if event.tick > upToTick:
      break
    case event.kind
    of Kill:
      # The raw credited-kill COUNTER only: `kills` is a stat here, not money.
      # It is deliberately counted off Kill (which is what the sim's own
      # counter follows, because only real deaths emit these events, so the
      # placement keys derived here match the sim's.
      if event.source >= 0 and event.source < seats:
        inc result[event.source].kills
    of Death:
      # Kill MONEY and the assist pot are both paid on the DEATH (the sim pays
      # them inside killPlayer), not on the Kill event. Paying off Death keeps
      # this test measuring the scoring rules rather than event ordering.
      if event.source >= 0 and event.source < seats:
        result[event.source].deathTick = event.tick
      if event.target < 0 or event.target == event.source:
        continue
      if event.target < seats:
        result[event.target].killPts += config.killPoints
      let assisters = creditedDamagers(
        events, event.source, event.target, event.tick,
        max(0, config.assistWindowTicks)
      )
      if assisters.len > 0:
        # Integer split, and a pot that cannot pay a whole point pays nothing —
        # the sim's own rule.
        let share = config.assistPoints div assisters.len
        if share > 0:
          for slot in assisters:
            if slot >= 0 and slot < seats:
              result[slot].assists += share
    of Damage:
      if event.source >= 0 and event.source < seats and
          event.source != event.target:
        result[event.source].damage += event.amount
    else:
      discard
  # Survival pay lands on each whole-second boundary of the game clock, to
  # everyone still alive AFTER that tick's deaths resolve — so a seat that dies
  # exactly on a boundary tick is not paid for it.
  # Survival stops being paid the moment the game is over, even though the game
  # clock keeps running through the end-card hold.
  let
    payUntil = if playingEnd >= 0: min(upToTick, playingEnd) else: upToTick
    seconds = max(0, payUntil - gameStart) div TargetFps
  for second in 1 .. seconds:
    let boundary = gameStart + second * TargetFps
    for seat in 0 ..< seats:
      let died = result[seat].deathTick
      if died < 0 or died > boundary:
        result[seat].survival += config.survivalPointsPerSec
  for seat in 0 ..< seats:
    result[seat].combat = result[seat].killPts + result[seat].assists
    result[seat].total = result[seat].survival + result[seat].combat

proc ledgerPlacement(scores: seq[SeatScore]): seq[int] =
  ## Seats in placement order by the documented total order: alive first, then
  ## later death tick, then kills, then damage dealt, then lower seat.
  result = @[]
  for seat in 0 ..< scores.len:
    result.add seat
  result.sort(proc (a, b: int): int =
    let
      aAlive = scores[a].deathTick < 0
      bAlive = scores[b].deathTick < 0
    if aAlive != bAlive:
      return if aAlive: -1 else: 1
    if scores[a].deathTick != scores[b].deathTick:
      return if scores[a].deathTick > scores[b].deathTick: -1 else: 1
    if scores[a].kills != scores[b].kills:
      return if scores[a].kills > scores[b].kills: -1 else: 1
    if scores[a].damage != scores[b].damage:
      return if scores[a].damage > scores[b].damage: -1 else: 1
    cmp(a, b)
  )

proc frameSeats(state: JsonNode): Table[int, JsonNode] =
  ## The frame's `ffaScore` seats, keyed by stable join slot.
  result = initTable[int, JsonNode]()
  for seat in state["ffaScore"]["seats"]:
    result[seat["s"].getInt] = seat

suite "ffa scorebug honesty (state channel vs the event ledger)":
  let
    data = loadReplay(FfaFixture)
    ledger = extractEvents(data)          # raises on any hash mismatch
    gameStart = phaseStartTick(ledger.events, "playing")
    playingEnd = phaseStartTick(ledger.events, "gameover")

  test "the fixture carries the awards this test exists to check":
    check ledger.finished
    check gameStart >= 0
    var
      kills = 0
      sharedSplits = 0
    for event in ledger.events:
      if event.kind != Death or event.target < 0:
        continue
      inc kills
      if creditedDamagers(
        ledger.events, event.source, event.target, event.tick, AssistWindow
      ).len > 1:
        inc sharedSplits
    check kills >= 3
    # At least one kill whose +4 pot is SPLIT between several assisters: the
    # case a per-assister flat payout would get wrong.
    check sharedSplits >= 1

  test "sampled frames report the ledger's scores, components and ranks":
    # Sample ticks that matter rather than round numbers: the first shared
    # assist split, the last kill, and the final frame (the only place podium
    # is earned).
    var
      firstSplitTick = -1
      lastKillTick = -1
    for event in ledger.events:
      if event.kind != Death or event.target < 0:
        continue
      lastKillTick = event.tick
      if firstSplitTick < 0 and creditedDamagers(
        ledger.events, event.source, event.target, event.tick, AssistWindow
      ).len > 1:
        firstSplitTick = event.tick
    check firstSplitTick > 0
    check lastKillTick > 0
    var samples: seq[int] = @[]
    for tick in [firstSplitTick, lastKillTick, ledger.ticks]:
      if tick notin samples:
        samples.add tick
    check samples.len == 3

    let previousDir = getCurrentDir()
    setCurrentDir(GameDir)
    try:
      var config = defaultGameConfig()
      config.update(data.configJson)
      var
        sim = initSimServer(config)
        replay = initReplayPlayer(data)
      sim.gameEventLoggingEnabled = false
      replay.looping = false
      replay.mismatchQuit = true
      var checked = 0
      while replay.playing:
        replay.stepReplay(sim)
        if sim.tickCount notin samples:
          continue
        let
          state = parseJson(sim.buildStateJson(
            newJArray(), false, 1, replay.replayMaxTick(), false, true, -1, -1
          ))
          seats = frameSeats(state)
          overNow = state["ph"].getStr == "gameover"
        check state["ffa"].getBool
        check seats.len == sim.players.len
        var expected = ledgerScores(
          ledger.events, sim.config, seats.len, sim.tickCount, gameStart,
          playingEnd
        )
        let places = ledgerPlacement(expected)
        for place, slot in places:
          if overNow and place < sim.config.podiumPoints.len:
            expected[slot].podium = sim.config.podiumPoints[place]
            expected[slot].total += expected[slot].podium
        for place, slot in places:
          let
            want = expected[slot]
            got = seats[slot]
          # The whole contract in one block: the total the viewer reads, the
          # component split behind it, the placement facts, and the rank.
          check got["sc"].getInt == want.total
          check got["sv"].getInt == want.survival
          check got["cb"].getInt == want.combat
          check got["pd"].getInt == want.podium
          check got["k"].getInt == want.kills
          check got["dmg"].getInt == want.damage
          check got["alive"].getBool == (want.deathTick < 0)
          check got["rank"].getInt == place + 1
          # Components always add up to the displayed total, so the client can
          # show the split without ever doing score arithmetic.
          check got["sv"].getInt + got["cb"].getInt + got["pd"].getInt ==
            got["sc"].getInt
        # Margins are the server's own signed gap to the rank-1 seat.
        let leader = seats[places[0]]["sc"].getInt
        for slot, seat in seats:
          check seat["gap"].getInt == leader - seat["sc"].getInt
        # Podium is earned at the end and nowhere else.
        if not overNow:
          for slot, seat in seats:
            check seat["pd"].getInt == 0
        else:
          check seats[places[0]]["pd"].getInt == sim.config.podiumPoints[0]
        inc checked
      check checked == samples.len
    finally:
      setCurrentDir(previousDir)

  test "the frame carries the zone countdown the server cue reads":
    let previousDir = getCurrentDir()
    setCurrentDir(GameDir)
    try:
      var config = defaultGameConfig()
      config.update(data.configJson)
      var
        sim = initSimServer(config)
        replay = initReplayPlayer(data)
      sim.gameEventLoggingEnabled = false
      replay.looping = false
      replay.mismatchQuit = true
      var
        sawCountdown = false
        sawFloor = false
      while replay.playing:
        replay.stepReplay(sim)
        if sim.tickCount mod 60 != 0:
          continue
        let state = parseJson(sim.buildStateJson(
          newJArray(), false, 1, replay.replayMaxTick(), false, true, -1, -1
        ))
        let seconds = state["ring"]["toFloorSec"].getInt
        # The replay chip and the server's own cue read ONE helper, so the two
        # zone read-outs cannot drift.
        let cue = sim.ffaZoneCueText()
        if seconds > 0:
          sawCountdown = true
          check cue == "ZONE " & $(seconds div 60) & ":" &
            (if seconds mod 60 < 10: "0" else: "") & $(seconds mod 60)
        elif seconds == 0:
          sawFloor = true
          check cue == "ZONE FLOOR"
      check sawCountdown
      check sawFloor
    finally:
      setCurrentDir(previousDir)
