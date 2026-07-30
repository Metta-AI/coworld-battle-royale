import
  std/[os, unittest],
  ctf/sim

const GameDir = currentSourcePath.parentDir.parentDir

proc initCtfForTest(): SimServer =
  ## Initializes the CTF sim from the game directory (so data/ resolves).
  let previousDir = getCurrentDir()
  setCurrentDir(GameDir)
  try:
    result = initSimServer(defaultGameConfig())
  finally:
    setCurrentDir(previousDir)

proc twoTeamGame(): SimServer =
  result = initCtfForTest()
  discard result.addPlayer("red0")
  discard result.addPlayer("blue0")
  result.startGame()
  result.players[0].team = Red
  result.players[1].team = Blue

proc tickOfFrame(cx, frame: int): int =
  ## The first tick on which the diamond centered at map-x `cx` shows `frame`.
  for tick in 0 ..< DiamondSpinFrames * DiamondSpinTicksPerFrame:
    if diamondSpinFrame(cx, tick) == frame:
      return tick
  -1

proc cornerPixel(spot: tuple[cx, cy, radius: int]):
    tuple[x, y: int] =
  ## A pixel on the diamond's resting east vertex line that the 45° frame
  ## vacates: at rest it is stone, half a quarter-turn later it is open floor.
  (spot.cx + spot.radius - 2, spot.cy)

suite "spinning center diamonds are real geometry":
  test "every diamond turns and its silhouette IS the collision mask":
    var sim = twoTeamGame()
    check AnimatedDiamonds.len > 0
    for frame in 0 ..< DiamondSpinFrames:
      # Drive the geometry straight to a tick that shows this frame on the
      # left half; the right half mirrors, which the per-pixel compare covers.
      let tick = tickOfFrame(AnimatedDiamonds[0].cx, frame)
      check tick >= 0
      sim.applyDiamondGeometry(tick)
      for spot in AnimatedDiamonds:
        let spotFrame = diamondSpinFrame(spot.cx, tick)
        for y in spot.cy - spot.radius - 1 .. spot.cy + spot.radius + 1:
          for x in spot.cx - spot.radius - 1 .. spot.cx + spot.radius + 1:
            if animatedDiamondCovers(spot, spotFrame, x, y):
              # Drawn stone must block. (The converse does not hold: a
              # neighbouring wall may share the box.)
              check sim.isWall(x, y)
              check not sim.canOccupy(x, y)

  test "a vertex that rotates away stops blocking movement and bullets":
    var sim = twoTeamGame()
    let
      spot = AnimatedDiamonds[0]
      (px, py) = cornerPixel(spot)
      restTick = tickOfFrame(spot.cx, 0)
      turnedTick = tickOfFrame(spot.cx, DiamondSpinFrames div 2)
    sim.applyDiamondGeometry(restTick)
    check sim.isWall(px, py)
    check not sim.lineOfSightClear(
      spot.cx - spot.radius - 6, py, spot.cx + spot.radius + 6, py)
    # Half a quarter-turn later the vertex has swung off this row: the pixel
    # the player sees as floor really is floor, and the shot goes through.
    sim.applyDiamondGeometry(turnedTick)
    check not sim.isWall(px, py)

  test "the fog occlusion grid follows the spin":
    var sim = twoTeamGame()
    let spot = AnimatedDiamonds[0]
    proc cellsAround(sim: SimServer, spot: tuple[cx, cy, radius: int]):
        seq[bool] =
      let
        (gx0, gy0) = fovCellAt(spot.cx - spot.radius, spot.cy - spot.radius)
        (gx1, gy1) = fovCellAt(spot.cx + spot.radius, spot.cy + spot.radius)
      for gy in gy0 .. gy1:
        for gx in gx0 .. gx1:
          result.add sim.fovBlocked[fovCellIndex(gx, gy)]
    sim.applyDiamondGeometry(tickOfFrame(spot.cx, 0))
    let atRest = sim.cellsAround(spot)
    sim.applyDiamondGeometry(tickOfFrame(spot.cx, DiamondSpinFrames div 2))
    let turned = sim.cellsAround(spot)
    # Vision is recomputed as the stone moves, not frozen at bake time: the
    # 45° frame occludes a different set of cells than the resting one.
    check atRest != turned

  test "the sweep pushes an engulfed player onto free floor":
    var sim = twoTeamGame()
    let spot = AnimatedDiamonds[0]
    sim.tickCount = tickOfFrame(spot.cx, DiamondSpinFrames div 2)
    sim.updateAnimatedDiamonds()
    # Stand exactly where the resting vertex will be — open floor right now.
    let (px, py) = cornerPixel(spot)
    check sim.canOccupy(px, py)
    sim.players[0].x = px
    sim.players[0].y = py
    sim.tickCount = tickOfFrame(spot.cx, 0)
    sim.updateAnimatedDiamonds()
    check sim.isWall(px, py)
    check sim.canOccupy(sim.players[0].x, sim.players[0].y)

  test "geometry is a pure function of the tick":
    var
      simA = twoTeamGame()
      simB = twoTeamGame()
    for tick in [0, 7, 33, 250]:
      simA.applyDiamondGeometry(tick)
      simB.applyDiamondGeometry(tick)
      for spot in AnimatedDiamonds:
        for y in spot.cy - spot.radius - 1 .. spot.cy + spot.radius + 1:
          for x in spot.cx - spot.radius - 1 .. spot.cx + spot.radius + 1:
            check simA.isWall(x, y) == simB.isWall(x, y)
    check simA.gameHash == simB.gameHash

  test "the two halves spin in mirrored directions":
    let
      left = AnimatedDiamonds[0]
      right = block:
        var pick = AnimatedDiamonds[0]
        for spot in AnimatedDiamonds:
          if spot.cx > MapWidth div 2:
            pick = spot
            break
        pick
    check right.cx > MapWidth div 2
    let tick = DiamondSpinTicksPerFrame       # frame 1 on the left half.
    check diamondSpinFrame(left.cx, tick) == 1
    check diamondSpinFrame(right.cx, tick) == DiamondSpinFrames - 1
