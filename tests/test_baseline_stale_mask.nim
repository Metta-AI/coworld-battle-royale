import
  helpers,
  pixie,
  std/[math, os, strformat, strutils, tables, unittest],
  bitworld/pixelfonts,
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

proc boxesFromMessages(
    messages: openArray[SpritePacketMessage]
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
    result.add(DiamondBox(
      x0: message.objectDef.x,
      y0: message.objectDef.y,
      x1: message.objectDef.x + definition.width,
      y1: message.objectDef.y + definition.height))

proc streamedDiamondBoxes(
    messages: openArray[SpritePacketMessage],
    scale: int
): seq[DiamondBox] =
  for box in boxesFromMessages(messages):
    result.add(DiamondBox(
      x0: box.x0 div scale,
      y0: box.y0 div scale,
      x1: box.x1 div scale,
      y1: box.y1 div scale))

proc streamedPlayerDiamondBoxes(
    sim: var SimServer,
    playerIndex: int
): seq[DiamondBox] =
  var state, nextState: PlayerViewerState
  let previousDir = getCurrentDir()
  setCurrentDir(GameDir)
  try:
    let packet = sim.buildSpriteProtocolPlayerUpdates(
      playerIndex, state, nextState, spritesOff = true)
    result = boxesFromMessages(packet.parseSpritePacket())
  finally:
    setCurrentDir(previousDir)

proc sameBoxes(a, b: seq[DiamondBox]): bool =
  if a.len != b.len:
    return false
  for box in a:
    if box notin b:
      return false
  true

proc fovCandidateConfirmed(
    sim: var SimServer,
    a, b: VisionPoint,
    shadowCache: var Table[int, seq[bool]]
): bool =
  if sim.players.len == 0:
    return false
  sim.players[0].placeAtCenter(int(a.x), int(a.y))
  let
    aimBrads = bradsOfVector(int(b.x - a.x), int(b.y - a.y))
    (originCx, originCy) = fovCellAt(
      sim.players[0].x + CollisionW div 2,
      sim.players[0].y + CollisionH div 2)
    originKey = fovCellIndex(originCx, originCy)
  sim.players[0].aimBrads = aimBrads
  if originKey notin shadowCache:
    var shadow = newSeq[bool](FovCellCount)
    sim.computeFovShadowcast(originCx, originCy, shadow)
    shadowCache[originKey] = shadow
  let
    (targetCx, targetCy) = fovCellAt(int(b.x), int(b.y))
    targetIndex = fovCellIndex(targetCx, targetCy)
  if not shadowCache[originKey][targetIndex]:
    return false
  let
    (ox, oy) = fovCellCenter(originCx, originCy)
    (px, py) = fovCellCenter(targetCx, targetCy)
    (ax, ay) = aimVector(aimBrads)
    vx = px - ox
    vy = py - oy
    d2 = float(vx * vx + vy * vy)
  if d2 <= float(sim.config.visionBubble * sim.config.visionBubble):
    return true
  if d2 > float(sim.visionRange() * sim.visionRange()):
    return false
  let dot = float(vx) * ax + float(vy) * ay
  dot >= cos(float(sim.config.visionConeDeg) * PI / 180.0) * sqrt(d2)

proc serverFovConfirmed(
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
    staleMask: openArray[bool],
    w, h: int,
    boxes: openArray[DiamondBox],
    a, b: VisionPoint,
    markStale: bool,
    title: string
) =
  let
    ax = int(a.x)
    ay = int(a.y)
    bx = int(b.x)
    by = int(b.y)
    cropW = max(180, abs(bx - ax) + 60)
    cropH = max(140, abs(by - ay) + 60)
    cropX = (ax + bx) div 2
    cropY = (ay + by) div 2
    originX = clamp(cropX - cropW div 2, 0, w - cropW)
    originY = clamp(cropY - cropH div 2, 0, h - cropH)
  var image = newImage(cropW, cropH)
  for y in 0 ..< cropH:
    for x in 0 ..< cropW:
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
        if x >= originX and x < originX + cropW and
            y >= originY and y < originY + cropH:
          image[x - originX, y - originY] = rgba(60, 150, 240, 255)
    for y in box.y0 ..< box.y1:
      for x in [box.x0, box.x1 - 1]:
        if x >= originX and x < originX + cropW and
            y >= originY and y < originY + cropH:
          image[x - originX, y - originY] = rgba(60, 150, 240, 255)
  let steps = max(abs(bx - ax), abs(by - ay))
  if steps > 0:
    for s in 0 .. steps:
      let
        x = ax + (bx - ax) * s div steps
        y = ay + (by - ay) * s div steps
      if x >= originX and x < originX + cropW and
          y >= originY and y < originY + cropH:
        image[x - originX, y - originY] = rgba(240, 45, 45, 255)
        if markStale and not staleMask[y * w + x]:
          image[x - originX, y - originY] = rgba(255, 190, 40, 255)
  let font = readTiny5Font()
  image.drawText(font, title, 5, 5, rgba(255, 255, 255, 255))
  image.resize(cropW * 3, cropH * 3).writeFile(path)

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
      confirmedMismatchPairs = 0
      boxRayBlocked = 0
      selectedTick = -1
      selectedA, selectedB: VisionPoint
      selectedDistance = -1.0
      selectedLiveMask: seq[bool]
      selectedBoxes: seq[DiamondBox]
      shadowCache = initTable[int, seq[bool]]()
    for _ in 1 .. spinTicks:
      sim.step(sim.none(), sim.none())
      shadowCache.clear()
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
          if not maskRayClear(snapshot, width, height, boxes, a, b):
            inc boxRayBlocked
          let confirmed = fovCandidateConfirmed(sim, a, b, shadowCache)
          if not confirmed:
            continue
          inc confirmedMismatchPairs
          if not rayHitsDiamond(boxes, a, b) or
              not maskRayClear(snapshot, width, height, boxes, a, b):
            continue
          let laneLength = sqrt(
            (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
          if sim.tickCount > DiamondSpinTicksPerFrame and
              laneLength > selectedDistance:
            selectedTick = sim.tickCount
            selectedA = a
            selectedB = b
            selectedDistance = laneLength
            selectedLiveMask = newSeq[bool](sim.walkMask.len)
            for k in 0 ..< sim.walkMask.len:
              selectedLiveMask[k] = sim.walkMask[k]
            selectedBoxes = boxes

    check mismatches > 0
    check confirmedMismatchPairs > 0
    let blockedRate = float(boxRayBlocked) / float(max(1, mismatches))
    echo &"stale-mask mismatches={mismatches} " &
      &"fov-confirmed-mismatches={confirmedMismatchPairs} " &
      &"box-ray-blocked={boxRayBlocked} " &
      &"wrongly-blocked-rate={blockedRate:.4f}"
    check blockedRate <= 0.05

    var foundStaticWall = false
    let finalBoxes = expectedDiamondBoxes(sim.tickCount)
    for y in 20 ..< height - 20:
      if foundStaticWall:
        break
      for x in 20 ..< width - 20:
        if sim.isWall(x, y) and not sim.windowMask[y * width + x]:
          let
            a = VisionPoint(x: float(x - 12), y: float(y))
            b = VisionPoint(x: float(x + 12), y: float(y))
          if maskAt(sim.walkMask, width, height, int(a.x), int(a.y)) and
              maskAt(sim.walkMask, width, height, int(b.x), int(b.y)) and
              not pointInAnyDiamond(finalBoxes, int(a.x), int(a.y)) and
              not pointInAnyDiamond(finalBoxes, int(b.x), int(b.y)) and
              not rayHitsDiamond(finalBoxes, a, b) and
              not maskRayClear(
                sim.walkMask, width, height, finalBoxes, a, b):
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
    check sameBoxes(streamedPlayerDiamondBoxes(sim, 0), finalBoxes)

    check selectedTick > DiamondSpinTicksPerFrame
    sim.applyDiamondGeometry(selectedTick)
    let
      liveLos = sim.lineOfSightClear(
        int(selectedA.x), int(selectedA.y), int(selectedB.x), int(selectedB.y))
      fovConfirmed = serverFovConfirmed(sim, selectedA, selectedB)
      snapshotRefused = not plainRay(
        snapshot, width, height, selectedA, selectedB)
      boxRayAllowed = maskRayClear(
        snapshot, width, height, selectedBoxes, selectedA, selectedB)
    check liveLos
    check fovConfirmed
    check snapshotRefused
    check boxRayAllowed
    echo "[OK] INSIDE diamond box: live LOS clear, server FOV confirms, " &
      "plain snapshot ray refuses, box-aware stale ray allows"

    var
      foundGlass = false
      glassA, glassB: VisionPoint
    block findGlass:
      for y in 0 ..< height:
        for x in 0 ..< width:
          if not sim.windowMask[y * width + x]:
            continue
          for horizontal in [true, false]:
            let
              a = if horizontal:
                VisionPoint(x: float(x - 12), y: float(y))
              else:
                VisionPoint(x: float(x), y: float(y - 12))
              b = if horizontal:
                VisionPoint(x: float(x + 12), y: float(y))
              else:
                VisionPoint(x: float(x), y: float(y + 12))
              ax = int(a.x)
              ay = int(a.y)
              bx = int(b.x)
              by = int(b.y)
              steps = max(abs(bx - ax), abs(by - ay))
            if not maskAt(sim.walkMask, width, height, ax, ay) or
                not maskAt(sim.walkMask, width, height, bx, by) or
                rayHitsDiamond(finalBoxes, a, b):
              continue
            var glassOnly = true
            var hasGlass = false
            for s in 0 .. steps:
              let
                px = ax + (bx - ax) * s div max(1, steps)
                py = ay + (by - ay) * s div max(1, steps)
                index = py * width + px
              if not sim.walkMask[index]:
                if not sim.windowMask[index]:
                  glassOnly = false
                  break
                hasGlass = true
            if not glassOnly or not hasGlass or
                maskRayClear(
                  sim.walkMask, width, height, finalBoxes, a, b):
              continue
            if serverFovConfirmed(sim, a, b):
              glassA = a
              glassB = b
              foundGlass = true
              break findGlass
    check foundGlass
    if foundGlass:
      let
        glassFovConfirmed = serverFovConfirmed(sim, glassA, glassB)
        glassRayBlocked = not maskRayClear(
          sim.walkMask, width, height, finalBoxes, glassA, glassB)
      check glassFovConfirmed
      check glassRayBlocked
      echo "[OK] OUTSIDE diamond box: glass ray is FOV-confirmed and " &
        "box-aware live ray declines it"

    when defined(writeStandoffOverlay):
      drawOverlay(
        "/tmp/stale-mask-standoff.png", snapshot, snapshot, width, height,
        selectedBoxes, selectedA, selectedB, true,
        "stale connect-time snapshot")
      drawOverlay(
        "/tmp/live-mask-standoff.png", selectedLiveMask, snapshot, width,
        height, selectedBoxes, selectedA, selectedB, false,
        &"live mask, tick {selectedTick}")
      echo &"standoff tick={selectedTick} endpoints=({int(selectedA.x)}," &
        &"{int(selectedA.y)})-({int(selectedB.x)},{int(selectedB.y)}) " &
        &"lane-length={selectedDistance:.1f} sim FOV confirmed the sighting=" &
        (if fovConfirmed: "1" else: "0")
      echo "overlay stale=/tmp/stale-mask-standoff.png " &
        "live=/tmp/live-mask-standoff.png"
