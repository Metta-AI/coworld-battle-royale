import
  std/[algorithm, json, math, os, strformat, strutils, tables],
  ../src/ctf/[replays, sim],
  "extract_events"

const
  MaxLead = 16
  VelocityWindows = [1, 3, 6]
  MaxTargetRange = 1100.0
  MaxTargetHeadingError = 24
  MovingSpeed = 0.5

type
  TargetLeadError = object of CatchableError
  TargetEstimate = object
    slot: int
    distance: float
    headingError: int
  LeadStats = object
    samples: int
    movingSamples: int
    targetErrors: array[MaxLead + 1, float]
    releaseErrors: array[MaxLead + 1, float]
    movingTargetErrors: array[MaxLead + 1, float]
    movingReleaseErrors: array[MaxLead + 1, float]
  Summary = object
    replays: int
    triggers: int
    matchedTriggers: int
    models: array[VelocityWindows.len, LeadStats]

proc mean(total: float, count: int): float =
  ## Returns one arithmetic mean or zero for an empty sample.
  if count == 0:
    return 0.0
  total / count.float

proc bradsOf(x, y: float): int =
  ## Returns the game aim heading from one displacement.
  if abs(x) + abs(y) < 1e-6:
    return 0
  (int(round(arctan2(-y, x) * 128.0 / PI)) + 256) mod 256

proc bradsError(desired, current: int): int =
  ## Returns the absolute shortest heading error.
  abs((desired - current + 384) mod 256 - 128)

proc frameForTick(extraction: ExtractResult, tick: int): int =
  ## Returns the frame index for a sim tick or negative one when absent.
  var
    low = 0
    high = extraction.frameCount - 1
  while low <= high:
    let
      middle = (low + high) div 2
      frameTick = extraction.frameTick(middle)
    if frameTick == tick:
      return middle
    if frameTick < tick:
      low = middle + 1
    else:
      high = middle - 1
  -1

proc slotNames(extraction: ExtractResult): seq[string] =
  ## Returns replay-attributed player names for every seat.
  result = extraction.slotAddress
  let results = parseJson(extraction.resultsJson)
  for slot in 0 ..< result.len:
    if result[slot].len == 0:
      result[slot] = results["names"][slot].getStr()

proc inferTarget(
  extraction: ExtractResult,
  trigger: SimEvent
): TargetEstimate =
  ## Infers the live target closest to the locked trigger heading.
  result = TargetEstimate(
    slot: -1,
    distance: -1.0,
    headingError: high(int)
  )
  let frame = extraction.frameForTick(trigger.tick)
  if frame < 0:
    return
  for slot in 0 ..< extraction.frameSlots:
    if slot == trigger.source:
      continue
    let target = extraction.frameSeat(frame, slot)
    if (target.flags and 1) == 0:
      continue
    let
      dx = target.x.float - trigger.x
      dy = target.y.float - trigger.y
      distance = hypot(dx, dy)
      error = bradsError(bradsOf(dx, dy), trigger.headingBrads)
    if distance > MaxTargetRange:
      continue
    if error < result.headingError or
      (error == result.headingError and
        (result.distance < 0.0 or distance < result.distance)):
        result = TargetEstimate(
          slot: slot,
          distance: distance,
          headingError: error
        )
  if result.headingError > MaxTargetHeadingError:
    result.slot = -1

proc targetVelocity(
  extraction: ExtractResult,
  triggerFrame, targetSlot, window: int
): tuple[x, y: float, valid: bool] =
  ## Returns a replay-oracle average target velocity before the trigger.
  let earlierFrame = triggerFrame - window
  if earlierFrame < 0:
    return
  let
    current = extraction.frameSeat(triggerFrame, targetSlot)
    earlier = extraction.frameSeat(earlierFrame, targetSlot)
  if (current.flags and 1) == 0 or (earlier.flags and 1) == 0:
    return
  result.x = (current.x - earlier.x).float / window.float
  result.y = (current.y - earlier.y).float / window.float
  result.valid = true

proc addSample(
  stats: var LeadStats,
  sourceX, sourceY: float,
  shot: SimEvent,
  currentTarget, releaseTarget: FrameSeat,
  velocityX, velocityY: float
) =
  ## Adds one target-lead counterfactual for every tested horizon.
  let
    targetHeading = bradsOf(
      releaseTarget.x.float - sourceX,
      releaseTarget.y.float - sourceY
    )
    releaseHeading = bradsOf(
      releaseTarget.x.float - shot.x,
      releaseTarget.y.float - shot.y
    )
    speed = hypot(velocityX, velocityY)
    moving = speed >= MovingSpeed
  inc stats.samples
  if moving:
    inc stats.movingSamples
  for lead in 0 .. MaxLead:
    let predictedHeading = bradsOf(
      currentTarget.x.float + velocityX * lead.float - sourceX,
      currentTarget.y.float + velocityY * lead.float - sourceY
    )
    stats.targetErrors[lead] += bradsError(
      targetHeading,
      predictedHeading
    ).float
    stats.releaseErrors[lead] += bradsError(
      releaseHeading,
      predictedHeading
    ).float
    if moving:
      stats.movingTargetErrors[lead] += bradsError(
        targetHeading,
        predictedHeading
      ).float
      stats.movingReleaseErrors[lead] += bradsError(
        releaseHeading,
        predictedHeading
      ).float

proc addReplay(
  summary: var Summary,
  replayPath,
  policyName: string
) =
  ## Adds target-lead counterfactuals from one hash-validated replay.
  let extraction = extractEvents(loadReplay(replayPath), captureFrames = true)
  if not extraction.finished:
    raise newException(
      TargetLeadError,
      "hosted replay did not finish: " & replayPath
    )
  let names = extraction.slotNames()
  var shots: Table[int64, SimEvent]
  for event in extraction.events:
    if event.kind == Shot:
      shots[event.actionId] = event
  inc summary.replays
  for trigger in extraction.events:
    if trigger.kind != GunTrigger or
      trigger.source < 0 or
      trigger.source >= names.len or
      names[trigger.source] != policyName:
        continue
    inc summary.triggers
    if trigger.actionId notin shots:
      continue
    let
      target = extraction.inferTarget(trigger)
      shot = shots[trigger.actionId]
      triggerFrame = extraction.frameForTick(trigger.tick)
      releaseFrame = extraction.frameForTick(shot.tick)
    if target.slot < 0 or triggerFrame < 0 or releaseFrame < 0:
      continue
    let
      currentTarget = extraction.frameSeat(triggerFrame, target.slot)
      releaseTarget = extraction.frameSeat(releaseFrame, target.slot)
    if currentTarget.x == 0 and currentTarget.y == 0 or
      releaseTarget.x == 0 and releaseTarget.y == 0:
        continue
    var added = false
    for model, window in VelocityWindows:
      let velocity = extraction.targetVelocity(
        triggerFrame,
        target.slot,
        window
      )
      if not velocity.valid:
        continue
      summary.models[model].addSample(
        trigger.x,
        trigger.y,
        shot,
        currentTarget,
        releaseTarget,
        velocity.x,
        velocity.y
      )
      added = true
    if added:
      inc summary.matchedTriggers

proc replayPaths(paths: openArray[string]): seq[string] =
  ## Returns sorted replay files from explicit paths and directories.
  for path in paths:
    if fileExists(path):
      if path.endsWith(".replay"):
        result.add(path)
    elif dirExists(path):
      for child in walkDirRec(path):
        if child.endsWith(".replay"):
          result.add(child)
    else:
      raise newException(TargetLeadError, "path does not exist: " & path)
  result.sort()

proc bestLead(errors: array[MaxLead + 1, float], samples: int): int =
  ## Returns the tested horizon with the lowest mean error.
  result = 0
  for lead in 1 .. MaxLead:
    if errors[lead].mean(samples) < errors[result].mean(samples):
      result = lead

proc printModel(window: int, stats: LeadStats) =
  ## Prints one velocity model's horizon error table.
  let
    bestTarget = stats.targetErrors.bestLead(stats.samples)
    bestRelease = stats.releaseErrors.bestLead(stats.samples)
    bestMovingTarget = stats.movingTargetErrors.bestLead(stats.movingSamples)
    bestMovingRelease = stats.movingReleaseErrors.bestLead(stats.movingSamples)
  echo &"velocityWindow={window} samples={stats.samples} " &
    &"movingSamples={stats.movingSamples} bestTarget={bestTarget} " &
    &"bestRelease={bestRelease} bestMovingTarget={bestMovingTarget} " &
    &"bestMovingRelease={bestMovingRelease}"
  echo "lead targetError releaseError movingTargetError movingReleaseError"
  for lead in 0 .. MaxLead:
    echo &"{lead:>4} {stats.targetErrors[lead].mean(stats.samples):>11.4f} " &
      &"{stats.releaseErrors[lead].mean(stats.samples):>12.4f} " &
      &"{stats.movingTargetErrors[lead].mean(stats.movingSamples):>17.4f} " &
      &"{stats.movingReleaseErrors[lead].mean(stats.movingSamples):>18.4f}"

proc run() =
  ## Summarizes target-lead horizons from hosted replay files.
  let args = commandLineParams()
  if args.len < 2:
    raise newException(
      TargetLeadError,
      "usage: summarize_target_leads POLICY_NAME REPLAY_PATH..."
    )
  let
    policyName = args[0]
    paths = replayPaths(args[1 .. ^1])
  if paths.len == 0:
    raise newException(TargetLeadError, "no .replay files found")
  var summary: Summary
  for path in paths:
    summary.addReplay(path, policyName)
  echo &"policy={policyName} replays={summary.replays} " &
    &"triggers={summary.triggers} matchedTriggers={summary.matchedTriggers}"
  for model, window in VelocityWindows:
    printModel(window, summary.models[model])

run()
