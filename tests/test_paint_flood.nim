## Paint-flood endgame: config lifecycle, the clock latch, kill-on-touch,
## the no-timeout-tie guarantee, hash gating, and the board/POV emission.
## See docs/plans/2026-08-07-paint-flood-design.md.

import
  helpers,
  std/[json, unittest],
  bitworld/spriteprotocol,
  ctf/[global, labels, sim]

proc floodGame(
  pxPerSec: int,
  startSec = PaintFloodStartSec,
  maxTicks = 1000
): SimServer =
  ## A started Red-vs-Blue game with the paint flood configured.
  var config = defaultGameConfig()
  config.maxTicks = maxTicks
  config.paintFloodPxPerSec = pxPerSec
  config.paintFloodStartSec = startSec
  result = initCtfForTest(config)
  discard result.addPlayer("red0")
  discard result.addPlayer("blue0")
  result.startGame()
  result.players[0].team = Red
  result.players[1].team = Blue

proc runClockTo(sim: var SimServer, remaining: int) =
  ## Advances the raw tick counter so `remaining` ticks stay on the clock.
  sim.tickCount = sim.gameStartTick + sim.config.maxTicks - remaining

proc stepIdle(sim: var SimServer, ticks: int) =
  ## Steps the sim with all-idle inputs.
  let noInput = sim.none()
  for _ in 1 .. ticks:
    sim.step(noInput, noInput)

suite "paint flood config":
  test "off by default, with the documented start threshold":
    let config = defaultGameConfig()
    check config.paintFloodPxPerSec == 0
    check config.paintFloodStartSec == PaintFloodStartSec

  test "JSON round-trip through update and the config echo":
    var config = defaultGameConfig()
    config.update("""{"paintFloodPxPerSec": 16, "paintFloodStartSec": 30}""")
    check config.paintFloodPxPerSec == 16
    check config.paintFloodStartSec == 30
    let echo = config.configJson()
    var reread = defaultGameConfig()
    reread.update(echo)
    check reread.paintFloodPxPerSec == 16
    check reread.paintFloodStartSec == 30

  test "a default game's config echo carries no flood keys":
    let node = parseJson(defaultGameConfig().configJson())
    check not node.hasKey("paintFloodPxPerSec")
    check not node.hasKey("paintFloodStartSec")

  test "a negative rate is rejected":
    var config = defaultGameConfig()
    expect CtfError:
      config.update("""{"paintFloodPxPerSec": -1}""")

  test "the flood requires a timed game":
    var config = defaultGameConfig()
    expect CtfError:
      config.update("""{"maxTicks": 0, "paintFloodPxPerSec": 5}""")

  test "a start threshold under one second is rejected":
    var config = defaultGameConfig()
    expect CtfError:
      config.update("""{"paintFloodPxPerSec": 5, "paintFloodStartSec": 0}""")

suite "paint flood sim":
  test "latches when the clock reaches the threshold, then advances":
    var sim = floodGame(pxPerSec = 24)
    let thresholdTicks = sim.config.paintFloodStartSec * TargetFps
    sim.runClockTo(thresholdTicks + 3)
    sim.stepIdle(1)
    check sim.paintFloodStartTick == -1
    check sim.paintFloodDepth() == 0
    sim.stepIdle(2)
    # remaining is now exactly the threshold: latched, depth still 0.
    check sim.paintFloodStartTick == sim.tickCount
    check sim.paintFloodDepth() == 0
    # At 24 px/s the flood advances one px per tick from the latch tick.
    sim.stepIdle(5)
    check sim.paintFloodDepth() == 5

  test "never latches while the mode is off":
    var sim = floodGame(pxPerSec = 24)
    sim.config.paintFloodPxPerSec = 0
    sim.runClockTo(10)
    sim.stepIdle(5)
    check sim.paintFloodStartTick == -1
    check sim.paintFloodDepth() == 0

  test "action-floor overtime never retreats a latched flood":
    var sim = floodGame(pxPerSec = 24)
    sim.runClockTo(sim.config.paintFloodStartSec * TargetFps)
    sim.stepIdle(10)
    check sim.paintFloodStartTick > 0
    let depthBefore = sim.paintFloodDepth()
    # A kill floors the clock back above the latch threshold...
    sim.killPlayer(1, 0)
    check sim.effectiveMaxTicks() - sim.gameTicksElapsed() ==
      ActionClockFloorTicks
    # ...and the flood keeps advancing anyway.
    sim.stepIdle(2)
    check sim.paintFloodDepth() == depthBefore + 2

  test "kills a cog the band touches, spares the center":
    var sim = floodGame(pxPerSec = 240)
    sim.placeStill(0, 40, MapHeight div 2)                # near the left edge.
    sim.placeStill(1, MapWidth div 2, MapHeight div 2 - 100)
    sim.runClockTo(sim.config.paintFloodStartSec * TargetFps)
    # At 10 px/tick the band reaches x - PlayerHalf = 34 within 5 ticks.
    sim.stepIdle(6)
    check not sim.players[0].alive
    check sim.players[0].deaths == 1
    check sim.players[0].lives == Lives - 1
    check sim.players[1].alive

  test "a timed flood game never ends in a timeout draw":
    var sim = floodGame(pxPerSec = 240, maxTicks = 600)
    var steps = 0
    while sim.phase == Playing and steps < 5000:
      sim.stepIdle(1)
      inc steps
    check sim.phase == GameOver
    check not sim.timeLimitReached

  test "the latch tick is hashed only once latched":
    var sim1 = floodGame(pxPerSec = 24)
    var sim2 = floodGame(pxPerSec = 24)
    check sim1.gameHash == sim2.gameHash
    sim1.paintFloodStartTick = sim1.tickCount
    check sim1.gameHash != sim2.gameHash

suite "paint flood emission":
  test "board stream ships the marker, frontier strips, and permanent rows":
    var sim = floodGame(pxPerSec = 240)
    sim.runClockTo(sim.config.paintFloodStartSec * TargetFps)
    sim.stepIdle(3)   # depth 20: two full 8px rows per side + frontier.
    check sim.paintFloodDepth() == 20
    var state = initGlobalViewerState()
    let messages = sim.buildGlobalMessages(state)
    check messages.hasObject(PaintFloodObjectBase)          # stated marker.
    for side in 0 ..< 4:
      check messages.hasObject(PaintFloodObjectBase + 1 + side)  # frontiers.
      check messages.hasObject(paintFloodRowObjectId(side, 0))
      check messages.hasObject(paintFloodRowObjectId(side, 1))
    # The permanent rows are once-only: the next frame re-places frontiers
    # but never the submerged rows.
    let next = sim.buildGlobalMessages(state)
    check next.hasObject(PaintFloodObjectBase + 1)
    for side in 0 ..< 4:
      check not next.hasObject(paintFloodRowObjectId(side, 0))

  test "the stated marker labels depth, rate, and start":
    var sim = floodGame(pxPerSec = 240)
    sim.runClockTo(sim.config.paintFloodStartSec * TargetFps)
    sim.stepIdle(3)
    var state = initGlobalViewerState()
    var found = false
    for message in sim.buildGlobalMessages(state):
      if message.kind == spkSprite and
          message.sprite.label == labelPaintFlood(
            20, 240, PaintFloodStartSec):
        found = true
    check found

  test "the player stream ships the flood too":
    var sim = floodGame(pxPerSec = 240)
    sim.runClockTo(sim.config.paintFloodStartSec * TargetFps)
    sim.stepIdle(3)
    let messages = sim.playerMessages(0)
    check messages.hasObject(PaintFloodObjectBase)
    check messages.hasObject(PaintFloodObjectBase + 1)
    check messages.hasObject(paintFloodRowObjectId(0, 0))

  test "a new game re-arms a viewer's flood rows":
    var sim = floodGame(pxPerSec = 240)
    sim.runClockTo(sim.config.paintFloodStartSec * TargetFps)
    sim.stepIdle(3)
    var state = initGlobalViewerState()
    discard sim.buildGlobalMessages(state)
    check state.floodRowsSent == [2, 2, 2, 2]
    # The match resets: the viewer's stale rows are deleted and the cursor
    # re-arms from zero.
    sim.resetToLobby()
    var sawDelete = false
    for message in sim.buildGlobalMessages(state):
      if message.kind == spkDeleteObject and
          message.objectId == paintFloodRowObjectId(0, 0):
        sawDelete = true
    check sawDelete
    check state.floodRowsSent == [0, 0, 0, 0]
