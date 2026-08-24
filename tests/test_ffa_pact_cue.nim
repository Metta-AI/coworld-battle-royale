## Inferred pact beats are presentation-only: they are derived from the
## directional damage sink, expire with its bounded window, and never enter
## the CTF event vocabulary.

import
  helpers,
  std/[json, sequtils, unittest],
  ctf/[broadcast, sim]

proc pactGame(seats: int): SimServer =
  result = initCtfForTest(defaultFfaConfig(seats))
  for i in 0 ..< seats:
    discard result.addPlayer("pact" & $i)
  result.startGame()
  result.collectEvents = true

proc damage(tick, source, target: int): SimEvent =
  SimEvent(
    tick: tick,
    kind: Damage,
    source: source,
    target: target,
    amount: 1,
    hp: 1
  )

proc stepDamage(
  sim: var SimServer,
  tracker: var BroadcastTracker,
  tick: int,
  rows: openArray[(int, int)]
): JsonNode =
  sim.tickCount = tick
  for row in rows:
    sim.events.add(damage(tick, row[0], row[1]))
  result = newJArray()
  sim.stepEvents(tracker, result)

proc pactKinds(events: JsonNode): seq[string] =
  for event in events:
    let kind = event["k"].getStr
    if kind in ["pact", "pactfocus", "pactbreak", "pactend"]:
      result.add(kind)

proc eventsOf(events: JsonNode, kind: string): seq[JsonNode] =
  for event in events:
    if event["k"].getStr == kind:
      result.add(event)

suite "ffa inferred pact cue":
  test "a pair forms on a common victim":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    let events = stepDamage(sim, tracker, 1, [(0, 2), (1, 2)])
    let pacts = events.eventsOf("pact")
    check pacts.len == 1
    check pacts[0]["a"].getInt == 0
    check pacts[0]["b"].getInt == 1
    check pacts[0]["v"].getInt == 2
    check pacts[0]["w"].getInt == DefaultPactWindowTicks

  test "reciprocal damage in the window prevents a pact":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    let events = stepDamage(
      sim, tracker, 1, [(0, 1), (1, 0), (0, 2), (1, 2)]
    )
    check events.pactKinds.len == 0

  test "mutual damage breaks the pair on the landing step":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    discard stepDamage(sim, tracker, 1, [(0, 2), (1, 2)])
    let events = stepDamage(sim, tracker, 2, [(0, 1)])
    check events.eventsOf("pactbreak").len == 1
    check events.eventsOf("pactend").len == 0

  test "the pair ends when its damage window lapses":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    tracker.setPactWindowTicks(2)
    discard stepDamage(sim, tracker, 0, [])
    discard stepDamage(sim, tracker, 1, [(0, 2), (1, 2)])
    let events = stepDamage(sim, tracker, 4, [])
    check events.eventsOf("pactend").len == 1
    check events.eventsOf("pactbreak").len == 0

  test "the pair ends when a member dies":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    discard stepDamage(sim, tracker, 1, [(0, 2), (1, 2)])
    sim.players[1].alive = false
    let events = stepDamage(sim, tracker, 2, [])
    check events.eventsOf("pactend").len == 1

  test "resync clears pact state without emitting transitions":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    discard stepDamage(sim, tracker, 1, [(0, 2), (1, 2)])
    tracker.resync(sim)
    let quiet = stepDamage(sim, tracker, 2, [])
    check quiet.pactKinds.len == 0
    let fresh = stepDamage(sim, tracker, 3, [(0, 2), (1, 2)])
    check fresh.eventsOf("pact").len == 1

  test "a second victim creates one focus edge, not a stream":
    var
      sim = pactGame(4)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    discard stepDamage(sim, tracker, 1, [(0, 2), (1, 2)])
    let focus = stepDamage(sim, tracker, 2, [(0, 3), (1, 3)])
    check focus.eventsOf("pactfocus").len == 1
    check focus.eventsOf("pactfocus")[0]["v"].getInt == 3
    check stepDamage(sim, tracker, 3, []).eventsOf("pactfocus").len == 0

  test "self damage and a victim who is an attacker are excluded":
    var
      sim = pactGame(3)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    let events = stepDamage(sim, tracker, 1, [(0, 1), (1, 1)])
    check events.pactKinds.len == 0

  test "CTF emits none of the pact event kinds":
    var
      sim = initCtfForTest()
      tracker = initBroadcastTracker()
    discard sim.addPlayer("ctf-pact0")
    discard sim.addPlayer("ctf-pact1")
    sim.startGame()
    sim.collectEvents = true
    discard stepDamage(sim, tracker, 0, [])
    let events = stepDamage(sim, tracker, 1, [(0, 1), (1, 0)])
    check events.pactKinds.len == 0

  test "pacts are emitted in ascending pair order":
    var
      sim = pactGame(5)
      tracker = initBroadcastTracker()
    discard stepDamage(sim, tracker, 0, [])
    let events = stepDamage(
      sim, tracker, 1, [(3, 4), (1, 4), (2, 4), (0, 4)]
    )
    let pacts = events.eventsOf("pact")
    check pacts.mapIt((it["a"].getInt, it["b"].getInt)) == @[
      (0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)
    ]
