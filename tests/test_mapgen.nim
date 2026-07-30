import
  std/[os, unittest],
  ctf/sim, ctf/map_pool

const GameDir = currentSourcePath.parentDir.parentDir

proc initCtfForTest(config: GameConfig): SimServer =
  ## Initializes the CTF sim from the game directory (so data/ resolves).
  let previousDir = getCurrentDir()
  setCurrentDir(GameDir)
  try:
    result = initSimServer(config)
  finally:
    setCurrentDir(previousDir)

proc obstacleAt(obstacles: seq[ArenaShape], x, y: int): bool =
  ## Raw obstacle-union test (no border, no protected-floor carve): the
  ## carve uses div-derived centers that are 1px off-center on even-width
  ## maps, so only the obstacle union is EXACTLY symmetric.
  for shape in obstacles:
    if inShape(x, y, shape):
      return true
  false

suite "procedural terrain":
  test "same seed generates the same map":
    check generateCtfMap(4242) == generateCtfMap(4242)

  test "every pool seed validates on its first attempt":
    for seed in MapPoolSeeds:
      let gameMap = generateCtfMap(seed)
      check gameMap.genSeed == seed
      check validateGeneratedMap(gameMap) == ""

  test "obstacle union is exact under the map's symmetry":
    for seed in [MapPoolSeeds[0], MapPoolSeeds[1], 777]:
      let
        gameMap = generateCtfMap(seed)
        obstacles = buildArenaObstacles(gameMap)
        w = gameMap.width
        h = gameMap.height
      var x = ArenaBorder
      while x < w - ArenaBorder:
        var y = ArenaBorder
        while y < h - ArenaBorder:
          let (sx, sy) =
            case gameMap.symmetry
            of symMirror: (w - 1 - x, y)
            of symRot180: (w - 1 - x, h - 1 - y)
            of symRot90: (w - 1 - y, x)
          check obstacleAt(obstacles, x, y) ==
            obstacleAt(obstacles, sx, sy)
          y += 13
        x += 11

  test "4-team maps are exactly rot90-fair and deterministic":
    for layout in ["corners", "plus"]:
      let
        overrides = MapGenOverrides(windows: -1, layout: layout)
        gameMap = generateCtfMap(11, overrides, teams = 4)
        again = generateCtfMap(11, overrides, teams = 4)
        obstacles = buildArenaObstacles(gameMap)
        w = gameMap.width
      check gameMap == again
      check gameMap.symmetry == symRot90
      check w == gameMap.height
      # A quarter turn maps wall to wall everywhere: (x, y) -> (w-1-y, x).
      var x = ArenaBorder
      while x < w - ArenaBorder:
        var y = ArenaBorder
        while y < w - ArenaBorder:
          check obstacleAt(obstacles, x, y) ==
            obstacleAt(obstacles, w - 1 - y, x)
          y += 13
        x += 11

  test "map spec JSON round-trips the exact map":
    let gameMap = generateCtfMap(MapPoolSeeds[2])
    check mapFromSpecJson(mapSpecJson(gameMap)) == gameMap

  test "pool config pins the expanded spec and follows its gun range":
    var config = defaultGameConfig()
    config.update("""{"mapPath": "pool", "mapPoolIndex": 3}""")
    check config.mapSpec.len > 0
    let gameMap = resolveCtfMapMetadata(config)
    check gameMap.genSeed == MapPoolSeeds[3]
    check config.gunRange == gameMap.gunRange
    ## The replay config round-trip rebuilds the identical map.
    var replayConfig = defaultGameConfig()
    replayConfig.update(config.configJson())
    check resolveCtfMapMetadata(replayConfig) == gameMap

  test "generator honors parameter locks":
    var config = defaultGameConfig()
    config.update("""{
      "mapPath": "gen", "mapSeed": 99, "mapSize": "large",
      "mapSymmetry": "rot180", "mapCenterFeature": "ring"
    }""")
    let gameMap = resolveCtfMapMetadata(config)
    check gameMap.width == 1606
    check gameMap.symmetry == symRot180

  test "med kits spawn on the generated map's active pair":
    var config = defaultGameConfig()
    config.update("""{"mapPath": "pool", "mapPoolIndex": 0, "minPlayers": 1}""")
    let sim = initCtfForTest(config)
    check sim.gameMap.medKitCandidates.len == 4
    check sim.gameMap.medKitSpawns.len == 2
    for i in 0 ..< 2:
      let expected = sim.gameMap.medKitSpawns[i]
      check abs(sim.medKitSpawns[i].x - expected.x) <= 20
      check abs(sim.medKitSpawns[i].y - expected.y) <= 20
      check sim.medKitSpawns[i].present
