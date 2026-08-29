import
  helpers,
  std/[json, os, strutils, tables, unittest],
  ctf/replays,
  "../tools/extract_events",
  "../tools/ledger"

const
  FfaFixture = GameDir / "tests" / "fixtures" / "ffa-scorebug.bitreplay"

let LedgerPath =
  getTempDir() / ("loot-ledger-" & $getCurrentProcessId() & ".jsonl")

type
  FixtureData = tuple[
    jsonl: string,
    framesOut: string,
    extraction: ExtractResult,
    ledger: Ledger]

var
  fixtureCache: FixtureData
  fixtureLoaded = false

proc fixtureLedger(): FixtureData =
  if not fixtureLoaded:
    let data = loadReplay(FfaFixture)
    fixtureCache.jsonl = extractEventsJsonl(
      data, fixtureCache.framesOut, captureFrames = true)
    fixtureCache.extraction = extractEvents(data, captureFrames = true)
    writeFile(LedgerPath, fixtureCache.jsonl)
    fixtureCache.ledger = loadLedger(LedgerPath)
    fixtureLoaded = true
  fixtureCache

proc rosterlessLedger(fixture: FixtureData): Ledger =
  let path =
    getTempDir() / ("loot-ledger-rosterless-" & $getCurrentProcessId() & ".jsonl")
  var linesOut: seq[string]
  for line in fixture.jsonl.splitLines:
    if line.strip.len == 0:
      continue
    var node = parseJson(line)
    if node.hasKey("type") and node["type"].getStr == "summary":
      for key in ["slot_address", "slot_team", "slot_shots_fired",
                  "slot_shots_hit"]:
        node.delete(key)
    linesOut.add($node)
  writeFile(path, linesOut.join("\n") & "\n")
  loadLedger(path)

suite "FFA loot ledger instrumentation":
  test "frames v2 round-trips weapon tiers":
    let fixture = fixtureLedger()
    let extraction = fixture.extraction
    check fixture.framesOut == extraction.frames
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

  test "rosterless summaries preserve tier timelines":
    let fixture = fixtureLedger()
    let
      expected = fixture.ledger.tierTimeline()
      rosterless = rosterlessLedger(fixture)
      actual = rosterless.tierTimeline()
    check rosterless.summary.present
    check rosterless.summary.slotAddress.len == 0
    check rosterless.seatCount() == fixture.ledger.seatCount()
    check actual.len == expected.len
    for seat in 0 ..< fixture.ledger.seatCount():
      check actual.hasKey(seat)
      if not actual.hasKey(seat):
        continue
      let
        expectedTransitions = expected[seat]
        actualTransitions = actual[seat]
      check actualTransitions.len == expectedTransitions.len
      if actualTransitions.len != expectedTransitions.len:
        continue
      for index in 0 ..< expectedTransitions.len:
        check actualTransitions[index].tick == expectedTransitions[index].tick
        check actualTransitions[index].tier == expectedTransitions[index].tier
        check actualTransitions[index].origin == expectedTransitions[index].origin

  test "every tier gain has a matching pickup explanation":
    let ledger = fixtureLedger().ledger
    let
      radiusPx = 96.0
      outcomes = ledger.lootOutcomes(ledger.lastTick(), radiusPx)
    check outcomes.len == ledger.matchedKills().len
    for outcome in outcomes:
      if not outcome.tierGain:
        continue
      check outcome.gainOrigin in ["spawn", "corpse"]
      check outcome.gainTick > outcome.tick
      check outcome.gainDistPx >= 0.0
      var explained = false
      for row in ledger.rows:
        if row.kind == "item_pickup" and row.source == outcome.killer and
            row.tick == outcome.gainTick and
            row.item.pickupTier() > outcome.killerTierBefore:
          check row.item.pickupOrigin() == outcome.gainOrigin
          explained = true
          break
      check explained

  test "a death-site drop reads as a corpse gain, not a spawn gain":
    ## The dormant `dropWeaponOnDeath` rule emits "dropped heavy gun" rather
    ## than a new event kind, so a derivation keyed to the bare tokens would
    ## keep reporting "no return on a kill" after the knob is activated —
    ## the one conclusion this tooling exists to test.
    let path =
      getTempDir() / ("loot-ledger-drop-" & $getCurrentProcessId() & ".jsonl")
    writeFile(path, """
{"tick":10,"kind":"item_pickup","source":0,"target":-1,"item":"heavy gun","x":100.0,"y":100.0}
{"tick":20,"kind":"item_pickup","source":1,"target":-1,"item":"low gun","x":900.0,"y":900.0}
{"tick":30,"kind":"kill","source":1,"target":0,"weapon":"low gun","x":110.0,"y":100.0}
{"tick":30,"kind":"death","source":0,"target":1,"weapon":"low gun","x":110.0,"y":100.0}
{"tick":40,"kind":"item_pickup","source":1,"target":-1,"item":"dropped heavy gun","x":120.0,"y":100.0}
""".strip() & "\n")
    let
      ledger = loadLedger(path)
      timeline = ledger.tierTimeline()
    check ledger.isFfaLedger()
    check timeline[1][^1].tier == 3
    check timeline[1][^1].origin == "corpse"
    check timeline[1][1].origin == "spawn"
    check ledger.droppedTierPickups(1).len == 1
    check ledger.fixedTierPickups(1).len == 1
    check ledger.tierPickups(1).len == 2

    let outcomes = ledger.lootOutcomes(600, 96.0)
    check outcomes.len == 1
    check outcomes[0].killerTierBefore == 1
    check outcomes[0].killerTierAfter == 3
    check outcomes[0].gainOrigin == "corpse"
    check outcomes[0].gainAtCorpse
    removeFile(path)
