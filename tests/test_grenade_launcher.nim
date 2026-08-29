import
  helpers,
  std/[json, random, sequtils, unittest],
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
      config.grenadeLauncher = true
      let a = initCtfForTest(config)
      let b = initCtfForTest(config)
      check a.ffaLauncherSpawnTick() == b.ffaLauncherSpawnTick()
      first.add a.ffaLauncherSpawnTick()
      check first[^1] >= 0
      check first[^1] <= config.ringShrinkSec * TargetFps
    check first.deduplicate.len > 1

  test "launcher spawn timing does not consume sim RNG":
    var off = launcherGame(false)
    var on = launcherGame(true)
    var offRng = off.rng
    var onRng = on.rng
    for _ in 0 ..< 8:
      check offRng.rand(1000000) == onRng.rand(1000000)

  test "both launcher pickups appear on the exact spawn tick":
    var game = launcherGame()
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

  test "launcher pre-empts gun and excludes spray":
    var game = launcherGame()
    game.players[0].weaponTier = FfaWeaponHeavy
    game.players[0].gunAmmo = FfaHeavyGunMagazine
    game.players[0].hasLauncher = true
    game.players[0].launcherAmmo = 1
    check game.canFire(0)
    game.players[0].hasPlasmaArc = true
    check not game.canFire(0)
    game.players[0].hasPlasmaArc = false
    for spawn in game.launcherSpawns.mitems:
      spawn.present = true
    game.players[0].placeAtCenter(
      game.launcherSpawns[0].x, game.launcherSpawns[0].y)
    game.tryPickupLaunchers(0)
    check game.players[0].launcherAmmo == 1

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
