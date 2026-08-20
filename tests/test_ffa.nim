## Battle-royale (mode "ffa") core: the N-derived spawn ring, single-life
## elimination over the 20 hp pool, the total placement order, the scoring
## arithmetic, and the guarantee that every match names a winner. Every check
## here is mode-gated behavior — a ctf game must reach none of it.

import
  helpers,
  std/[json, sequtils, strutils, unittest],
  bitworld/spriteprotocol,
  ctf/[global, sim]

proc ffaGame(seats: int, maxTicks = 0): SimServer =
  ## A started ffa match with `seats` players, one per distinct address.
  var config = defaultFfaConfig(seats)
  if maxTicks > 0:
    config.maxTicks = maxTicks
  result = initCtfForTest(config)
  for i in 0 ..< seats:
    discard result.addPlayer("ffa" & $i)
  result.startGame()

proc stepNone(sim: var SimServer, ticks: int) =
  let input = sim.none()
  for _ in 0 ..< ticks:
    sim.step(input, input)

proc centerOf(player: Player): tuple[x, y: int] =
  (player.x + CollisionW div 2, player.y + CollisionH div 2)

suite "ffa config":
  test "the ffa baseline is single life over a 20 hp pool at N seats":
    let config = defaultFfaConfig(7)
    check config.isFfa()
    check config.numPlayers == 7
    check config.minPlayers == 7
    check config.lives == 1
    check config.hitPoints == FfaHitPoints
    check config.survivalPointsPerSec == FfaSurvivalPointsPerSec
    check config.killPoints == FfaKillPoints
    check config.assistPoints == FfaAssistPoints
    check config.assistWindowTicks == FfaAssistWindowTicks
    check config.podiumPoints == @FfaPodiumPoints
    check config.ringShrinkSec == FfaRingShrinkSec
    check config.ringFloorAreaPct == FfaRingFloorAreaPct
    check config.ringRecoveryTicks == FfaRingRecoveryTicks
    check config.ffaGunDamage == FfaGunDamage
    check config.ffaSprayDamage == FfaSprayDamage
    check config.ffaGrenadeDamage == FfaGrenadeDamage
    check config.ffaGrenadeTrenchSplashDamage ==
      FfaGrenadeTrenchSplashDamage
    check config.ffaMedKitSpawns == FfaMedKitSpawns
    check config.ffaLootCount == FfaLootCount
    check config.ffaLootRadius == FfaLootRadius
    check config.ffaLootRespawnTicks == FfaLootRespawnTicks

  test "ctf is the default and echoes no ffa key":
    let config = defaultGameConfig()
    check config.mode == CtfMode
    check not config.isFfa()
    let echoed = parseJson(config.configJson())
    for key in ["mode", "numPlayers", "survivalPointsPerSec", "killPoints",
        "assistPoints", "assistWindowTicks", "podiumPoints", "ffaGunDamage",
        "ffaSprayDamage", "ffaGrenadeDamage",
        "ffaGrenadeTrenchSplashDamage", "ffaMedKitSpawns",
        "ffaLootCount", "ffaLootRadius", "ffaLootRespawnTicks"]:
      check not echoed.hasKey(key)

  test "an ffa config round-trips through its replay echo":
    var config = defaultFfaConfig(9)
    config.killPoints = 12
    config.podiumPoints = @[50, 20]
    config.ffaGunDamage = 4
    config.ffaSprayDamage = 3
    config.ffaGrenadeDamage = 2
    config.ffaGrenadeTrenchSplashDamage = 1
    config.ffaMedKitSpawns = 1
    config.ffaLootCount = 8
    config.ffaLootRadius = 120
    config.ffaLootRespawnTicks = 96
    var reloaded = defaultGameConfig()
    reloaded.update(config.configJson())
    check reloaded.mode == FfaMode
    check reloaded.numPlayers == 9
    check reloaded.lives == 1
    check reloaded.hitPoints == FfaHitPoints
    check reloaded.killPoints == 12
    check reloaded.podiumPoints == @[50, 20]
    check reloaded.ffaGunDamage == 4
    check reloaded.ffaSprayDamage == 3
    check reloaded.ffaGrenadeDamage == 2
    check reloaded.ffaGrenadeTrenchSplashDamage == 1
    check reloaded.ffaMedKitSpawns == 1
    check reloaded.ffaLootCount == 8
    check reloaded.ffaLootRadius == 120
    check reloaded.ffaLootRespawnTicks == 96

  test "ctf retains the original combat economy defaults":
    let config = defaultGameConfig()
    check not config.isFfa()
    check config.ffaGunDamage == FfaGunDamage
    check config.ffaSprayDamage == FfaSprayDamage
    check config.ffaGrenadeDamage == FfaGrenadeDamage
    check config.ffaGrenadeTrenchSplashDamage ==
      FfaGrenadeTrenchSplashDamage
    check config.ffaMedKitSpawns == FfaMedKitSpawns
    check config.ffaLootCount == FfaLootCount

  test "numPlayers is validated, and only in ffa":
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "numPlayers": 1}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "numPlayers": 17}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"numPlayers": 8}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "deathmatch"}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "ffaGunDamage": 0}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "ffaMedKitSpawns": 3}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "ffaLootCount": 65}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "ffaLootRadius": 0}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"mode": "ffa", "ffaLootRespawnTicks": 0}""")
    expect CtfError:
      var config = defaultGameConfig()
      config.update("""{"ffaGunDamage": 4}""")

suite "ffa spawn ring":
  test "center loot weights sustain as a minority across cluster sizes":
    for (count, expectedMed, expectedShield) in [
        (4, 1, 0), (8, 1, 1), (12, 2, 2), (16, 2, 2)]:
      var config = defaultFfaConfig(4)
      config.ffaLootCount = count
      let game = initCtfForTest(config)
      let families = game.ffaLootFamilyCounts()
      check families.medKits == expectedMed
      check families.shields == expectedShield
      check families.medKits + families.shields <
        families.plasmaArcs + families.barriers
    var capped = defaultFfaConfig(4)
    capped.ffaMedKitSpawns = 1
    capped.ffaLootCount = FfaLootCount
    check initCtfForTest(capped).ffaLootFamilyCounts().medKits == 1

  test "center loot is deterministic, spaced, walkable, and inside the ring floor":
    var first = ffaGame(4)
    var second = ffaGame(4)
    check first.medKitSpawns.len + first.shieldSpawns.len +
      first.plasmaArcSpawns.len + first.barrierSpawns.len == FfaLootCount
    check first.grenadeSpawns.len == 4
    let floor = ffaRingFloorRadius(first.config)
    var points: seq[tuple[x, y: int]] = @[]
    var
      minRadius = high(int)
      maxRadius = 0
    for spawn in first.medKitSpawns:
      points.add((spawn.x, spawn.y))
    for spawn in first.shieldSpawns:
      points.add((spawn.x, spawn.y))
    for spawn in first.plasmaArcSpawns:
      points.add((spawn.x, spawn.y))
    for spawn in first.barrierSpawns:
      points.add((spawn.x, spawn.y))
    for spawn in first.grenadeSpawns:
      points.add((spawn.x, spawn.y))
    for i, point in points:
      check first.canOccupy(point.x, point.y)
      let radius = distSq(point.x, point.y, MapWidth div 2, MapHeight div 2)
      minRadius = min(minRadius, radius)
      maxRadius = max(maxRadius, radius)
      check radius <=
        (floor + 20) * (floor + 20)
      for other in points[0 ..< i]:
        check distSq(point.x, point.y, other.x, other.y) >
          (2 * MedKitPickupRange) * (2 * MedKitPickupRange)
    check maxRadius - minRadius > 20 * 20
    check first.medKitSpawns == second.medKitSpawns
    check first.shieldSpawns == second.shieldSpawns
    check first.plasmaArcSpawns == second.plasmaArcSpawns
    check first.barrierSpawns == second.barrierSpawns
    for i in 0 ..< first.grenadeSpawns.len:
      check first.grenadeSpawns[i] == second.grenadeSpawns[i]
    var staggered = false
    for spawn in first.medKitSpawns:
      staggered = staggered or not spawn.present
    for spawn in first.shieldSpawns:
      staggered = staggered or not spawn.present
    for spawn in first.plasmaArcSpawns:
      staggered = staggered or not spawn.present
    for spawn in first.barrierSpawns:
      staggered = staggered or not spawn.present
    check staggered

  test "ffa loot uses slower sustain and faster offensive respawn cadences":
    var medGame = ffaGame(2)
    medGame.tickCount = 100
    medGame.players[0].hp = 1
    medGame.players[0].placeAtCenter(
      medGame.medKitSpawns[0].x, medGame.medKitSpawns[0].y)
    medGame.tryPickupMedKits(0)
    check medGame.medKitSpawns[0].respawnAt ==
      100 + MedKitRespawnTicks

    var shieldGame = ffaGame(2)
    shieldGame.tickCount = 100
    shieldGame.players[0].placeAtCenter(
      shieldGame.shieldSpawns[0].x, shieldGame.shieldSpawns[0].y)
    shieldGame.tryPickupShields(0)
    check shieldGame.shieldSpawns[0].respawnAt ==
      100 + ShieldRespawnTicks

    var plasmaGame = ffaGame(2)
    plasmaGame.tickCount = 100
    plasmaGame.players[0].placeAtCenter(
      plasmaGame.plasmaArcSpawns[0].x, plasmaGame.plasmaArcSpawns[0].y)
    plasmaGame.tryPickupPlasmaArcs(0)
    check plasmaGame.plasmaArcSpawns[0].respawnAt ==
      100 + plasmaGame.config.ffaLootRespawnTicks

    var barrierGame = ffaGame(2)
    barrierGame.tickCount = 100
    barrierGame.players[0].placeAtCenter(
      barrierGame.barrierSpawns[0].x, barrierGame.barrierSpawns[0].y)
    barrierGame.tryPickupBarriers(0)
    check barrierGame.barrierSpawns[0].respawnAt ==
      100 + barrierGame.config.ffaLootRespawnTicks

    var grenadeGame = ffaGame(2)
    grenadeGame.tickCount = 100
    grenadeGame.players[0].placeAtCenter(
      grenadeGame.grenadeSpawns[0].x, grenadeGame.grenadeSpawns[0].y)
    grenadeGame.tryPickupGrenades(0)
    check grenadeGame.grenadeSpawns[0].respawnAt ==
      100 + grenadeGame.config.ffaLootRespawnTicks

  test "spawn pads derive from N alone, for N in 2, 5 and 16":
    for seats in [2, 5, 16]:
      var game = ffaGame(seats)
      check game.players.len == seats
      var
        radii: seq[int] = @[]
        centers: seq[tuple[x, y: int]] = @[]
      for i in 0 ..< seats:
        let spot = game.players[i].centerOf()
        check game.canOccupy(game.players[i].homeX, game.players[i].homeY)
        centers.add spot
        radii.add distSq(spot.x, spot.y, MapWidth div 2, MapHeight div 2)
      # Equal distance to center: the pads sit on one ring, and only the snap
      # to reachable floor moves them off it.
      for radius in radii:
        check abs(radius - radii[0]) <= 120 * 120
      # Maximum pairwise spacing for this N: no two seats share a pad, and
      # the tightest ring (16 seats) still leaves bodies clear of each other.
      for i in 0 ..< seats:
        for j in i + 1 ..< seats:
          check centers[i] != centers[j]
          check distSq(centers[i].x, centers[i].y, centers[j].x, centers[j].y) >
            (2 * CollisionW) * (2 * CollisionW)

  test "seat colors are per player, not per team":
    for seats in 2 .. PlayerColors.len:
      var game = ffaGame(seats)
      var seen: seq[uint8] = @[]
      for player in game.players:
        check player.color notin seen
        seen.add player.color

  test "rig sprite keys use identity in ffa and team in ctf":
    check rigHeadSpriteId(0, DefaultSkin, 0) !=
      rigHeadSpriteId(1, DefaultSkin, 0)
    check rigGunSpriteId(0, 0) != rigGunSpriteId(1, 0)
    check rigArmSpriteId(0, rsArmL, 0, 0) !=
      rigArmSpriteId(1, rsArmL, 0, 0)
    check rigLegSpriteId(0, rsLegFL, 0, 0, 0) !=
      rigLegSpriteId(1, rsLegFL, 0, 0, 0)
    check rigWheelSpriteId(0, rsWheelL, 0, 0) !=
      rigWheelSpriteId(1, rsWheelL, 0, 0)
    check rigHeadSpriteId(Red, DefaultSkin, 0) !=
      rigHeadSpriteId(Blue, DefaultSkin, 0)
    check rigGunSpriteId(Red, 0) != rigGunSpriteId(Blue, 0)

  test "ffa player-view art and identity badges use distinct color pools":
    check soldierPlayerSpriteId(0, DefaultSkin, 0) !=
      soldierPlayerSpriteId(1, DefaultSkin, 0)
    check selectedSoldierPlayerSpriteId(0, DefaultSkin, 0) !=
      selectedSoldierPlayerSpriteId(1, DefaultSkin, 0)
    check identityBadgeSpriteId(0, 0, 0) !=
      identityBadgeSpriteId(1, 0, 0)
    let
      game = ffaGame(2)
      redBubble = game.buildShoutBubbleForColor(0, "hello")
      orangeBubble = game.buildShoutBubbleForColor(1, "hello")
      redSoldier = soldierRotPixelsForColor(0, DefaultSkin, 0)
      orangeSoldier = soldierRotPixelsForColor(1, DefaultSkin, 0)
    check redBubble.pixels != orangeBubble.pixels
    check redSoldier != orangeSoldier

  test "ffa spectator header is alive count and timer, not team lives":
    var game = ffaGame(4)
    game.players[3].alive = false
    let header = game.ffaScoreboardHeaderText()
    check header.startsWith("ALIVE 3")
    check "TIME " in header
    check "LIVES" notin header
    check "RED" notin header

  test "ffa game over title names the winning identity color":
    var game = ffaGame(3)
    game.killPlayer(0, 1)
    game.killPlayer(2, 1)
    game.stepNone(1)
    check game.ffaGameOverTitle() == "ORANGE WINS"

  test "ffa spawns no hearts and no capture path is reachable":
    var game = ffaGame(4)
    for team in game.teams():
      check game.flags[team].captured
      check game.flags[team].carrier == -1
    for i in 0 ..< game.players.len:
      game.players[i].placeAtCenter(
        game.gameMap.flagHome(Red).x, game.gameMap.flagHome(Red).y)
      game.tryPickupFlags(i)
      check not game.players[i].carryingFlag

  test "ffa map markers omit capture zones and team base rooms":
    var game = ffaGame(4)
    var state = initGlobalViewerState()
    let messages = game.buildGlobalMessages(state)
    var labels: seq[string] = @[]
    for message in messages:
      if message.kind == spkSprite:
        labels.add(message.sprite.label)
    check not labels.anyIt(it.startsWith("endzone "))
    check not labels.anyIt(it.startsWith("game teams "))
    check "Room Red" notin labels
    check "Room Blue" notin labels

suite "ffa elimination":
  test "the ring shrinks linearly, damages only on cadence, and respects floor":
    var game = ffaGame(2)
    game.config.ringShrinkSec = 1
    game.config.ringDamageTicks = 3
    game.players[0].placeAtCenter(20, 20)
    let
      start = ffaRingStartRadius()
      floor = ffaRingFloorRadius(game.config)
      center = ffaRingCenter()
    check ffaRingRadiusAt(game.config, 0) == start
    check ffaRingRadiusAt(game.config, TargetFps div 2) < start
    check ffaRingRadiusAt(game.config, TargetFps) == floor
    check ffaRingRadiusAt(game.config, 20 * TargetFps) == floor
    game.tickCount = TargetFps
    let hp = game.players[0].hp
    game.updateFfaRing()
    check game.players[0].hp == hp
    game.players[0].ringTicks = game.config.ringDamageTicks - 1
    game.updateFfaRing()
    check game.players[0].hp == hp - 1
    game.players[0].placeAtCenter(center.x, center.y)
    game.players[0].ringTicks = 5
    game.updateFfaRing()
    check game.players[0].ringTicks == 5 - FfaRingRecoveryTicks

  test "one life over a 20 hp pool, and no respawn ever rearms":
    var game = ffaGame(4)
    for player in game.players:
      check player.hp == FfaHitPoints
      check player.lives == 1
      check player.deathTick == -1
    game.absorbDamage(0, FfaHitPoints - 1)
    check game.players[0].hp == 1
    check game.players[0].alive
    game.absorbDamage(0, 1)
    game.killPlayer(0, 1)
    check not game.players[0].alive
    check game.players[0].lives == 0
    check game.players[0].respawnTimer == 0
    check game.players[0].deathTick == game.tickCount
    game.stepNone(3 * game.config.respawnTicks)
    check not game.players[0].alive

  test "an ffa gun hit takes 2 of the pool and books damage dealt":
    var game = ffaGame(2)
    let midY = MapHeight div 2
    game.players[0].placeAtCenter(300, midY)
    game.players[1].placeAtCenter(340, midY)
    game.players[0].aimBrads = 0
    game.armToFire(0)
    game.tryFire(0)
    check game.players[1].hp == FfaHitPoints - FfaGunDamage
    check game.players[0].damageDealt == FfaGunDamage

  test "ffa combat economy overrides damage and med-kit count":
    var config = defaultFfaConfig(2)
    config.ffaGunDamage = 4
    config.ffaLootCount = 4
    var game = initCtfForTest(config)
    for i in 0 ..< 2:
      discard game.addPlayer("economy" & $i)
    game.startGame()
    check game.medKitSpawns.len == 1
    let midY = MapHeight div 2
    game.players[0].placeAtCenter(300, midY)
    game.players[1].placeAtCenter(340, midY)
    game.players[0].aimBrads = 0
    game.armToFire(0)
    game.tryFire(0)
    check game.players[1].hp == FfaHitPoints - 4
    check game.players[0].damageDealt == 4

suite "ffa placement":
  test "placement is a total order down to the slot":
    var game = ffaGame(5)
    game.tickCount = 100
    game.players[0].damageDealt = 3
    game.players[1].damageDealt = 9
    game.killPlayer(0, -1)
    game.killPlayer(1, -1)
    game.tickCount = 150
    game.players[2].damageDealt = 100
    game.killPlayer(2, -1)
    game.players[3].kills = 2
    # Alive first (more kills wins), then the later death, then the same-tick
    # pair split by damage dealt.
    check game.ffaPlacements() == @[3, 4, 2, 1, 0]

  test "a same-tick death with equal damage falls through to the lower slot":
    var game = ffaGame(3)
    game.tickCount = 60
    game.killPlayer(2, -1)
    game.killPlayer(1, -1)
    check game.ffaPlacements() == @[0, 1, 2]

suite "ffa scoring":
  test "survival, kill, assist split and podium add up":
    var game = ffaGame(4)
    game.stepNone(3 * TargetFps)
    for player in game.players:
      check player.reward == 3 * FfaSurvivalPointsPerSec
    # Slot 3 lands the killing blow on slot 0; slots 1 and 2 split the assist.
    game.recordFfaDamage(1, 0, 5)
    game.recordFfaDamage(2, 0, 5)
    game.recordFfaDamage(3, 0, 10)
    game.killPlayer(0, 3)
    check game.players[3].reward == 3 + FfaKillPoints
    check game.players[1].reward == 3 + FfaAssistPoints div 2
    check game.players[2].reward == 3 + FfaAssistPoints div 2
    check game.players[0].reward == 3
    game.killPlayer(1, 3)
    game.killPlayer(2, 3)
    game.stepNone(1)
    check game.phase == GameOver
    # Podium: the survivor takes 1st, then the two same-tick deaths by damage
    # dealt, and 4th place is off the podium.
    check game.players[3].reward == 3 + 3 * FfaKillPoints + FfaPodiumPoints[0]
    check game.players[1].reward == 3 + FfaAssistPoints div 2 + FfaPodiumPoints[1]
    check game.players[2].reward == 3 + FfaAssistPoints div 2 + FfaPodiumPoints[2]
    check game.players[0].reward == 3

  test "an environmental death credits nobody":
    var game = ffaGame(3)
    game.recordFfaDamage(1, 0, 4)
    game.killPlayer(0, -1)
    check game.players[1].reward == 0
    check game.players[2].reward == 0

  test "damage older than the assist window stops counting":
    var game = ffaGame(3)
    game.recordFfaDamage(1, 0, 4)
    game.tickCount = game.config.assistWindowTicks + 1
    game.recordFfaDamage(2, 0, 4)
    game.killPlayer(0, 2)
    check game.players[2].reward == FfaKillPoints
    check game.players[1].reward == 0

suite "ffa chat":
  test "shouts use the sender's vision and LOS, while range blocks delivery":
    var game = ffaGame(2)
    game.players[0].placeAtCenter(300, MapHeight div 2)
    game.players[1].placeAtCenter(380, MapHeight div 2)
    game.players[0].aimBrads = 0
    discard game.refreshPlayerFov(0)
    check game.playerVisibleTo(0, 1)
    check game.applyShout(0, "hello")
    check game.recentShouts.len == 1
    check game.shoutAudibleTo(1, game.recentShouts[0])
    game.players[1].placeAtCenter(MapWidth - 30, MapHeight - 30)
    discard game.refreshPlayerFov(0)
    check not game.playerVisibleTo(0, 1)
    check not game.shoutAudibleTo(1, game.recentShouts[0])

  test "the ffa player config echoes the full ring schedule":
    let config = defaultFfaConfig(4)
    let echoed = parseJson(config.configJson())
    for key in ["ringEnabled", "ringShrinkSec", "ringFloorAreaPct",
        "ringDamageTicks", "ringRecoveryTicks"]:
      check echoed.hasKey(key)
    check echoed["ringShrinkSec"].getInt == FfaRingShrinkSec
    check echoed["ringDamageTicks"].getInt == FfaRingDamageTicks
    check echoed["ringRecoveryTicks"].getInt == FfaRingRecoveryTicks

suite "ffa endings":
  test "a wipe ends the match on the named survivor":
    var game = ffaGame(3)
    game.killPlayer(0, 1)
    game.killPlayer(2, 1)
    game.stepNone(1)
    check game.phase == GameOver
    check not game.isDraw
    check game.ffaWinnerSlot == game.players[1].joinOrder
    check game.ffaWinnerSlot >= 0

  test "running the clock out still names a winner, never a draw":
    var game = ffaGame(4, maxTicks = 5 * TargetFps)
    game.stepNone(5 * TargetFps + 2)
    check game.phase == GameOver
    check game.timeLimitReached
    check not game.isDraw
    check game.ffaWinnerSlot == 0
    for player in game.players:
      check player.alive

suite "ffa determinism":
  test "the same seed replays to the same tick hashes at N=4 and N=16":
    proc scripted(seats, ticks: int): seq[uint64] =
      var game = ffaGame(seats)
      var previous = game.none()
      for tick in 0 ..< ticks:
        var input = game.none()
        for i in 0 ..< seats:
          input[i].up = ((tick + i) mod 7) < 3
          input[i].right = ((tick + i * 3) mod 5) < 2
          input[i].left = ((tick + i * 2) mod 9) < 2
          input[i].attack = ((tick + i) mod 11) < 6
        game.step(input, previous)
        previous = input
        result.add game.gameHash()
    for seats in [4, 16]:
      let first = scripted(seats, 240)
      check first.len == 240
      check first == scripted(seats, 240)
