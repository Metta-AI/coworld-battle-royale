import
  std/[algorithm, math, os, strutils],
  ../src/ctf/sim,
  toolutil

const
  LowHealth = 6
  NearRadius = 180.0
  SubmittedRadius = 240.0
  SafeMargin = 80.0
  AuditRadii = [180.0, 240.0, 320.0, 520.0]

type
  BattleRoyaleError = object of CatchableError
  OpportunityCounts = object
    ticks: int
    windows: int
    files: int
  MedKitTotals = object
    files: int
    damagedTicks: int
    lowHealthTicks: int
    pickupEvents: int
    damagedVisible: OpportunityCounts
    damagedRadii: array[AuditRadii.len, OpportunityCounts]
    damagedSafeSubmitted: OpportunityCounts
    damagedNear: OpportunityCounts
    damagedSubmitted: OpportunityCounts
    lowHealthNear: OpportunityCounts

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
  ## Reports whether any visible living opponent is closer to a pickup.
  for i, player in game.players:
    if i == playerIndex or not player.alive or
        not game.playerVisibleTo(playerIndex, i):
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

proc nearestMedKit(
  game: SimServer,
  playerIndex: int,
  requireSafe,
  requireUncontested: bool
): float =
  ## Returns the nearest visible medkit passing optional safety gates.
  result = Inf
  let
    player = game.players[playerIndex]
    playerX = player.x + CollisionW div 2
    playerY = player.y + CollisionH div 2
    elapsed = game.gameTicksElapsed()
    ringRadius = game.config.ffaRingRadiusAt(elapsed)
    safeRadius = max(0.0, float(ringRadius) - SafeMargin)
    (centerX, centerY) = ffaRingCenter()
  for spawn in game.medKitSpawns:
    if not spawn.present or
        not game.fovVisibleAt(playerIndex, spawn.x, spawn.y) or
        (requireSafe and
          distance(spawn.x, spawn.y, centerX, centerY) > safeRadius):
      continue
    let playerDistance = distance(
      playerX,
      playerY,
      spawn.x,
      spawn.y
    )
    if playerDistance < result and
        (not requireUncontested or
          not game.opponentCloser(
            playerIndex,
            spawn.x,
            spawn.y,
            playerDistance
          )):
      result = playerDistance

proc addOpportunity(
  counts: var OpportunityCounts,
  qualifies: bool,
  active: var bool
) =
  ## Adds one opportunity sample and window boundary.
  if qualifies:
    inc counts.ticks
    if not active:
      inc counts.windows
  active = qualifies

proc addReplay(
  totals: var MedKitTotals,
  replayPath, policyName: string
) {.raises: [Exception].} =
  ## Adds one replay's visible Hunter medkit opportunities to the totals.
  var (game, replay) = openReplay(replayPath)
  var
    index = -1
    counted = false
    wasAlive = false
    previousHp = 0
    damagedNearActive = false
    damagedSubmittedActive = false
    lowHealthNearActive = false
    damagedVisibleActive = false
    damagedRadiusActive: array[AuditRadii.len, bool]
    damagedSafeSubmittedActive = false
    fileDamagedVisible = false
    fileDamagedRadii: array[AuditRadii.len, bool]
    fileDamagedSafeSubmitted = false
    fileDamagedNear = false
    fileDamagedSubmitted = false
    fileLowHealthNear = false
  while replay.playing:
    replay.stepReplay(game)
    if index < 0:
      index = game.playerIndex(policyName)
      if index < 0:
        continue
      if not counted:
        inc totals.files
        counted = true
    let player = game.players[index]
    if wasAlive and player.alive and player.hp > previousHp:
      inc totals.pickupEvents
    wasAlive = player.alive
    previousHp = player.hp
    if not player.alive:
      damagedVisibleActive = false
      damagedRadiusActive = default(array[AuditRadii.len, bool])
      damagedSafeSubmittedActive = false
      damagedNearActive = false
      damagedSubmittedActive = false
      lowHealthNearActive = false
      continue
    let maxHp = game.config.maxHpFor(player.team, player.perks)
    if player.hp >= maxHp:
      damagedVisibleActive = false
      damagedRadiusActive = default(array[AuditRadii.len, bool])
      damagedSafeSubmittedActive = false
      damagedNearActive = false
      damagedSubmittedActive = false
      lowHealthNearActive = false
      continue
    inc totals.damagedTicks
    if player.hp < LowHealth:
      inc totals.lowHealthTicks
    discard game.refreshPlayerFov(index)
    let
      nearestVisible = game.nearestMedKit(index, false, false)
      nearestSafe = game.nearestMedKit(index, true, false)
      nearest = game.nearestMedKit(index, true, true)
    let damagedVisible = nearestVisible < Inf
    totals.damagedVisible.addOpportunity(
      damagedVisible,
      damagedVisibleActive
    )
    fileDamagedVisible = fileDamagedVisible or damagedVisible
    for i, radius in AuditRadii:
      let withinRadius = nearestVisible <= radius
      totals.damagedRadii[i].addOpportunity(
        withinRadius,
        damagedRadiusActive[i]
      )
      fileDamagedRadii[i] = fileDamagedRadii[i] or withinRadius
    let damagedSafeSubmitted = nearestSafe <= SubmittedRadius
    totals.damagedSafeSubmitted.addOpportunity(
      damagedSafeSubmitted,
      damagedSafeSubmittedActive
    )
    fileDamagedSafeSubmitted =
      fileDamagedSafeSubmitted or damagedSafeSubmitted
    let
      damagedNear = nearest <= NearRadius
      damagedSubmitted = nearest <= SubmittedRadius
      lowHealthNear = player.hp < LowHealth and damagedNear
    totals.damagedNear.addOpportunity(
      damagedNear,
      damagedNearActive
    )
    totals.damagedSubmitted.addOpportunity(
      damagedSubmitted,
      damagedSubmittedActive
    )
    totals.lowHealthNear.addOpportunity(
      lowHealthNear,
      lowHealthNearActive
    )
    fileDamagedNear = fileDamagedNear or damagedNear
    fileDamagedSubmitted = fileDamagedSubmitted or damagedSubmitted
    fileLowHealthNear = fileLowHealthNear or lowHealthNear
  if index < 0:
    return
  if fileDamagedVisible:
    inc totals.damagedVisible.files
  for i in 0 ..< AuditRadii.len:
    if fileDamagedRadii[i]:
      inc totals.damagedRadii[i].files
  if fileDamagedSafeSubmitted:
    inc totals.damagedSafeSubmitted.files
  if fileDamagedNear:
    inc totals.damagedNear.files
  if fileDamagedSubmitted:
    inc totals.damagedSubmitted.files
  if fileLowHealthNear:
    inc totals.lowHealthNear.files

proc printOpportunities(
  label: string,
  counts: OpportunityCounts
) =
  ## Prints one medkit opportunity class.
  echo label, "Ticks=", counts.ticks
  echo label, "Windows=", counts.windows
  echo label, "Files=", counts.files

proc summarize(
  replayDir, policyName: string
) {.raises: [Exception].} =
  ## Summarizes visible, safe, uncontested medkit opportunities.
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
  var totals: MedKitTotals
  for path in paths:
    totals.addReplay(path, policyName)
  echo "files=", totals.files
  echo "damagedTicks=", totals.damagedTicks
  echo "lowHealthTicks=", totals.lowHealthTicks
  echo "pickupEvents=", totals.pickupEvents
  printOpportunities("damagedVisible", totals.damagedVisible)
  for i, radius in AuditRadii:
    printOpportunities(
      "damagedWithin" & $int(radius),
      totals.damagedRadii[i]
    )
  printOpportunities(
    "damagedSafeWithin" & $int(SubmittedRadius),
    totals.damagedSafeSubmitted
  )
  printOpportunities("damagedNear", totals.damagedNear)
  printOpportunities("damagedSubmitted", totals.damagedSubmitted)
  printOpportunities("lowHealthNear", totals.lowHealthNear)

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_medkit_opportunities REPLAY_DIR POLICY_NAME"
  )

chdirGameDir()
summarize(
  absolutePath(paramStr(1)),
  paramStr(2)
)
