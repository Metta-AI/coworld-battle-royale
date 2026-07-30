import
  std/[os, unittest],
  bitworld/spriteprotocol,
  ctf/sim

const GameDir = currentSourcePath.parentDir.parentDir

proc initCtfForTest(config: GameConfig): SimServer =
  ## Initializes the CTF sim from the game directory (so data/ resolves).
  let previousDir = getCurrentDir()
  setCurrentDir(GameDir)
  try:
    result = initSimServer(config)
  finally:
    setCurrentDir(previousDir)

proc twoTeamGame(): SimServer =
  ## A started game with one Red player (0) and one Blue player (1).
  result = initCtfForTest(defaultGameConfig())
  discard result.addPlayer("red0")
  discard result.addPlayer("blue0")
  result.startGame()
  result.players[0].team = Red
  result.players[1].team = Blue

proc openGround(sim: var SimServer) =
  ## All-open floor with both players apart and at rest, so held movement
  ## input produces real, deterministic displacement.
  for i in 0 ..< sim.walkMask.len:
    sim.walkMask[i] = true
  for (index, x, y) in [(0, 100, 100), (1, 400, 300)]:
    sim.players[index].x = x
    sim.players[index].y = y
    sim.players[index].velX = 0
    sim.players[index].velY = 0
    sim.players[index].carryX = 0
    sim.players[index].carryY = 0

proc sansShoutTick(player: Player, matching: Player): Player =
  ## The player with lastShoutTick copied over, so everything else can be
  ## compared for exact equality.
  result = player
  result.lastShoutTick = matching.lastShoutTick

suite "shouts":
  test "a shout is stored with player, team, and shout-time coordinates":
    var sim = twoTeamGame()
    check sim.applyShout(0, "push mid")
    check sim.recentShouts.len == 1
    let shout = sim.recentShouts[0]
    check shout.address == "red0"
    check shout.team == Red
    check shout.text == "push mid"
    check shout.tick == sim.tickCount
    check shout.x == sim.players[0].x + CollisionW div 2
    check shout.y == sim.players[0].y + CollisionH div 2

  test "shouts are truncated to the limit and sanitized":
    var sim = twoTeamGame()
    check sim.applyShout(0, "0123456789ABCDEF")
    check sim.recentShouts[0].text == "0123456789"
    check sim.recentShouts[0].text.len == ShoutMaxChars
    # Control characters are dropped; whitespace-only shouts are ignored.
    sim.players[1].lastShoutTick = -1
    check not sim.applyShout(1, "\x01\x02   \n")

  test "dead players cannot shout":
    var sim = twoTeamGame()
    sim.players[0].alive = false
    check not sim.applyShout(0, "ghost")
    check sim.recentShouts.len == 0

  test "shouting is rate limited and replaces the previous bubble":
    var sim = twoTeamGame()
    check sim.applyShout(0, "first")
    check not sim.applyShout(0, "too soon")
    check sim.recentShouts.len == 1
    check sim.recentShouts[0].text == "first"
    # After the cooldown a new shout replaces the old bubble.
    let none = newSeq[InputState](sim.players.len)
    for _ in 0 ..< ShoutCooldownTicks:
      sim.step(none, none)
    check sim.applyShout(0, "second")
    check sim.recentShouts.len == 1
    check sim.recentShouts[0].text == "second"

  test "shouts expire after their display window":
    var sim = twoTeamGame()
    check sim.applyShout(0, "brief")
    let none = newSeq[InputState](sim.players.len)
    for _ in 0 ..< ShoutTicks:
      sim.step(none, none)
    check sim.recentShouts.len == 0

  test "shouts are audible within range, through walls, but not to the dead":
    var sim = twoTeamGame()
    check sim.applyShout(0, "here")
    let shout = sim.recentShouts[0]
    # The shouter hears its own shout.
    check sim.shoutAudibleTo(0, shout)
    # A viewer just inside the radius hears it; just outside does not.
    sim.players[1].x = shout.x + ShoutRange - 1 - CollisionW div 2
    sim.players[1].y = shout.y - CollisionH div 2
    check sim.shoutAudibleTo(1, shout)
    sim.players[1].x = shout.x + ShoutRange + 1 - CollisionW div 2
    check not sim.shoutAudibleTo(1, shout)
    # Dead viewers observe nothing.
    sim.players[1].x = shout.x - CollisionW div 2
    sim.players[1].alive = false
    check not sim.shoutAudibleTo(1, shout)

  test "shouting is parallel: it never blocks or alters same-tick movement and fire":
    # Two identical worlds, identical held inputs (move right + trigger
    # pull); one of them also shouts. Talking is free: it must never
    # consume, delay, or modify any other same-tick action.
    var
      talker = twoTeamGame()
      silent = twoTeamGame()
    talker.openGround()
    silent.openGround()

    # applyShout on its own changes nothing in the player state except
    # lastShoutTick.
    let before = talker.players[0]
    check talker.applyShout(0, "on my mark")
    check talker.recentShouts.len == 1
    check talker.recentShouts[0].text == "on my mark"
    check talker.players[0].lastShoutTick == talker.tickCount
    check talker.players[0].sansShoutTick(before) == before

    # With the shout in flight, movement and fire advance in lockstep with
    # the silent world: every tick, the full player state matches exactly
    # (lastShoutTick aside).
    var inputs = newSeq[InputState](talker.players.len)
    inputs[0] = InputState(right: true, attack: true)
    var prev = newSeq[InputState](talker.players.len)
    let startX = talker.players[0].x
    for _ in 0 ..< 10:
      talker.step(inputs, prev)
      silent.step(inputs, prev)
      prev = inputs
      check talker.players[0].sansShoutTick(silent.players[0]) ==
        silent.players[0]
    check talker.players[0].x > startX      # the shouter really moved

    # A second shout inside the cooldown is rejected — and the rejection,
    # too, leaves movement and fire untouched.
    check not talker.applyShout(0, "too soon")
    check talker.recentShouts.len == 1
    check talker.recentShouts[0].text == "on my mark"
    for _ in 0 ..< 5:
      talker.step(inputs, prev)
      silent.step(inputs, prev)
      check talker.players[0].sansShoutTick(silent.players[0]) ==
        silent.players[0]

  test "shouts are part of the game hash":
    var sim1 = twoTeamGame()
    var sim2 = twoTeamGame()
    check sim1.gameHash == sim2.gameHash
    sim1.applyShout(0, "flank left")
    check sim1.gameHash != sim2.gameHash
    sim2.applyShout(0, "flank left")
    check sim1.gameHash == sim2.gameHash
