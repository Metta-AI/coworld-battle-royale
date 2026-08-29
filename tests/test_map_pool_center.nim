import
  std/[md5, os, sets, strformat, unittest],
  ctf/arena,
  ctf/map_pool,
  ctf/sim

const BrGen42SpecMd5 = "2be75b1b1e13917ddcb0c2a45e3230b7"
const SpinBand = 80 ## DiamondSpinBand, arena.nim:1241 (not exported)

proc poolDiamondCensus(gameMap: CtfMap): tuple[
    spinning, nearestAxis: int] =
  result.nearestAxis = high(int)
  for shape in buildArenaObstacles(gameMap):
    if shape.kind != shapeDiamond:
      continue
    result.nearestAxis = min(
      result.nearestAxis,
      abs(2 * shape.cx - (gameMap.width - 1)))
    if gameMap.isSpinningDiamond(shape):
      inc result.spinning

proc centerData(gameMap: CtfMap): tuple[
    wall, trench, puddle: string, kits: seq[MapPoint]] =
  let
    centerX = gameMap.width div 2
    centerY = gameMap.height div 2
    radius2 = BrCenterKeepOut * BrCenterKeepOut
    obstacles = buildArenaObstacles(gameMap)
    wallMask = rasterizeRestWallMask(
      gameMap,
      obstacles,
      proc (x, y: int): bool = mapProtectedFloorAt(gameMap, x, y),
    )
  for y in centerY - BrCenterKeepOut .. centerY + BrCenterKeepOut:
    for x in centerX - BrCenterKeepOut .. centerX + BrCenterKeepOut:
      let
        dx = x - centerX
        dy = y - centerY
      if dx * dx + dy * dy > radius2:
        continue
      let index = y * gameMap.width + x
      result.wall.add char(if wallMask[index]: 1 else: 0)
      var trench, puddle: bool
      for shape in gameMap.trenches:
        if inShape(x, y, shape):
          trench = true
          break
      for item in gameMap.puddles:
        if inPuddle(x, y, item):
          puddle = true
          break
      result.trench.add char(if trench: 1 else: 0)
      result.puddle.add char(if puddle: 1 else: 0)
  for point in gameMap.medKitCandidates:
    let
      dx = point.x - centerX
      dy = point.y - centerY
    if dx * dx + dy * dy <= radius2:
      result.kits.add point

proc wallHash(gameMap: CtfMap): string =
  let mask = rasterizeRestWallMask(
    gameMap,
    buildArenaObstacles(gameMap),
    proc (x, y: int): bool = mapProtectedFloorAt(gameMap, x, y),
  )
  var bits = newStringOfCap(mask.len div 8 + 1)
  var acc: uint8
  for i, wall in mask:
    acc = (acc shl 1) or (if wall: 1'u8 else: 0'u8)
    if i mod 8 == 7:
      bits.add char(acc)
      acc = 0
  if mask.len mod 8 != 0:
    bits.add char(acc shl (8 - mask.len mod 8))
  $toMD5(bits)

suite "battle-royale rotation pool":
  test "pool entries stay outside the spinning-diamond band":
    ## The margin is currently 162 vs 160. This is an OBSERVED property of
    ## the generated file, not a construction guarantee. A pool regeneration
    ## that crosses it fails here and names the entry; if diamonds in BR are
    ## ever wanted, delete this test deliberately.
    let overrides = brCanonicalOverrides()
    var minimumDoubledAxis = high(int)
    for index in 0 ..< BrMapPoolSeeds.len:
      let
        seed = BrMapPoolSeeds[index]
        gameMap = brPoolCtfMap(index, overrides)
        census = poolDiamondCensus(gameMap)
      doAssert census.spinning == 0, &"entry index={index} seed={seed} " &
        &"has {census.spinning} spinning diamonds"
      minimumDoubledAxis = min(minimumDoubledAxis, census.nearestAxis)
    check minimumDoubledAxis < high(int)
    doAssert minimumDoubledAxis >= 2 * SpinBand,
      &"minimum doubled axis distance={minimumDoubledAxis} is below " &
      "the spinning threshold"
    echo &"pool minimum doubled axis distance={minimumDoubledAxis} " &
      &"(observed 162 vs threshold < {2 * SpinBand})"

  test "all entries share the canonical center and remain valid":
    let reference = generateMapAttempt(
      BrCanonicalCenterSeed, brCanonicalOverrides())
    let expected = centerData(reference)
    check FfaLootRadius + 80 <= BrCenterKeepOut
    for index in 0 ..< BrMapPoolSeeds.len:
      let gameMap = brPoolCtfMap(index, brCanonicalOverrides())
      check gameMap.center == MapPoint(
        x: gameMap.width div 2, y: gameMap.height div 2)
      check centerData(gameMap) == expected
      check gameMap.medKitSpawns.len == 2
      check gameMap.medKitSpawns == reference.medKitSpawns
      check gameMap.medKitCandidates == reference.medKitCandidates
      for spawn in gameMap.medKitSpawns:
        check spawn in gameMap.medKitCandidates
      check validateGeneratedMap(gameMap) == ""

  test "all entries remain distinct outside the canonical disc":
    var hashes = initHashSet[string]()
    for index in 0 ..< BrMapPoolSeeds.len:
      let hash = wallHash(brPoolCtfMap(index, brCanonicalOverrides()))
      check hash notin hashes
      hashes.incl hash
    check hashes.len == BrMapPoolSeeds.len

  test "default map resolutions and the pinned BR map stay unchanged":
    var defaultConfig = defaultGameConfig()
    defaultConfig.update(readFile(
      currentSourcePath.parentDir.parentDir / "config.json"))
    check mapSpecJson(loadCtfMapMetadata(defaultConfig)) ==
      mapSpecJson(loadCtfMapMetadata("arena"))

    var brConfig = defaultGameConfig()
    brConfig.update(readFile(
      currentSourcePath.parentDir.parentDir / "config.br.json"))
    let canonical = generateMapAttempt(
      BrCanonicalCenterSeed, brCanonicalOverrides())
    check $toMD5(mapSpecJson(canonical)) == BrGen42SpecMd5
    check mapSpecJson(loadCtfMapMetadata(brConfig)) ==
      mapSpecJson(canonical)

  test "BR pool resolution ignores divergent generator knobs":
    var config = defaultGameConfig()
    config.mapPath = BrPoolMapName
    config.mapPoolIndex = 17
    config.mapGen.puddles = 8
    check mapSpecJson(loadCtfMapMetadata(config)) ==
      mapSpecJson(brPoolCtfMap(config.mapPoolIndex, brCanonicalOverrides()))
