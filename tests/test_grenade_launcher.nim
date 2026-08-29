import
  helpers,
  std/[json, math, random, sequtils, unittest],
  ctf/sim

proc launcherGame(armed = true): SimServer =
  var config = defaultFfaConfig(3)
  config.grenadeLauncher = armed
  result = initCtfForTest(config)
  for i in 0 ..< 3:
    discard result.addPlayer("launcher" & $i)
  result.startGame()
  result.collectEvents = true

suite "FFA grenade launcher":
  test "disabled by default and absent from state":
    let config = defaultFfaConfig(3)
    check not config.grenadeLauncher
    check not parseJson(config.configJson()).hasKey("grenadeLauncher")
    let game = launcherGame(false)
    check game.launcherSpawnTick == -1
    check game.launcherSpawns.len == 0

  test "spawn tick is deterministic and seed-derived":
    var first: seq[int] = @[]
    for seed in 1 .. 20:
      var config = defaultFfaConfig(3)
      config.seed = seed
      config.mapSeed = 42
      config.grenadeLauncher = true
      let a = initCtfForTest(config)
      let b = initCtfForTest(config)
      check a.ffaLauncherSpawnTick() == b.ffaLauncherSpawnTick()
      first.add a.ffaLauncherSpawnTick()
      check first[^1] >= 0
      check first[^1] <= config.ringShrinkSec * TargetFps
    check first.deduplicate.len > 1
    var mapOnly: seq[int] = @[]
    for mapSeed in 1 .. 20:
      var config = defaultFfaConfig(3)
      config.seed = 7
      config.mapSeed = mapSeed
      config.grenadeLauncher = true
      mapOnly.add initCtfForTest(config).ffaLauncherSpawnTick()
    check mapOnly.deduplicate.len == 1

  test "launcher spawn timing does not consume sim RNG":
    var off = launcherGame(false)
    var on = launcherGame(true)
    var offRng = off.rng
    var onRng = on.rng
    for _ in 0 ..< 8:
      check offRng.rand(1000000) == onRng.rand(1000000)

  test "both launcher pickups appear on the exact spawn tick":
    var game = launcherGame()
    check game.launcherSpawns.len == LauncherSpawnCount
    check game.launcherSpawns[0].x != game.launcherSpawns[1].x or
      game.launcherSpawns[0].y != game.launcherSpawns[1].y
    for spawn in game.launcherSpawns:
      check game.isWalkable(spawn.x, spawn.y)
    game.launcherSpawnTick = game.gameTicksElapsed() + 2
    game.tickCount += 1
    game.updateGuns()
    check game.launcherSpawns.allIt(not it.present)
    game.tickCount += 1
    game.updateGuns()
    check game.launcherSpawns.len == LauncherSpawnCount
    check game.launcherSpawns.allIt(it.present)

  test "launcher pickup and firing consume three rounds":
    var game = launcherGame()
    game.launcherSpawnTick = 0
    for spawn in game.launcherSpawns.mitems:
      spawn.present = true
    game.players[0].placeAtCenter(
      game.launcherSpawns[0].x, game.launcherSpawns[0].y)
    game.tryPickupLaunchers(0)
    check game.players[0].hasLauncher
    check game.players[0].launcherAmmo == LauncherAmmoRounds
    for _ in 0 ..< LauncherAmmoRounds:
      game.players[0].fireCooldown = 0
      game.fireLauncher(0)
    check not game.players[0].hasLauncher
    check game.players[0].launcherAmmo == 0

  test "launcher pickups are spent permanently after pickup":
    var game = launcherGame()
    game.launcherSpawnTick = 0
    for spawn in game.launcherSpawns.mitems:
      spawn.present = true
    game.players[0].placeAtCenter(
      game.launcherSpawns[0].x, game.launcherSpawns[0].y)
    game.tryPickupLaunchers(0)
    check not game.launcherSpawns[0].present
    check game.launcherSpawns[0].respawnAt == -1
    check game.launcherSpawns[1].present
    inc game.tickCount
    game.updateGuns()
    check not game.launcherSpawns[0].present
    check game.launcherSpawns[1].present
    for _ in 0 ..< FfaLootRespawnTicks:
      inc game.tickCount
      game.updateGuns()
    check not game.launcherSpawns[0].present
    check game.launcherSpawns[1].present

  test "launcher pickup clears pending gunfire":
    var game = launcherGame()
    game.launcherSpawnTick = 0
    for spawn in game.launcherSpawns.mitems:
      spawn.present = true
    game.players[0].placeAtCenter(
      game.launcherSpawns[0].x, game.launcherSpawns[0].y)
    game.players[0].weaponTier = FfaWeaponHeavy
    game.players[0].gunAmmo = FfaHeavyGunMagazine
    game.players[0].fireWindup = game.config.fireWindupTicks
    game.players[0].windupBrads = 0
    game.tryPickupLaunchers(0)
    check game.players[0].hasLauncher
    check game.players[0].fireWindup == 0
    check game.players[0].windupBrads == -1
    let gunAmmo = game.players[0].gunAmmo
    let idle = game.none()
    for _ in 0 ..< game.config.fireWindupTicks + 1:
      game.step(idle, idle)
    check game.players[0].gunAmmo == gunAmmo

  test "launcher pre-empts gun and excludes spray":
    var game = launcherGame()
    game.players[0].weaponTier = FfaWeaponHeavy
    game.players[0].gunAmmo = FfaHeavyGunMagazine
    game.players[0].hasLauncher = true
    game.players[0].launcherAmmo = LauncherAmmoRounds
    check game.canFire(0)
    game.tryFire(0)
    check game.players[0].gunAmmo == FfaHeavyGunMagazine
    check game.players[0].launcherAmmo == LauncherAmmoRounds - 1
    game.players[0].hasPlasmaArc = true
    check not game.canFire(0)
    game.players[0].hasPlasmaArc = false
    game.players[0].launcherAmmo = 1
    for spawn in game.launcherSpawns.mitems:
      spawn.present = true
    game.players[0].placeAtCenter(
      game.launcherSpawns[0].x, game.launcherSpawns[0].y)
    game.tryPickupLaunchers(0)
    check game.players[0].launcherAmmo == 1

  test "launcher range follows the ring and artillery floor":
    var game = launcherGame()
    let earlyElapsed = game.gameTicksElapsed()
    let earlyRing = ffaRingRadiusAt(game.config, earlyElapsed)
    check game.ffaLauncherRange() ==
      max(4 * LauncherBlastRadius, 2 * earlyRing)
    check 2 * earlyRing > 4 * LauncherBlastRadius
    game.tickCount = game.gameStartTick +
      game.config.ringShrinkSec * TargetFps + 1
    let lateElapsed = game.gameTicksElapsed()
    check game.ffaLauncherRange() ==
      max(4 * LauncherBlastRadius,
        2 * ffaRingRadiusAt(game.config, lateElapsed))
    check game.ffaLauncherRange() == 4 * LauncherBlastRadius

  test "launcher impacts stop at walls, bodies, and range":
    var wallProbe = launcherGame()
    wallProbe.players[0].placeAtCenter(
      wallProbe.gameMap.center.x, wallProbe.gameMap.center.y)
    var wallAngle = -1
    for angle in countup(0, AimBradsTurn - 1, 8):
      let (ux, uy) = aimVector(angle)
      let sx = wallProbe.players[0].x + CollisionW div 2
      let sy = wallProbe.players[0].y + CollisionH div 2
      for step in 1 .. wallProbe.ffaLauncherRange():
        if wallProbe.isWall(
            sx + int(round(ux * float(step))),
            sy + int(round(uy * float(step)))):
          wallAngle = angle
          break
      if wallAngle >= 0:
        break
    check wallAngle >= 0
    wallProbe.players[0].hasLauncher = true
    wallProbe.players[0].launcherAmmo = 1
    wallProbe.players[0].aimBrads = wallAngle
    wallProbe.fireLauncher(0)
    let wallImpact = wallProbe.events.filterIt(it.kind == ShotImpact)
    check wallImpact.len == 1
    if wallImpact.len == 1:
      check wallImpact[0].target == -1
      check not wallProbe.isWall(int(wallImpact[0].x), int(wallImpact[0].y))

    var body = launcherGame()
    body.players[0].placeAtCenter(60, MapHeight div 2)
    body.players[0].aimBrads = 0
    body.players[0].hasLauncher = true
    body.players[0].launcherAmmo = 1
    body.players[1].placeAtCenter(110, MapHeight div 2)
    body.fireLauncher(0)
    let bodyImpact = body.events.filterIt(it.kind == ShotImpact)
    check bodyImpact.len == 1
    if bodyImpact.len == 1:
      check bodyImpact[0].target == 1

    var rangeProbe = launcherGame()
    rangeProbe.players[0].placeAtCenter(
      rangeProbe.gameMap.center.x, rangeProbe.gameMap.center.y)
    rangeProbe.tickCount = rangeProbe.gameStartTick +
      rangeProbe.config.ringShrinkSec * TargetFps + 1
    var rangeAngle = -1
    let range = rangeProbe.ffaLauncherRange()
    for angle in countup(0, AimBradsTurn - 1, 8):
      let (ux, uy) = aimVector(angle)
      let sx = rangeProbe.players[0].x + CollisionW div 2
      let sy = rangeProbe.players[0].y + CollisionH div 2
      var clear = true
      for step in 1 .. range:
        if rangeProbe.isWall(
            sx + int(round(ux * float(step))),
            sy + int(round(uy * float(step)))):
          clear = false
          break
      if clear:
        rangeAngle = angle
        break
    check rangeAngle >= 0
    rangeProbe.players[0].hasLauncher = true
    rangeProbe.players[0].launcherAmmo = 1
    rangeProbe.players[0].aimBrads = rangeAngle
    rangeProbe.fireLauncher(0)
    let rangeImpact = rangeProbe.events.filterIt(it.kind == ShotImpact)
    check rangeImpact.len == 1
    if rangeImpact.len == 1:
      check rangeImpact[0].target == -1
      check int(rangeImpact[0].distance) == range

  test "launcher blast damages the shooter at close range":
    var game = launcherGame()
    game.players[0].placeAtCenter(60, MapHeight div 2)
    game.players[0].aimBrads = 0
    game.players[0].hasLauncher = true
    game.players[0].launcherAmmo = 1
    let before = game.players[0].hp
    game.players[1].placeAtCenter(110, MapHeight div 2)
    game.fireLauncher(0)
    check game.players[0].hp == before - LauncherDamage

  test "launcher is hash-visible only when armed":
    var off = launcherGame(false)
    var offControl = launcherGame(false)
    off.launcherSpawnTick = 42
    off.launcherSpawns = @[PickupSpawn(x: 1, y: 2, present: true, respawnAt: 3)]
    offControl.players[0].hasLauncher = true
    check off.gameHash() == offControl.gameHash()
    var on = launcherGame(true)
    let before = on.gameHash()
    on.players[0].launcherAmmo = 2
    check on.gameHash() != before
