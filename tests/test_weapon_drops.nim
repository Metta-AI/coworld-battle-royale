import
  helpers,
  std/[json, unittest],
  bitworld/spriteprotocol,
  ctf/[broadcast, global, sim]

proc ffaDropGame(dropEnabled: bool): SimServer =
  var config = defaultFfaConfig(3)
  config.dropWeaponOnDeath = dropEnabled
  result = initCtfForTest(config)
  for i in 0 ..< 3:
    discard result.addPlayer("drop" & $i)
  result.startGame()
  result.collectEvents = true

proc killAtCenter(game: var SimServer, victim, killer: int) =
  game.players[victim].placeAtCenter(400, MapHeight div 2)
  game.players[killer].placeAtCenter(500, MapHeight div 2)
  game.killPlayer(victim, killer)

suite "dormant FFA weapon drops":
  test "disabled by default and absent from config JSON and hash":
    let config = defaultFfaConfig(3)
    check not config.dropWeaponOnDeath
    check not parseJson(config.configJson()).hasKey("dropWeaponOnDeath")
    var game = ffaDropGame(false)
    var control = ffaDropGame(false)
    game.players[0].weaponTier = FfaWeaponMid
    control.players[0].weaponTier = FfaWeaponMid
    game.killAtCenter(0, 1)
    control.killAtCenter(0, 1)
    check game.droppedGuns.len == 0
    check game.events[^1].kind == Death
    check game.events[^1].amount == 0
    check game.gameHash() == control.gameHash()
    check game.buildStateJson(
      newJArray(), false, 1, game.effectiveMaxTicks(), false, true, -1, 0
    ) == control.buildStateJson(
      newJArray(), false, 1, control.effectiveMaxTicks(), false, true, -1, 0
    )

  test "armed victim drops its tier at the death center":
    var game = ffaDropGame(true)
    game.players[0].weaponTier = FfaWeaponMid
    game.killAtCenter(0, 1)
    check game.droppedGuns.len == 1
    check game.droppedGuns[0].tier == FfaWeaponMid
    check game.droppedGuns[0].present
    check game.droppedGuns[0].x == 400
    check game.droppedGuns[0].y == MapHeight div 2
    check game.droppedGuns[0].dropTick == game.tickCount
    check game.events[^1].kind == Death
    check game.events[^1].amount == FfaWeaponMid

  test "lower tier consumes a drop without respawn":
    var game = ffaDropGame(true)
    game.players[0].weaponTier = FfaWeaponMid
    game.killAtCenter(0, 1)
    game.players[2].placeAtCenter(400, MapHeight div 2)
    game.players[2].weaponTier = FfaWeaponLow
    game.players[2].fireWindup = 4
    game.players[2].windupBrads = 0
    game.tryPickupGuns(2)
    check game.players[2].weaponTier == FfaWeaponMid
    check not game.droppedGuns[0].present
    check game.players[2].fireWindup == 0
    check game.players[2].windupBrads == -1
    check game.events[^1].kind == Pickup
    check game.events[^1].item == "dropped mid gun"
    game.tickCount += FfaLootRespawnTicks
    game.updateGuns()
    check not game.droppedGuns[0].present

  test "pickup chooses the highest nearby upgrade":
    var game = ffaDropGame(true)
    game.droppedGuns = @[
      DroppedWeapon(x: 400, y: MapHeight div 2, tier: FfaWeaponLow,
        present: true),
      DroppedWeapon(x: 400, y: MapHeight div 2, tier: FfaWeaponHeavy,
        present: true)
    ]
    game.players[2].placeAtCenter(400, MapHeight div 2)
    game.tryPickupGuns(2)
    check game.players[2].weaponTier == FfaWeaponHeavy
    check game.droppedGuns[0].present
    check not game.droppedGuns[1].present

  test "equal or higher tiers and unarmed victims do not consume or drop":
    var game = ffaDropGame(true)
    game.players[0].weaponTier = FfaWeaponMid
    game.killAtCenter(0, 1)
    game.players[2].placeAtCenter(400, MapHeight div 2)
    game.players[2].weaponTier = FfaWeaponMid
    game.tryPickupGuns(2)
    check game.droppedGuns[0].present
    game.players[2].weaponTier = FfaWeaponHeavy
    game.tryPickupGuns(2)
    check game.droppedGuns[0].present
    var unarmed = ffaDropGame(true)
    unarmed.killAtCenter(0, 1)
    check unarmed.droppedGuns.len == 0

  test "drop state is included in enabled hash":
    var game = ffaDropGame(true)
    let before = game.gameHash()
    game.players[0].weaponTier = FfaWeaponLow
    game.killAtCenter(0, 1)
    check game.gameHash() != before

  test "enabled config is parsed and echoed":
    var config = defaultFfaConfig(3)
    config.update("""{"dropWeaponOnDeath":true}""")
    check config.dropWeaponOnDeath
    check parseJson(config.configJson())["dropWeaponOnDeath"].getBool

  test "dropped guns use existing broadcast tokens and render":
    var game = ffaDropGame(true)
    game.players[0].weaponTier = FfaWeaponMid
    game.killAtCenter(0, 1)
    let
      json = game.playerMessages(2)
      state = parseJson(game.buildStateJson(
        newJArray(), false, 1, game.effectiveMaxTicks(), false, true, -1, 0
      ))
    check json.len > 0
    var mapItem = false
    for item in state["fp"]["map"]["items"]:
      if item["item"].getStr == "mid gun" and
          item["x"].getInt == 400 and item["y"].getInt == MapHeight div 2:
        mapItem = true
    check mapItem
    var boardState = initGlobalViewerState()
    let messages = game.buildGlobalMessages(boardState)
    var rendered = false
    for message in messages:
      if message.kind == spkObject and
          message.objectDef.id == DroppedGunObjectBase:
        rendered = true
    check rendered
