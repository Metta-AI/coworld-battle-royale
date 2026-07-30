import
  std/[os, unittest],
  bitworld/spriteprotocol,
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

proc twoTeamGame(extraPlayers = 0): SimServer =
  ## A started game with one Red player (0), one Blue player (1), and
  ## `extraPlayers` more Blue bodies (2..).
  result = initCtfForTest(defaultGameConfig())
  discard result.addPlayer("red0")
  discard result.addPlayer("blue0")
  for i in 0 ..< extraPlayers:
    discard result.addPlayer("blue" & $(i + 1))
  result.startGame()
  result.players[0].team = Red
  for i in 1 ..< result.players.len:
    result.players[i].team = Blue

proc armToFire(game: var SimServer, shooter: int) =
  ## Clears the gates so the shooter's next tryFire releases this tick.
  game.players[shooter].windupBrads = -1
  game.players[shooter].fireCooldown = 0

proc placeAt(game: var SimServer, playerIndex, px, py: int) =
  ## Puts one player's CENTER exactly on map pixel (px, py), at rest.
  game.players[playerIndex].x = px - CollisionW div 2
  game.players[playerIndex].y = py - CollisionH div 2
  game.players[playerIndex].velX = 0
  game.players[playerIndex].velY = 0

suite "trenches":
  test "the arena has one walkable trench square at the field center":
    let sim = twoTeamGame()
    check ArenaTrenches.len == 1
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
      trench = ArenaTrenches[0]
    check trench.w == TrenchSize
    check trench.h == TrenchSize
    check trenchIndexAt(cx, cy) == 0
    check trenchIndexAt(cx - TrenchSize, cy) == -1
    # Every pixel of the trench is walkable floor (it sits inside the open
    # center ring, never overlapping a wall).
    for y in trench.y ..< trench.y + trench.h:
      for x in trench.x ..< trench.x + trench.w:
        check sim.canOccupy(x, y)

  test "an occupant's speed cap is one fifth of the open-field cap":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
      cap = sim.config.maxSpeed div TrenchSpeedDivisor
    sim.placeAt(0, cx - 24, cy)
    check sim.playerTrench(0) == 0
    # Hold right long enough to reach the cap; the capped speed never
    # exceeds one fifth of the open-field max.
    for _ in 0 ..< 12:
      sim.applyInput(0, InputState(right: true))
      check sim.players[0].velX <= cap
    check sim.playerTrench(0) == 0
    check sim.players[0].velX == cap

  test "momentum carried into a trench is clamped on entry":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
      cap = sim.config.maxSpeed div TrenchSpeedDivisor
    sim.placeAt(0, cx, cy)
    sim.players[0].velX = sim.config.maxSpeed
    sim.applyInput(0, InputState())
    check sim.players[0].velX <= cap
    # The same full-speed glide OUTSIDE a trench keeps most of its speed
    # (friction only) — the clamp is the trench's, not the field's.
    sim.placeAt(1, cx - 200, cy)
    sim.players[1].velX = sim.config.maxSpeed
    sim.applyInput(1, InputState())
    check sim.players[1].velX > cap

  test "firing from inside a trench takes three times the cooldown":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
    sim.placeAt(0, cx, cy)
    sim.players[0].aimBrads = 0
    sim.armToFire(0)
    sim.tryFire(0)
    check sim.players[0].fireCooldown ==
      sim.config.fireCooldownTicks * TrenchFireSlowdown
    # Outside, the same shot costs the base cooldown.
    sim.placeAt(0, cx - 200, cy)
    sim.armToFire(0)
    sim.tryFire(0)
    check sim.players[0].fireCooldown == sim.config.fireCooldownTicks

  test "trench and shield fire slowdowns compose by max, not product":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
    sim.placeAt(0, cx, cy)
    sim.players[0].hasShield = true
    sim.players[0].shieldHp = ShieldLayerHp
    sim.players[0].aimBrads = 0
    sim.armToFire(0)
    sim.tryFire(0)
    check sim.players[0].fireCooldown ==
      sim.config.fireCooldownTicks *
      max(ShieldFireSlowdown, TrenchFireSlowdown)

  test "about seventy percent of incoming shots fly over an occupant":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
      shots = 200
    # Shooter in the open ring outside the trench, aiming due west at the
    # occupant standing on the trench center. Ducked shots deal no damage
    # and count as misses; the rest hit for 1 as usual.
    sim.placeAt(1, cx, cy)
    check sim.playerTrench(1) == 0
    sim.placeAt(0, cx + 50, cy)
    check sim.playerTrench(0) == -1
    sim.players[0].aimBrads = 128
    var damaged = 0
    for _ in 0 ..< shots:
      sim.players[1].hp = sim.config.hitPoints
      sim.armToFire(0)
      sim.tryFire(0)
      if sim.players[1].hp < sim.config.hitPoints:
        inc damaged
    check sim.players[0].shotsFired == shots
    # Every shot that dealt damage is exactly a counted hit, and the hit
    # rate sits in a generous window around the expected 30%.
    check sim.players[0].shotsHit == damaged
    check damaged >= shots * 15 div 100
    check damaged <= shots * 45 div 100

  test "a ducked shot's tracer flies straight over the trench":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
      trench = ArenaTrenches[0]
    sim.placeAt(1, cx, cy)
    sim.placeAt(0, cx + 50, cy)
    sim.players[0].aimBrads = 128
    # Fire until one shot is ducked (the seeded RNG makes this quick): its
    # tracer carries on PAST the whole trench toward the far wall, because
    # the pit never stops a bullet.
    var sawFlyOver = false
    for _ in 0 ..< 50:
      sim.players[1].hp = sim.config.hitPoints
      sim.armToFire(0)
      sim.tryFire(0)
      let fx = sim.recentShots[^1]
      if sim.players[1].hp == sim.config.hitPoints:
        sawFlyOver = true
        check not fx.hit
        check fx.x1 < trench.x
        break
    check sawFlyOver

  test "a ducked shot carries on and can hit a body behind the trench":
    var sim = twoTeamGame(extraPlayers = 1)
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
      shots = 200
    # Occupant on the trench center, a second body directly behind it on
    # the same ray (both inside the open ring). Every shot lands on ONE of
    # them: ~30% on the ducking occupant, the rest flying over onto the
    # exposed body behind.
    sim.placeAt(1, cx, cy)
    sim.placeAt(2, cx - 50, cy)
    check sim.playerTrench(1) == 0
    check sim.playerTrench(2) == -1
    sim.placeAt(0, cx + 50, cy)
    sim.players[0].aimBrads = 128
    var
      frontHits = 0
      behindHits = 0
    for _ in 0 ..< shots:
      sim.players[1].hp = sim.config.hitPoints
      sim.players[2].hp = sim.config.hitPoints
      sim.armToFire(0)
      sim.tryFire(0)
      if sim.players[1].hp < sim.config.hitPoints:
        inc frontHits
      if sim.players[2].hp < sim.config.hitPoints:
        inc behindHits
    check frontHits + behindHits == shots
    check frontHits >= shots * 15 div 100
    check frontHits <= shots * 45 div 100
    check behindHits >= shots * 55 div 100

  test "shots between two occupants of the same trench are never ducked":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
    sim.placeAt(0, cx - 20, cy)
    sim.placeAt(1, cx + 20, cy)
    check sim.playerTrench(0) == 0
    check sim.playerTrench(1) == 0
    sim.players[0].aimBrads = 0
    for _ in 0 ..< 20:
      sim.players[1].hp = sim.config.hitPoints
      sim.armToFire(0)
      sim.tryFire(0)
      check sim.players[1].hp == sim.config.hitPoints - 1
    check sim.players[0].shotsHit == 20

  test "shots fired from inside at a target outside are never ducked":
    var sim = twoTeamGame()
    let
      cx = sim.gameMap.center.x
      cy = sim.gameMap.center.y
    sim.placeAt(0, cx, cy)
    sim.placeAt(1, cx + 50, cy)
    check sim.playerTrench(1) == -1
    sim.players[0].aimBrads = 0
    for _ in 0 ..< 20:
      sim.players[1].hp = sim.config.hitPoints
      sim.armToFire(0)
      sim.tryFire(0)
      check sim.players[1].hp == sim.config.hitPoints - 1
    check sim.players[0].shotsHit == 20

  test "generated maps dig walkable, team-symmetric trenches":
    ## Every pool map's trenches sit on open floor (never under a wall or
    ## outside the borders), and every dig has its exact image under the
    ## map's symmetry — neither team gets a private pit.
    var mapsWithTrenches = 0
    var sawEndzone, sawField = false
    for index in 0 ..< MapPoolSeeds.len:
      let
        gameMap = poolCtfMap(index)
        obstacles = buildArenaObstacles(gameMap)
      if gameMap.trenches.len > 0:
        inc mapsWithTrenches
      for trench in gameMap.trenches:
        check trench.w == TrenchSize
        check trench.h == TrenchSize
        var open = true
        for y in trench.y ..< trench.y + trench.h:
          for x in trench.x ..< trench.x + trench.w:
            if mapWallAt(gameMap, obstacles, x, y):
              open = false
        check open
        let cx = trench.x + trench.w div 2
        if cx < gameMap.captureClear or
            cx >= gameMap.width - gameMap.captureClear:
          sawEndzone = true
        else:
          sawField = true
        let image =
          case gameMap.symmetry
          of symMirror: MapRect(
            x: gameMap.width - trench.x - trench.w,
            y: trench.y, w: trench.w, h: trench.h)
          of symRot180: MapRect(
            x: gameMap.width - trench.x - trench.w,
            y: gameMap.height - trench.y - trench.h,
            w: trench.w, h: trench.h)
        check image in gameMap.trenches
    ## The drawn pool exercises the endzone and field placement classes.
    check mapsWithTrenches > 0
    check sawEndzone
    check sawField

  test "generated trenches are deterministic and survive the spec round-trip":
    let generated = generateCtfMap(4242)
    check generated.trenches == generateCtfMap(4242).trenches
    let rebuilt = mapFromSpecJson(mapSpecJson(generated))
    check rebuilt.trenches == generated.trenches
