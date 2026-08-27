import
  std/[algorithm, math, os, strutils],
  ../src/ctf/sim,
  toolutil

const
  PursuitMinHp = 6
  SupportRadius = 300.0

type
  BattleRoyaleError = object of CatchableError
  OpportunityCounts = object
    ticks: int
    windows: int
    files: int
  PursuitTotals = object
    files: int
    armedTicks: int
    visibleTicks: int
    submittedTicks: int
    supportedWeak: OpportunityCounts
    equalSolo: OpportunityCounts
    strongSolo: OpportunityCounts
    broad: OpportunityCounts

proc distance(x1, y1, x2, y2: int): float =
  ## Returns Euclidean distance between two replay positions.
  hypot(float(x1 - x2), float(y1 - y2))

proc playerIndex(game: SimServer, policyName: string): int =
  ## Returns the joined player index for one hosted league identity.
  for i, player in game.players:
    if player.address == policyName:
      return i
  -1

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
  totals: var PursuitTotals,
  replayPath, policyName: string
) {.raises: [Exception].} =
  ## Adds one replay's visible Hunter pursuit counterfactuals.
  var (game, replay) = openReplay(replayPath)
  var
    index = -1
    supportedWeakActive = false
    equalSoloActive = false
    strongSoloActive = false
    broadActive = false
    fileSupportedWeak = false
    fileEqualSolo = false
    fileStrongSolo = false
    fileBroad = false
  inc totals.files
  while replay.playing:
    replay.stepReplay(game)
    if index < 0:
      index = game.playerIndex(policyName)
      if index < 0:
        continue
    let player = game.players[index]
    if not player.alive or player.weaponTier == FfaWeaponUnarmed or
        player.hp < PursuitMinHp:
      supportedWeakActive = false
      equalSoloActive = false
      strongSoloActive = false
      broadActive = false
      continue
    inc totals.armedTicks
    discard game.refreshPlayerFov(index)
    var
      targetIndex = -1
      targetDistance = Inf
    for i, target in game.players:
      if i == index or not target.alive or
          not game.playerVisibleTo(index, i):
        continue
      let d = distance(player.x, player.y, target.x, target.y)
      if d < targetDistance:
        targetIndex = i
        targetDistance = d
    if targetIndex < 0:
      supportedWeakActive = false
      equalSoloActive = false
      strongSoloActive = false
      broadActive = false
      continue
    inc totals.visibleTicks
    let
      target = game.players[targetIndex]
      (centerX, centerY) = ffaRingCenter()
      ringRadius = game.config.ffaRingRadiusAt(game.gameTicksElapsed())
      targetSafe = distance(
        target.x,
        target.y,
        centerX,
        centerY
      ) <= float(max(1, ringRadius))
    var supported = false
    for i, other in game.players:
      if i == index or i == targetIndex or not other.alive or
          not game.playerVisibleTo(index, i):
        continue
      if distance(other.x, other.y, target.x, target.y) <= SupportRadius:
        supported = true
        break
    let
      weaker = target.weaponTier == FfaWeaponUnarmed or
        target.hp < player.hp
      submitted = targetSafe and weaker and not supported
      supportedWeak = targetSafe and weaker and supported
      equalSolo = targetSafe and not supported and
        target.hp == player.hp
      strongSolo = targetSafe and not supported and
        target.hp > player.hp
      broad = targetSafe and not submitted
    if submitted:
      inc totals.submittedTicks
    totals.supportedWeak.addOpportunity(
      supportedWeak,
      supportedWeakActive
    )
    totals.equalSolo.addOpportunity(equalSolo, equalSoloActive)
    totals.strongSolo.addOpportunity(strongSolo, strongSoloActive)
    totals.broad.addOpportunity(broad, broadActive)
    fileSupportedWeak = fileSupportedWeak or supportedWeak
    fileEqualSolo = fileEqualSolo or equalSolo
    fileStrongSolo = fileStrongSolo or strongSolo
    fileBroad = fileBroad or broad
  if index < 0:
    raise newException(
      BattleRoyaleError,
      "hosted replay has no player named: " & policyName
    )
  if fileSupportedWeak:
    inc totals.supportedWeak.files
  if fileEqualSolo:
    inc totals.equalSolo.files
  if fileStrongSolo:
    inc totals.strongSolo.files
  if fileBroad:
    inc totals.broad.files

proc printOpportunities(
  label: string,
  counts: OpportunityCounts
) =
  ## Prints one pursuit opportunity class.
  echo label, "Ticks=", counts.ticks
  echo label, "Windows=", counts.windows
  echo label, "Files=", counts.files

proc summarize(
  replayDir, policyName: string
) {.raises: [Exception].} =
  ## Summarizes submitted and counterfactual Hunter pursuit gates.
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
  var totals: PursuitTotals
  for path in paths:
    totals.addReplay(path, policyName)
  echo "files=", totals.files
  echo "armedTicks=", totals.armedTicks
  echo "visibleTicks=", totals.visibleTicks
  echo "submittedTicks=", totals.submittedTicks
  printOpportunities("supportedWeak", totals.supportedWeak)
  printOpportunities("equalSolo", totals.equalSolo)
  printOpportunities("strongSolo", totals.strongSolo)
  printOpportunities("broad", totals.broad)

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_pursuit_opportunities REPLAY_DIR POLICY_NAME"
  )

chdirGameDir()
summarize(
  absolutePath(paramStr(1)),
  paramStr(2)
)
