import
  std/[algorithm, math, os, strutils],
  ../src/ctf/sim,
  toolutil

const
  ShieldNearRadius = 90.0
  ShieldMediumRadius = 160.0
  ShieldFarRadius = 240.0
  ShieldSafeMargin = 80.0

type
  BattleRoyaleError = object of CatchableError
  ShieldTotals = object
    files: int
    pickupEvents: int
    unshieldedDeaths: int
    nearTicks: int
    nearWindows: int
    nearFiles: int
    mediumTicks: int
    mediumWindows: int
    mediumFiles: int
    farTicks: int
    farWindows: int
    farFiles: int
    nearUnarmedTicks: int
    nearUnarmedWindows: int
    nearUnarmedFiles: int
    mediumUnarmedTicks: int
    mediumUnarmedWindows: int
    mediumUnarmedFiles: int
    farUnarmedTicks: int
    farUnarmedWindows: int
    farUnarmedFiles: int

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
    let distance = distance(player.x, player.y, spawnX, spawnY)
    if distance < playerDistance:
      return true
  false

proc safeShieldDistances(
  game: SimServer,
  playerIndex: int
): seq[float] =
  ## Returns distances to present, ring-safe, uncontested shields.
  let
    player = game.players[playerIndex]
    elapsed = game.gameTicksElapsed()
    ringRadius = game.config.ffaRingRadiusAt(elapsed)
    (centerX, centerY) = ffaRingCenter()
    safeRadius = max(0.0, float(ringRadius) - ShieldSafeMargin)
  for spawn in game.shieldSpawns:
    if not spawn.present or
      distance(spawn.x, spawn.y, centerX, centerY) > safeRadius:
        continue
    let playerDistance = distance(
      player.x,
      player.y,
      spawn.x,
      spawn.y
    )
    if not game.opponentCloser(
      playerIndex,
      spawn.x,
      spawn.y,
      playerDistance
    ):
      result.add(playerDistance)

proc addReplay(
  totals: var ShieldTotals,
  replayPath, policyName: string
) {.raises: [Exception].} =
  ## Adds one replay's shield opportunities to the totals.
  var (game, replay) = openReplay(replayPath)
  var
    index = -1
    wasAlive = false
    wasShielded = false
    nearActive = false
    mediumActive = false
    farActive = false
    nearUnarmedActive = false
    mediumUnarmedActive = false
    farUnarmedActive = false
    fileNear = false
    fileMedium = false
    fileFar = false
    fileNearUnarmed = false
    fileMediumUnarmed = false
    fileFarUnarmed = false
  inc totals.files
  while replay.playing:
    replay.stepReplay(game)
    if index < 0:
      index = game.playerIndex(policyName)
      if index < 0:
        continue
    let player = game.players[index]
    if wasAlive and not player.alive and not wasShielded:
      inc totals.unshieldedDeaths
      break
    if not wasShielded and player.shieldHp > 0:
      inc totals.pickupEvents
    wasAlive = player.alive
    wasShielded = player.shieldHp > 0
    if not player.alive or wasShielded:
      nearActive = false
      mediumActive = false
      farActive = false
      nearUnarmedActive = false
      mediumUnarmedActive = false
      farUnarmedActive = false
      continue
    let distances = game.safeShieldDistances(index)
    let nearest =
      if distances.len > 0: distances.min()
      else: Inf
    let
      near = nearest <= ShieldNearRadius
      medium = nearest <= ShieldMediumRadius
      far = nearest <= ShieldFarRadius
      unarmed = player.weaponTier == FfaWeaponUnarmed
      nearUnarmed = near and unarmed
      mediumUnarmed = unarmed and nearest <= ShieldMediumRadius
      farUnarmed = unarmed and nearest <= ShieldFarRadius
    if near:
      inc totals.nearTicks
      fileNear = true
      if not nearActive:
        inc totals.nearWindows
    if medium:
      inc totals.mediumTicks
      fileMedium = true
      if not mediumActive:
        inc totals.mediumWindows
    if far:
      inc totals.farTicks
      fileFar = true
      if not farActive:
        inc totals.farWindows
    if nearUnarmed:
      inc totals.nearUnarmedTicks
      fileNearUnarmed = true
      if not nearUnarmedActive:
        inc totals.nearUnarmedWindows
    if mediumUnarmed:
      inc totals.mediumUnarmedTicks
      fileMediumUnarmed = true
      if not mediumUnarmedActive:
        inc totals.mediumUnarmedWindows
    if farUnarmed:
      inc totals.farUnarmedTicks
      fileFarUnarmed = true
      if not farUnarmedActive:
        inc totals.farUnarmedWindows
    nearActive = near
    mediumActive = medium
    farActive = far
    nearUnarmedActive = nearUnarmed
    mediumUnarmedActive = mediumUnarmed
    farUnarmedActive = farUnarmed
  if index < 0:
    raise newException(
      BattleRoyaleError,
      "hosted replay has no player named: " & policyName
    )
  if fileNear:
    inc totals.nearFiles
  if fileMedium:
    inc totals.mediumFiles
  if fileFar:
    inc totals.farFiles
  if fileNearUnarmed:
    inc totals.nearUnarmedFiles
  if fileMediumUnarmed:
    inc totals.mediumUnarmedFiles
  if fileFarUnarmed:
    inc totals.farUnarmedFiles

proc summarize(
  replayDir, policyName: string
) {.raises: [Exception].} =
  ## Summarizes safe shield pickup opportunities in hosted replays.
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
  var totals: ShieldTotals
  for path in paths:
    totals.addReplay(path, policyName)
  echo "files=", totals.files
  echo "pickupEvents=", totals.pickupEvents
  echo "unshieldedDeaths=", totals.unshieldedDeaths
  echo "nearTicks=", totals.nearTicks
  echo "nearWindows=", totals.nearWindows
  echo "nearFiles=", totals.nearFiles
  echo "mediumTicks=", totals.mediumTicks
  echo "mediumWindows=", totals.mediumWindows
  echo "mediumFiles=", totals.mediumFiles
  echo "farTicks=", totals.farTicks
  echo "farWindows=", totals.farWindows
  echo "farFiles=", totals.farFiles
  echo "nearUnarmedTicks=", totals.nearUnarmedTicks
  echo "nearUnarmedWindows=", totals.nearUnarmedWindows
  echo "nearUnarmedFiles=", totals.nearUnarmedFiles
  echo "mediumUnarmedTicks=", totals.mediumUnarmedTicks
  echo "mediumUnarmedWindows=", totals.mediumUnarmedWindows
  echo "mediumUnarmedFiles=", totals.mediumUnarmedFiles
  echo "farUnarmedTicks=", totals.farUnarmedTicks
  echo "farUnarmedWindows=", totals.farUnarmedWindows
  echo "farUnarmedFiles=", totals.farUnarmedFiles

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_shield_opportunities REPLAY_DIR POLICY_NAME"
  )

chdirGameDir()
summarize(
  absolutePath(paramStr(1)),
  paramStr(2)
)
