import
  helpers,
  std/[json, unittest],
  ctf/[global, sim]

proc globalBytes(sim: var SimServer): seq[uint8] =
  var state, nextState: GlobalViewerState
  sim.buildSpriteProtocolUpdates(state, nextState)

proc playerBytes(sim: var SimServer, playerIndex: int): seq[uint8] =
  var state, nextState: PlayerViewerState
  sim.buildSpriteProtocolPlayerUpdates(playerIndex, state, nextState)

proc ammoGame(finite, drops = false): SimServer =
  var config = defaultFfaConfig(3)
  config.finiteAmmo = finite
  config.dropWeaponOnDeath = drops
  result = initCtfForTest(config)
  for i in 0 ..< 3:
    discard result.addPlayer("ammo" & $i)
  result.startGame()
  result.collectEvents = true

suite "FFA finite ammunition":
  test "disabled by default, absent from config JSON and hash":
    let config = defaultFfaConfig(3)
    check not config.finiteAmmo
    check not config.grenadeLauncher
    check not parseJson(config.configJson()).hasKey("finiteAmmo")
    var a = ammoGame(false)
    var b = ammoGame(false)
    a.players[0].gunAmmo = 7
    a.players[0].sprayTicks = 8
    a.players[0].hasLauncher = true
    a.players[0].launcherAmmo = 2
    check a.gameHash() == b.gameHash()
    check a.globalBytes() == b.globalBytes()
    check a.playerBytes(0) == b.playerBytes(0)

  test "magazines are assigned by tier":
    check ffaMagazineForTier(FfaWeaponLow) == FfaLowGunMagazine
    check ffaMagazineForTier(FfaWeaponMid) == FfaMidGunMagazine
    check ffaMagazineForTier(FfaWeaponHeavy) == FfaHeavyGunMagazine
    check ffaMagazineForTier(FfaWeaponUnarmed) == 0
    var game = ammoGame(true)
    game.players[0].placeAtCenter(
      game.heavyGunSpawns[0].x, game.heavyGunSpawns[0].y)
    game.tryPickupGuns(0)
    check game.players[0].gunAmmo == FfaHeavyGunMagazine

  test "ammo decrements only when a shot releases":
    var game = ammoGame(true)
    game.players[0].weaponTier = FfaWeaponMid
    game.players[0].gunAmmo = FfaMidGunMagazine
    game.startFireWindup(0)
    check game.players[0].gunAmmo == FfaMidGunMagazine
    game.players[0].fireWindup = 0
    game.tryFire(0)
    check game.players[0].gunAmmo == FfaMidGunMagazine - 1

  test "an empty gun becomes fists, which remain infinite":
    var game = ammoGame(true)
    game.players[0].weaponTier = FfaWeaponLow
    game.players[0].gunAmmo = 1
    game.tryFire(0)
    check game.players[0].weaponTier == FfaWeaponUnarmed
    check game.players[0].gunAmmo == 0
    game.players[0].fireCooldown = 0
    let before = game.players[0].gunAmmo
    game.tryFire(0)
    check game.players[0].gunAmmo == before

  test "spray budget is consumed by active ticks":
    var game = ammoGame(true)
    game.players[0].hasPlasmaArc = true
    game.players[0].sprayTicks = 2
    game.tryFireArc(0)
    check game.players[0].sprayTicks == 1
    game.players[0].fireCooldown = 0
    game.tryFireArc(0)
    check game.players[0].sprayTicks == 0
    check not game.players[0].hasPlasmaArc
    check game.players[0].arcTicksLeft == 0

  test "remaining corpse ammo is inherited by a picker":
    var game = ammoGame(true, true)
    game.players[0].weaponTier = FfaWeaponMid
    game.players[0].gunAmmo = 13
    game.players[0].placeAtCenter(400, MapHeight div 2)
    game.players[1].placeAtCenter(500, MapHeight div 2)
    game.killPlayer(0, 1)
    check game.droppedGuns.len == 1
    check game.droppedGuns[0].ammo == 13
    game.players[2].placeAtCenter(400, MapHeight div 2)
    game.tryPickupGuns(2)
    check game.players[2].gunAmmo == 13

  test "finite ammo permits a fuller equal-tier pickup":
    var game = ammoGame(true)
    game.players[0].weaponTier = FfaWeaponMid
    game.players[0].gunAmmo = 1
    game.players[0].placeAtCenter(
      game.midGunSpawns[0].x, game.midGunSpawns[0].y)
    game.tryPickupGuns(0)
    check game.players[0].gunAmmo == FfaMidGunMagazine
    var dormant = ammoGame(false)
    dormant.players[0].weaponTier = FfaWeaponMid
    dormant.players[0].placeAtCenter(
      dormant.midGunSpawns[0].x, dormant.midGunSpawns[0].y)
    dormant.tryPickupGuns(0)
    check dormant.players[0].weaponTier == FfaWeaponMid
    check dormant.midGunSpawns[0].present
