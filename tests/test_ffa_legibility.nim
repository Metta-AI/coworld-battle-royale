import
  std/[sequtils, strutils, unittest],
  bitworld/spriteprotocol,
  helpers,
  ctf/[global, sim]

suite "FFA spectator legibility":
  test "continuous health bars retain the pip-bar dimensions":
    check buildFfaHpBarSprite(2, 3, 1).len ==
      buildHpBarSprite(2, 3, 1).len
    check buildFfaHpBarSprite(5, 5, 2).len ==
      buildHpBarSprite(5, 5, 2).len

  test "FFA nameplates and roster tiers stay on the board stream":
    var config = defaultFfaConfig(4)
    var game = initCtfForTest(config)
    for i in 0 ..< 4:
      discard game.addPlayer("legibility" & $i)
    game.startGame()
    game.players[0].weaponTier = FfaWeaponUnarmed
    game.players[1].weaponTier = FfaWeaponLow
    game.players[2].weaponTier = FfaWeaponMid
    game.players[3].weaponTier = FfaWeaponHeavy
    game.players[0].hasPlasmaArc = true
    var globalState = initGlobalViewerState()
    var boardLabels: seq[string] = @[]
    for message in game.buildGlobalMessages(globalState):
      if message.kind == spkSprite:
        boardLabels.add(message.sprite.label)
    check boardLabels.anyIt(it.startsWith("name ") and it.contains("tier "))
    check boardLabels.anyIt(it == "roster tier 1")
    check boardLabels.anyIt(it == "roster arc")
    var playerState: PlayerViewerState
    for message in game.buildPlayerMessages(0, playerState):
      if message.kind == spkSprite:
        check not message.sprite.label.startsWith("roster ")
