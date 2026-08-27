import
  std/[algorithm, math, os, strutils],
  ../src/ctf/sim,
  toolutil

const
  SubmittedRadius = 240.0
  NarrowRadius = 320.0
  WideRadius = 480.0
  SafeMargin = 80.0

type
  BattleRoyaleError = object of CatchableError
  GunChoice = object
    found: bool
    tier: int
    distance: float
    x: int
    y: int
  ChangeCounts = object
    ticks: int
    windows: int
    files: int
    starts: int
    upgrades: int
    mid: int
    heavy: int
  GunTotals = object
    files: int
    unarmedTicks: int
    submittedChoiceTicks: int
    contest: ChangeCounts
    narrow: ChangeCounts
    wide: ChangeCounts

proc distance(x1, y1, x2, y2: int): float =
  ## Returns Euclidean distance between two replay positions.
  hypot(float(x1 - x2), float(y1 - y2))

proc playerIndex(game: SimServer, policyName: string): int =
  ## Returns the joined player index for one hosted league identity.
  for i, player in game.players:
    if player.address == policyName:
      return i
  -1

proc opponentCloser(
  game: SimServer,
  playerIndex, spawnX, spawnY: int,
  playerDistance: float
): bool =
  ## Reports whether any living opponent is closer to a pickup.
  for i, player in game.players:
    if i == playerIndex or not player.alive:
      continue
    let opponentDistance = distance(
      player.x + CollisionW div 2,
      player.y + CollisionH div 2,
      spawnX,
      spawnY
    )
    if opponentDistance < playerDistance:
      return true
  false

proc consider(
  choice: var GunChoice,
  game: SimServer,
  playerIndex, tier, spawnX, spawnY: int,
  maxDistance, safeRadius: float,
  respectOpponentLead: bool
) =
  ## Considers one visible, present gun under Hunter's selection rules.
  if not game.fovVisibleAt(playerIndex, spawnX, spawnY):
    return
  let player = game.players[playerIndex]
  let playerDistance = distance(
    player.x + CollisionW div 2,
    player.y + CollisionH div 2,
    spawnX,
    spawnY
  )
  if playerDistance > maxDistance:
    return
  let (centerX, centerY) = ffaRingCenter()
  if distance(spawnX, spawnY, centerX, centerY) > safeRadius:
    return
  if respectOpponentLead and game.opponentCloser(
      playerIndex,
      spawnX,
      spawnY,
      playerDistance):
    return
  let
    sameDistance = abs(playerDistance - choice.distance) < 1e-6
    betterPosition =
      spawnX < choice.x or
      (spawnX == choice.x and spawnY < choice.y)
  if not choice.found or tier > choice.tier or
      (tier == choice.tier and
        (playerDistance < choice.distance or
          (sameDistance and betterPosition))):
    choice = GunChoice(
      found: true,
      tier: tier,
      distance: playerDistance,
      x: spawnX,
      y: spawnY
    )

proc bestGun(
  game: SimServer,
  playerIndex: int,
  highRadius: float,
  respectOpponentLead = true
): GunChoice =
  ## Reconstructs Hunter's tier-first choice with one high-tier radius.
  let
    elapsed = game.gameTicksElapsed()
    ringRadius = game.config.ffaRingRadiusAt(elapsed)
    safeRadius = max(0.0, float(ringRadius) - SafeMargin)
  result.distance = Inf
  result.x = high(int)
  result.y = high(int)
  for spawn in game.lowGunSpawns:
    if spawn.present:
      result.consider(
        game,
        playerIndex,
        FfaWeaponLow,
        spawn.x,
        spawn.y,
        SubmittedRadius,
        safeRadius,
        respectOpponentLead
      )
  for spawn in game.midGunSpawns:
    if spawn.present:
      result.consider(
        game,
        playerIndex,
        FfaWeaponMid,
        spawn.x,
        spawn.y,
        highRadius,
        safeRadius,
        respectOpponentLead
      )
  for spawn in game.heavyGunSpawns:
    if spawn.present:
      result.consider(
        game,
        playerIndex,
        FfaWeaponHeavy,
        spawn.x,
        spawn.y,
        highRadius,
        safeRadius,
        respectOpponentLead
      )

proc differs(a, b: GunChoice): bool =
  ## Reports whether two selectors choose different pickup coordinates.
  a.found != b.found or
    (a.found and (a.tier != b.tier or a.x != b.x or a.y != b.y))

proc addChange(
  counts: var ChangeCounts,
  standard, candidate: GunChoice,
  active: var bool
) =
  ## Adds one changed high-tier selection sample and window boundary.
  let changed = standard.differs(candidate)
  if changed:
    inc counts.ticks
    if not active:
      inc counts.windows
    if not standard.found:
      inc counts.starts
    elif candidate.tier > standard.tier:
      inc counts.upgrades
    if candidate.tier == FfaWeaponHeavy:
      inc counts.heavy
    elif candidate.tier == FfaWeaponMid:
      inc counts.mid
  active = changed

proc addReplay(
  totals: var GunTotals,
  replayPath, policyName: string
) {.raises: [Exception].} =
  ## Adds one replay's visible Hunter gun choices to the totals.
  var (game, replay) = openReplay(replayPath)
  var
    index = -1
    contestActive = false
    narrowActive = false
    wideActive = false
    fileContest = false
    fileNarrow = false
    fileWide = false
  inc totals.files
  while replay.playing:
    replay.stepReplay(game)
    if index < 0:
      index = game.playerIndex(policyName)
      if index < 0:
        continue
    let player = game.players[index]
    if not player.alive or player.weaponTier != FfaWeaponUnarmed:
      narrowActive = false
      wideActive = false
      continue
    inc totals.unarmedTicks
    discard game.refreshPlayerFov(index)
    let
      standard = game.bestGun(index, SubmittedRadius)
      contest = game.bestGun(index, SubmittedRadius, false)
      narrow = game.bestGun(index, NarrowRadius)
      wide = game.bestGun(index, WideRadius)
    if standard.found:
      inc totals.submittedChoiceTicks
    totals.contest.addChange(standard, contest, contestActive)
    totals.narrow.addChange(standard, narrow, narrowActive)
    totals.wide.addChange(standard, wide, wideActive)
    fileContest = fileContest or standard.differs(contest)
    fileNarrow = fileNarrow or standard.differs(narrow)
    fileWide = fileWide or standard.differs(wide)
  if index < 0:
    raise newException(
      BattleRoyaleError,
      "hosted replay has no player named: " & policyName
    )
  if fileContest:
    inc totals.contest.files
  if fileNarrow:
    inc totals.narrow.files
  if fileWide:
    inc totals.wide.files

proc printChange(label: string, counts: ChangeCounts) =
  ## Prints one candidate radius's changed-choice coverage.
  echo label, "Ticks=", counts.ticks
  echo label, "Windows=", counts.windows
  echo label, "Files=", counts.files
  echo label, "Starts=", counts.starts
  echo label, "Upgrades=", counts.upgrades
  echo label, "MidTicks=", counts.mid
  echo label, "HeavyTicks=", counts.heavy

proc summarize(
  replayDir, policyName: string
) {.raises: [Exception].} =
  ## Summarizes visible, safe, uncontested opening-gun opportunities.
  var paths: seq[string]
  for path in walkDirRec(replayDir):
    if path.endsWith(".replay") or path.endsWith(".bitreplay"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "replay directory contains no replays: " & replayDir
    )
  var totals: GunTotals
  for path in paths:
    totals.addReplay(path, policyName)
  echo "files=", totals.files
  echo "unarmedTicks=", totals.unarmedTicks
  echo "submittedChoiceTicks=", totals.submittedChoiceTicks
  printChange("contest", totals.contest)
  printChange("narrow", totals.narrow)
  printChange("wide", totals.wide)

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_gun_opportunities REPLAY_DIR POLICY_NAME"
  )

chdirGameDir()
summarize(
  absolutePath(paramStr(1)),
  paramStr(2)
)
