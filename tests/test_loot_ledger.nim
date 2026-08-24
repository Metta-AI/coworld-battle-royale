import
  helpers,
  std/[os, tables, unittest],
  ctf/replays,
  "../tools/extract_events",
  "../tools/ledger"

const
  FfaFixture = GameDir / "tests" / "fixtures" / "ffa-scorebug.bitreplay"
  LedgerPath = "/tmp/test_loot_ledger.jsonl"

proc fixtureLedger(frames: var string): tuple[
    extraction: ExtractResult, ledger: Ledger] =
  let data = loadReplay(FfaFixture)
  let output = extractEventsJsonl(data, frames, captureFrames = true)
  writeFile(LedgerPath, output)
  result.extraction = extractEvents(data, captureFrames = true)
  result.ledger = loadLedger(LedgerPath)

suite "FFA loot ledger instrumentation":
  test "frames v2 round-trips weapon tiers":
    var frames: string
    let (extraction, _) = fixtureLedger(frames)
    check frames == extraction.frames
    check frames[0 ..< 8] == "CTFFRM02"
    check frames.len == FramesHeaderBytes +
      extraction.frameCount *
      frameRecordBytes(extraction.frameSlots, extraction.frameTeams)
    for index in 0 ..< extraction.frameCount:
      for seat in 0 ..< extraction.frameSlots:
        check extraction.frameSeat(index, seat).weaponTier in 0 .. 3

  test "derived tiers, frames, and shot tokens agree":
    var frames: string
    let (extraction, ledger) = fixtureLedger(frames)
    let timeline = ledger.tierTimeline()
    var shotCount = 0
    for row in ledger.rows:
      if row.kind != "shot" or not TierByToken.hasKey(row.weapon):
        continue
      inc shotCount
      let tokenTier = TierByToken[row.weapon]
      check tierAt(timeline, row.source, row.tick) == tokenTier
      check extraction.frameSeat(row.tick - 1, row.source).weaponTier == tokenTier
    check shotCount > 0
    echo "oracle triple equality covered ", shotCount, " shot rows"

  test "every seat starts unarmed and tier transitions are monotone":
    var frames: string
    let (_, ledger) = fixtureLedger(frames)
    let timeline = ledger.tierTimeline()
    check ledger.isFfaLedger()
    for seat in 0 ..< ledger.seatCount():
      check timeline.hasKey(seat)
      if not timeline.hasKey(seat):
        continue
      let transitions = timeline[seat]
      check transitions.len > 0
      if transitions.len == 0:
        continue
      check transitions[0].tick == 0
      check transitions[0].tier == 0
      var previousTick = transitions[0].tick
      var previousTier = transitions[0].tier
      if transitions.len > 1:
        for transition in transitions[1 .. ^1]:
          check transition.tick >= previousTick
          check transition.tier >= previousTier
          previousTick = transition.tick
          previousTier = transition.tier

  test "every tier gain has a matching pickup explanation":
    var frames: string
    let (_, ledger) = fixtureLedger(frames)
    let outcomes = ledger.lootOutcomes(ledger.lastTick(), 96.0)
    check outcomes.len == ledger.matchedKills().len
    for outcome in outcomes:
      if not outcome.tierGain:
        continue
      check outcome.gainOrigin == "spawn"
      check outcome.gainTick > outcome.tick
      check outcome.gainDistPx >= 0.0
      var explained = false
      for row in ledger.rows:
        if row.kind == "item_pickup" and row.source == outcome.killer and
            row.tick == outcome.gainTick and TierByToken.hasKey(row.item) and
            TierByToken[row.item] > outcome.killerTierBefore:
          explained = true
          break
      check explained
