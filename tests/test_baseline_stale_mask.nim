import
  helpers,
  pixie,
  std/[math, strformat, strutils, tables, unittest],
  bitworld/spriteprotocol,
  ctf/[arena, global, sim, sim_types],
  baseline/vision

proc plainRay(
    mask: openArray[bool],
    w, h: int,
    a, b: VisionPoint
): bool =
  maskRayClear(mask, w, h, [], a, b)

proc maskAt(mask: openArray[bool], w, h, x, y: int): bool =
  x >= 0 and y >= 0 and x < w and y < h and mask[y * w + x]

proc rayHitsDiamond(
    boxes: openArray[DiamondBox],
    a, b: VisionPoint
): bool =
  let
    ax = int(a.x)
    ay = int(a.y)
    bx = int(b.x)
    by = int(b.y)
    steps = max(abs(bx - ax), abs(by - ay))
  for s in 0 .. steps:
    let
      x = ax + (bx - ax) * s div max(1, steps)
      y = ay + (by - ay) * s div max(1, steps)
    if pointInAnyDiamond(boxes, x, y):
      return true
  false

proc expectedDiamondBoxes(tick: int): seq[DiamondBox] =
  discard tick
  for spot in AnimatedDiamonds:
    let size = rotatingDiamondSize(spot.radius)
    let x0 = spot.cx - size div 2
    let y0 = spot.cy - size div 2
    result.add(DiamondBox(x0: x0, y0: y0, x1: x0 + size, y1: y0 + size))

proc streamedDiamondBoxes(
    messages: openArray[SpritePacketMessage],
    scale: int
): seq[DiamondBox] =
  var definitions = initTable[int, tuple[label: string, width, height: int]]()
  for message in messages:
    if message.kind == spkSprite:
      definitions[message.sprite.id] = (
        message.sprite.label, message.sprite.width, message.sprite.height)
  for message in messages:
    if message.kind != spkObject or
        message.objectDef.spriteId notin definitions:
      continue
    let definition = definitions[message.objectDef.spriteId]
    if not definition.label.startsWith("diamond"):
      continue
    let
      x0 = message.objectDef.x div scale
      y0 = message.objectDef.y div scale
      width = definition.width div scale
      height = definition.height div scale
    result.add(DiamondBox(
      x0: x0, y0: y0, x1: x0 + width, y1: y0 + height))

proc sameBoxes(a, b: seq[DiamondBox]): bool =
  if a.len != b.len:
    return false
  for box in a:
    if box notin b:
      return false
  true

proc fovConfirmed(
    sim: var SimServer,
    a, b: VisionPoint
): bool =
  if sim.players.len == 0:
    return false
  sim.players[0].placeAtCenter(int(a.x), int(a.y))
  sim.players[0].aimBrads = bradsOfVector(
    int(b.x - a.x), int(b.y - a.y))
  discard sim.refreshPlayerFov(0)
  sim.fovVisibleAt(0, int(b.x), int(b.y))

proc drawOverlay(
    path: string,
    mask: openArray[bool],
    w, h: int,
    boxes: openArray[DiamondBox],
    a, b: VisionPoint,
    cropX, cropY: int
) =
  const half = 120
  let
    size = half * 2 + 1
    originX = cropX - half
    originY = cropY - half
  var image = newImage(size, size)
  for y in 0 ..< size:
    for x in 0 ..< size:
      let
        mx = originX + x
        my = originY + y
      image[x, y] =
        if mx < 0 or my < 0 or mx >= w or my >= h:
          rgba(70, 20, 70, 255)
        elif mask[my * w + mx]:
          rgba(32, 38, 44, 255)
        else:
          rgba(205, 185, 160, 255)
  for box in boxes:
    for x in box.x0 ..< box.x1:
      for y in [box.y0, box.y1 - 1]:
        if x >= originX and x < originX + size and
            y >= originY and y < originY + size:
          image[x - originX, y - originY] = rgba(60, 150, 240, 255)
    for y in box.y0 ..< box.y1:
      for x in [box.x0, box.x1 - 1]:
        if x >= originX and x < originX + size and
            y >= originY and y < originY + size:
          image[x - originX, y - originY] = rgba(60, 150, 240, 255)
  let
    ax = int(a.x)
    ay = int(a.y)
    bx = int(b.x)
    by = int(b.y)
    steps = max(abs(bx - ax), abs(by - ay))
  if steps > 0:
    for s in 0 .. steps:
      let
        x = ax + (bx - ax) * s div steps
        y = ay + (by - ay) * s div steps
      if x >= originX and x < originX + size and
          y >= originY and y < originY + size:
        image[x - originX, y - originY] = rgba(240, 45, 45, 255)
  image.writeFile(path)

suite "baseline live geometry trust":
  test "confirmed sightings survive the stale diamond snapshot":
    var sim = initCtfForTest(defaultFfaConfig(6))
    for i in 0 ..< 6:
      discard sim.addPlayer("stale" & $i)
    sim.startGame()
    let
      width = MapWidth
      height = MapHeight
      snapshot = sim.walkMask
      spinTicks = DiamondSpinFrames * DiamondSpinTicksPerFrame
    check AnimatedDiamonds.len > 0
    check sim.medKitSpawns.len > 0

    var
      mismatches = 0
      boxRayBlocked = 0
      selectedTick = -1
      selectedA, selectedB: VisionPoint
      selectedLiveMask: seq[bool]
      selectedBoxes: seq[DiamondBox]
    for _ in 1 .. spinTicks:
      sim.step(sim.none(), sim.none())
      let boxes = expectedDiamondBoxes(sim.tickCount)
      var points: seq[VisionPoint]
      for kit in sim.medKitSpawns:
        for y in countup(kit.y - 70, kit.y + 70, 8):
          for x in countup(kit.x - 70, kit.x + 70, 8):
            if (x - kit.x) * (x - kit.x) +
                (y - kit.y) * (y - kit.y) > 70 * 70:
              continue
            let p = VisionPoint(x: float(x), y: float(y))
            if maskAt(sim.walkMask, width, height, x, y):
              points.add(p)
      for i in 0 ..< points.len:
        for j in i + 1 ..< points.len:
          let
            a = points[i]
            b = points[j]
            oldClear = plainRay(snapshot, width, height, a, b)
            liveClear = plainRay(sim.walkMask, width, height, a, b)
          if oldClear or not liveClear:
            continue
          inc mismatches
          check shotAllowed(true, snapshot, width, height, boxes, a, b)
          if not shotAllowed(false, snapshot, width, height, boxes, a, b):
            inc boxRayBlocked
          if selectedTick < 0:
            selectedTick = sim.tickCount
            selectedA = a
            selectedB = b
            selectedLiveMask = sim.walkMask
            selectedBoxes = boxes

    check mismatches > 0
    let blockedRate = float(boxRayBlocked) / float(max(1, mismatches))
    echo &"stale-mask mismatches={mismatches} box-ray-blocked={boxRayBlocked} " &
      &"wrongly-blocked-rate={blockedRate:.4f}"
    check blockedRate <= 0.05

    var foundStaticWall = false
    let finalBoxes = expectedDiamondBoxes(sim.tickCount)
    for y in 20 ..< height - 20:
      if foundStaticWall:
        break
      for x in 20 ..< width - 20:
        if sim.isWall(x, y):
          let
            a = VisionPoint(x: float(x - 12), y: float(y))
            b = VisionPoint(x: float(x + 12), y: float(y))
          if maskAt(sim.walkMask, width, height, int(a.x), int(a.y)) and
              maskAt(sim.walkMask, width, height, int(b.x), int(b.y)) and
              not pointInAnyDiamond(finalBoxes, int(a.x), int(a.y)) and
              not pointInAnyDiamond(finalBoxes, int(b.x), int(b.y)) and
              not rayHitsDiamond(finalBoxes, a, b) and
              not shotAllowed(false, sim.walkMask, width, height,
                finalBoxes, a, b):
            foundStaticWall = true
            break
      if foundStaticWall:
        break
    check foundStaticWall

    var state = initGlobalViewerState()
    let messages = sim.buildGlobalMessages(state)
    check sameBoxes(
      streamedDiamondBoxes(messages, boardRenderScaleFor(MapWidth, MapHeight)),
      finalBoxes)

    when defined(writeStandoffOverlay):
      check selectedTick >= 0
      sim.applyDiamondGeometry(selectedTick)
      check sim.lineOfSightClear(
        int(selectedA.x), int(selectedA.y), int(selectedB.x), int(selectedB.y))
      check sim.fovConfirmed(selectedA, selectedB)
      drawOverlay(
        "/tmp/stale-mask-standoff.png", snapshot, width, height, selectedBoxes,
        selectedA, selectedB, int((selectedA.x + selectedB.x) / 2),
        int((selectedA.y + selectedB.y) / 2))
      drawOverlay(
        "/tmp/live-mask-standoff.png", selectedLiveMask, width, height,
        selectedBoxes,
        selectedA, selectedB, int((selectedA.x + selectedB.x) / 2),
        int((selectedA.y + selectedB.y) / 2))
      echo &"standoff tick={selectedTick} endpoints=({int(selectedA.x)}," &
        &"{int(selectedA.y)})-({int(selectedB.x)},{int(selectedB.y)}) " &
        "baseline old ray refused=1 sim FOV confirmed the sighting=1"
      echo "overlay stale=/tmp/stale-mask-standoff.png " &
        "live=/tmp/live-mask-standoff.png"
