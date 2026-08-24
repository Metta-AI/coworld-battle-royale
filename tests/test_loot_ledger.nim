import
  helpers,
  std/[json, os, tables, unittest],
  ctf/replays,
  "../tools/extract_events",
  "../tools/ledger"

const
  FfaFixture = GameDir / "tests" / "fixtures" / "ffa-scorebug.bitreplay"

let LedgerPath =
  getTempDir() / ("loot-ledger-" & $getCurrentProcessId() & ".jsonl")

type
  FixtureData = tuple[extraction: ExtractResult, ledger: Ledger]

var
  fixtureCache: FixtureData
  fixtureLoaded = false

proc fixtureLedger(): FixtureData =
  if not fixtureLoaded:
    fixtureCache.extraction = extractEvents(
      loadReplay(FfaFixture), captureFrames = true)
    var summary = newJObject()
    summary["finished"] = %fixtureCache.extraction.finished
    summary["draw"] = %fixtureCache.extraction.isDraw
    summary["winner"] = %fixtureCache.extraction.winner
    summary["slot_address"] = %fixtureCache.extraction.slotAddress
    summary["slot_team"] = %fixtureCache.extraction.slotTeam
    summary["slot_shots_fired"] = %fixtureCache.extraction.slotShotsFired
    summary["slot_shots_hit"] = %fixtureCache.extraction.slotShotsHit
    writeFile(LedgerPath, fixtureCache.extraction.events.eventsJsonl(
      fixtureCache.extraction.ticks, summary))
    fixtureCache.ledger = loadLedger(LedgerPath)
    fixtureLoaded = true
  fixtureCache

suite "FFA loot ledger instrumentation":
  test "frames v2 round-trips weapon tiers":
    let extraction = fixtureLedger().extraction
    check extraction.frames[0 ..< 8] == "CTFFRM02"
    check extraction.frames.len == FramesHeaderBytes +
      extraction.frameCount *
      frameRecordBytes(extraction.frameSlots, extraction.frameTeams)
    for index in 0 ..< extraction.frameCount:
      for seat in 0 ..< extraction.frameSlots:
        check extraction.frameSeat(index, seat).weaponTier in 0 .. 3

  test "derived tiers, frames, and shot tokens agree":
    let fixture = fixtureLedger()
    let
      extraction = fixture.extraction
      ledger = fixture.ledger
    let timeline = ledger.tierTimeline()
    var shotCount = 0
    for row in ledger.rows:
      if row.kind != "shot" or not TierByToken.hasKey(row.weapon):
        continue
      inc shotCount
      let tokenTier = TierByToken[row.weapon]
      check extraction.frameTick(row.tick - 1) == row.tick
      check tierAt(timeline, row.source, row.tick) == tokenTier
      check extraction.frameSeat(row.tick - 1, row.source).weaponTier == tokenTier
    check shotCount > 0
    echo "oracle triple equality covered ", shotCount, " shot rows"

  test "every seat starts unarmed and tier transitions are monotone":
    let ledger = fixtureLedger().ledger
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
    let ledger = fixtureLedger().ledger
    let
      radiusPx = 96.0
      outcomes = ledger.lootOutcomes(ledger.lastTick(), radiusPx)
    check outcomes.len == ledger.matchedKills().len
    for outcome in outcomes:
      if not outcome.tierGain:
        continue
      check outcome.gainOrigin == "spawn"
      check outcome.gainTick > outcome.tick
      check outcome.gainDistPx >= 0.0
      check outcome.gainAtCorpse ==
        (outcome.gainDistPx <= radiusPx)
      var explained = false
      for row in ledger.rows:
        if row.kind == "item_pickup" and row.source == outcome.killer and
            row.tick == outcome.gainTick and TierByToken.hasKey(row.item) and
            TierByToken[row.item] > outcome.killerTierBefore:
          explained = true
          break
      check explained
