import
  std/[json, strutils, unittest],
  ctf/sim
import helpers except twoTeamGame

proc puddleGame(damagePct = DefaultPuddleDamagePct, puddles = 1): SimServer =
  ## A started game with one Red player (0) and one Blue player (1) on a
  ## generated map with `puddles` paint puddles — an odd count anchors one
  ## at the map center — since no map ships puddles by default.
  var config = defaultGameConfig()
  config.update(
    """{"mapPath": "gen", "mapSeed": 4242, "mapPuddles": """ & $puddles &
    """, "puddleDamagePct": """ & $damagePct & "}"
  )
  result = initCtfForTest(config)
  discard result.addPlayer("red0")
  discard result.addPlayer("blue0")
  result.startGame()
  result.players[0].team = Red
  result.players[1].team = Blue

proc placeAt(game: var SimServer, playerIndex, px, py: int) =
  ## Puts one player's CENTER exactly on map pixel (px, py), at rest.
  game.players[playerIndex].x = px - CollisionW div 2
  game.players[playerIndex].y = py - CollisionH div 2
  game.players[playerIndex].velX = 0
  game.players[playerIndex].velY = 0

proc stepTicks(game: var SimServer, ticks: int) =
  let prev = game.none()
  for _ in 0 ..< ticks:
    game.step(game.none(), prev)

suite "paint puddles":
  test "no map has puddles by default, and the config echo stays clean":
    let plain = initCtfForTest(defaultGameConfig())
    check plain.gameMap.puddles.len == 0
    check ArenaPuddles.len == 0
    check puddleIndexAt(plain.gameMap.center.x, plain.gameMap.center.y) == -1
    # The default replay config carries NO puddle keys: an unconditional
    # echo would change every existing fixture's bytes (the no-GV-bump rule).
    let echoed = parseJson(defaultGameConfig().configJson())
    check not echoed.hasKey("mapPuddles")
    check not echoed.hasKey("puddleDamagePct")

  test "mapPuddles:1 anchors one puddle at the generated map's center":
    let game = puddleGame()
    check ArenaPuddles.len == 1
    let
      cx = game.gameMap.center.x
      cy = game.gameMap.center.y
      blob = shapeAsRect(ArenaPuddles[0])
    check blob.w == PuddleSize
    check blob.h == PuddleSize
    check puddleIndexAt(cx, cy) == 0
    check puddleIndexAt(cx - PuddleSize, cy) == -1

  test "an even request places mirror-symmetric pairs on open floor":
    let game = puddleGame(puddles = 6)
    let blobs = game.gameMap.puddles
    check blobs.len > 0
    check blobs.len mod 2 == 0
    check blobs.len <= 6
    # Every blob's mirror image is in the set (the fixture map's symmetry
    # is the classic x-reflection), and every blob sits on open floor clear
    # of both base pockets.
    for blob in blobs:
      let
        rect = shapeAsRect(blob)
        image = rect.mirrorX(game.gameMap.width)
      var found = false
      for other in blobs:
        if shapeAsRect(other) == image:
          found = true
          break
      check found
      for room in game.gameMap.rooms:
        if room.name.endsWith("Base"):
          let base = MapRect(x: room.x, y: room.y, w: room.w, h: room.h)
          check not (rect.x < base.x + base.w and base.x < rect.x + rect.w and
            rect.y < base.y + base.h and base.y < rect.y + rect.h)

  test "the puddle set pins into the map spec and round-trips exactly":
    let game = puddleGame(puddles = 4)
    check game.gameMap.puddles.len > 0
    let spec = mapSpecJson(game.gameMap)
    check parseJson(spec).hasKey("puddles")
    let rebuilt = mapFromSpecJson(spec)
    check rebuilt.puddles.len == game.gameMap.puddles.len
    for i in 0 ..< rebuilt.puddles.len:
      check shapeAsRect(rebuilt.puddles[i]) == shapeAsRect(game.gameMap.puddles[i])
    # A puddle-free map pins NO key (pre-puddle specs must stay byte-stable),
    # and a spec without the key loads as puddle-free.
    let plain = initCtfForTest(defaultGameConfig())
    check not parseJson(mapSpecJson(plain.gameMap)).hasKey("puddles")

  test "placement is deterministic from the map seed":
    let a = puddleGame(puddles = 6)
    let firstSpec = mapSpecJson(a.gameMap)
    let b = puddleGame(puddles = 6)
    check mapSpecJson(b.gameMap) == firstSpec

  test "a full second of continuous occupancy rolls; dipping out resets":
    var game = puddleGame(damagePct = 0)
    let
      cx = game.gameMap.center.x
      cy = game.gameMap.center.y
    game.placeAt(0, cx, cy)
    check game.playerPuddle(0) == 0
    game.stepTicks(PuddleRollTicks - 1)
    check game.players[0].puddleTicks == PuddleRollTicks - 1
    # One tick on clean floor restarts the second.
    game.placeAt(0, cx - PuddleSize * 2, cy)
    game.stepTicks(1)
    check game.players[0].puddleTicks == 0
    game.placeAt(0, cx, cy)
    game.stepTicks(PuddleRollTicks - 1)
    check game.players[0].puddleTicks == PuddleRollTicks - 1
    # At pct 0 the completed second resets the clock and never hurts.
    game.stepTicks(1)
    check game.players[0].puddleTicks == 0
    check game.players[0].hp == game.config.hitPoints

  test "puddleDamagePct 100 deals exactly 1 damage per completed second":
    var game = puddleGame(damagePct = 100)
    game.placeAt(0, game.gameMap.center.x, game.gameMap.center.y)
    game.stepTicks(PuddleRollTicks - 1)
    check game.players[0].hp == game.config.hitPoints
    game.stepTicks(1)
    check game.players[0].hp == game.config.hitPoints - 1
    # The clock restarted: the next damage lands one full second later.
    game.stepTicks(PuddleRollTicks - 1)
    check game.players[0].hp == game.config.hitPoints - 1
    game.stepTicks(1)
    check game.players[0].hp == game.config.hitPoints - 2

  test "the shield layer soaks the puddle hit before base hp":
    var game = puddleGame(damagePct = 100)
    game.players[0].hasShield = true
    game.players[0].shieldHp = 1
    game.placeAt(0, game.gameMap.center.x, game.gameMap.center.y)
    game.stepTicks(PuddleRollTicks)
    check game.players[0].shieldHp == 0
    check game.players[0].hasShield == false
    check game.players[0].hp == game.config.hitPoints

  test "a lethal roll is an environmental death: nobody gets the kill":
    var game = puddleGame(damagePct = 100)
    game.players[0].hp = 1
    game.placeAt(0, game.gameMap.center.x, game.gameMap.center.y)
    game.stepTicks(PuddleRollTicks)
    check not game.players[0].alive
    check game.players[0].deaths == 1
    check game.players[0].puddleTicks == 0
    for player in game.players:
      check player.kills == 0

  test "a dead body in the puddle never ticks the clock":
    var game = puddleGame(damagePct = 0)
    game.placeAt(0, game.gameMap.center.x, game.gameMap.center.y)
    game.players[0].alive = false
    game.stepTicks(PuddleRollTicks)
    check game.players[0].puddleTicks == 0

  test "a puddle game's replay config echoes both knobs":
    let game = puddleGame(damagePct = 25, puddles = 2)
    let echoed = parseJson(game.config.configJson())
    check echoed["mapPuddles"].getInt() == 2
    check echoed["puddleDamagePct"].getInt() == 25

  test "config validation rejects out-of-range knobs":
    var config = defaultGameConfig()
    expect CtfError:
      config.update("""{"puddleDamagePct": 101}""")
    expect CtfError:
      config.update("""{"mapPath": "gen", "mapSeed": 1, "mapPuddles": 65}""")
    expect CtfError:
      ## 4-team maps refuse an explicit puddle request, like trenches.
      config.update(
        """{"mapPath": "gen", "mapSeed": 1, "teams": 4, "mapPuddles": 2}""")
