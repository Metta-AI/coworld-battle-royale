import
  std/[algorithm, json, math, os, strformat, strutils],
  zippy/ziparchives

const
  RingDamageInterval = 48
  TargetFps = 24
  WindowSec = 10

type
  BattleRoyaleError = object of CatchableError
  DamageSample = object
    tick: int
    hp: int
  EventData = object
    damages: seq[DamageSample]
    deathTick: int
    centerX: float
    centerY: float
  TickSample = object
    tick: int
    x: float
    y: float
    action: string
    objective: string
    visible: int
    tier: int
    safeRadius: float
  RetreatStats = object
    samples: int
    unstickSamples: int
    path: float
    displacement: float
    zeroSteps: int
    steps: int
    switches: int
    visible: int
    unarmed: int
    outwardSteps: int
    radialProgress: float
    startSlack: float
    endSlack: float

proc artifactFiles(zipPath: string): tuple[
    events: string, ticks: string] {.raises: [
    IOError,
    OSError,
    ZippyError,
    BattleRoyaleError
].} =
  ## Loads the event and tick streams from one hosted artifact.
  let reader = openZipArchive(zipPath)
  defer:
    reader.close()
  var
    hasEvents = false
    hasTicks = false
  for path in reader.walkFiles:
    case path
    of "events.jsonl":
      result.events = reader.extractFile(path)
      hasEvents = true
    of "ticks.jsonl":
      result.ticks = reader.extractFile(path)
      hasTicks = true
    else:
      discard
  if not hasEvents or not hasTicks:
    raise newException(
      BattleRoyaleError,
      "artifact lacks event or tick stream: " & zipPath
    )

proc parseEventData(text: string): EventData {.raises: [
  IOError,
  OSError,
  ValueError
].} =
  ## Parses damage events, map center, and terminal death tick.
  result.deathTick = -1
  for line in text.splitLines():
    if line.len == 0:
      continue
    let event = parseJson(line)
    case event["e"].getStr()
    of "damage":
      result.damages.add(DamageSample(
        tick: event["t"].getInt(),
        hp: event["hp"].getInt()
      ))
    of "death":
      result.deathTick = event["t"].getInt()
    of "game_params":
      result.centerX = float(event["mapW"].getInt()) / 2.0
      result.centerY = float(event["mapH"].getInt()) / 2.0
    else:
      discard

proc parseTickSamples(text: string): seq[TickSample] {.raises: [
  IOError,
  OSError,
  ValueError
].} =
  ## Parses sampled policy state in file order.
  for line in text.splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    result.add(TickSample(
      tick: sample["t"].getInt(),
      x: sample["x"].getFloat(),
      y: sample["y"].getFloat(),
      action: sample["act"].getStr(),
      objective: sample["obj"].getStr(),
      visible: sample["vis"].getInt(),
      tier: sample["tier"].getInt(),
      safeRadius: sample["safeR"].getFloat()
    ))

proc terminalRingRun(events: EventData): seq[DamageSample] =
  ## Returns a fatal unit-damage cadence consistent with the ring.
  if events.deathTick < 0:
    return
  var fatal = -1
  for i in countdown(events.damages.high, 0):
    let damage = events.damages[i]
    if damage.tick > events.deathTick:
      continue
    if damage.hp == 0 or
        (damage.hp == 1 and
          events.deathTick - damage.tick in 40 .. 56):
      fatal = i
      break
  if fatal < 0:
    return
  result.add(events.damages[fatal])
  var i = fatal
  while i > 0:
    let
      current = events.damages[i]
      previous = events.damages[i - 1]
    if current.tick - previous.tick != RingDamageInterval or
        previous.hp != current.hp + 1:
      break
    result.add(previous)
    dec i
  result.reverse()
  let terminalRingTick = result[^1].hp == 1 and
    events.deathTick - result[^1].tick in 40 .. 56
  if result.len < 3 and not terminalRingTick:
    result.setLen(0)

proc distance(a, b: TickSample): float =
  ## Returns Euclidean distance between two sampled positions.
  hypot(b.x - a.x, b.y - a.y)

proc centerDistance(sample: TickSample, centerX, centerY: float): float =
  ## Returns a sample's radial distance from the map and ring center.
  hypot(sample.x - centerX, sample.y - centerY)

proc retreatStats(
  samples: seq[TickSample],
  fatalTick: int,
  centerX, centerY: float
): RetreatStats =
  ## Summarizes retreat motion in the ten seconds before a ring-like death.
  let startTick = fatalTick - WindowSec * TargetFps
  var
    retreatSamples: seq[TickSample]
    previousObjective = ""
  for sample in samples:
    if sample.tick < startTick or sample.tick > fatalTick:
      continue
    if previousObjective.len > 0 and
        sample.objective != previousObjective:
      inc result.switches
    previousObjective = sample.objective
    if sample.action notin [
      "retreat_ring",
      "ring_unstick",
      "ring_unstick_flip"
    ]:
      continue
    retreatSamples.add(sample)
    inc result.samples
    if sample.action in ["ring_unstick", "ring_unstick_flip"]:
      inc result.unstickSamples
    if sample.visible > 0:
      inc result.visible
    if sample.tier == 0:
      inc result.unarmed
  if retreatSamples.len < 2:
    return
  result.displacement = distance(
    retreatSamples[0],
    retreatSamples[^1]
  )
  result.radialProgress = retreatSamples[0].centerDistance(
    centerX,
    centerY
  ) - retreatSamples[^1].centerDistance(centerX, centerY)
  result.startSlack = retreatSamples[0].safeRadius -
    retreatSamples[0].centerDistance(centerX, centerY)
  result.endSlack = retreatSamples[^1].safeRadius -
    retreatSamples[^1].centerDistance(centerX, centerY)
  for i in 1 ..< retreatSamples.len:
    let step = distance(retreatSamples[i - 1], retreatSamples[i])
    result.path += step
    inc result.steps
    if step < 0.8:
      inc result.zeroSteps
    if retreatSamples[i].centerDistance(centerX, centerY) >
        retreatSamples[i - 1].centerDistance(centerX, centerY) + 0.8:
      inc result.outwardSteps

proc episodeId(path: string): string =
  ## Returns the hosted episode id encoded in an artifact filename.
  let name = path.extractFilename()
  let marker = name.find("-policy_agent_")
  if marker < 0:
    return name.changeFileExt("")
  name[0 ..< marker]

proc percent(part, whole: int): float =
  ## Returns one percentage or zero for an empty denominator.
  if whole == 0:
    return 0.0
  100.0 * float(part) / float(whole)

proc summarize(artifactDir: string) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Prints per-episode and aggregate fatal ring-retreat motion.
  var
    paths: seq[string]
    total = RetreatStats()
    ringDeaths = 0
  for path in walkDirRec(artifactDir):
    if path.endsWith(".zip"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "artifact directory contains no zip files: " & artifactDir
    )
  for path in paths:
    let
      streams = artifactFiles(path)
      events = parseEventData(streams.events)
      run = terminalRingRun(events)
    if run.len == 0:
      continue
    let stats = retreatStats(
      parseTickSamples(streams.ticks),
      events.deathTick,
      events.centerX,
      events.centerY
    )
    inc ringDeaths
    total.samples += stats.samples
    total.unstickSamples += stats.unstickSamples
    total.path += stats.path
    total.displacement += stats.displacement
    total.zeroSteps += stats.zeroSteps
    total.steps += stats.steps
    total.switches += stats.switches
    total.visible += stats.visible
    total.unarmed += stats.unarmed
    total.outwardSteps += stats.outwardSteps
    total.radialProgress += stats.radialProgress
    total.startSlack += stats.startSlack
    total.endSlack += stats.endSlack
    echo &"episode={episodeId(path)} ringHits={run.len} " &
      &"fatalTick={events.deathTick} retreatSamples={stats.samples} " &
      &"unstickSamples={stats.unstickSamples} " &
      &"path={stats.path:.1f} displacement={stats.displacement:.1f} " &
      &"radialProgress={stats.radialProgress:.1f} " &
      &"slack={stats.startSlack:.1f}->{stats.endSlack:.1f} " &
      &"zeroStepPct={percent(stats.zeroSteps, stats.steps):.1f} " &
      &"outwardStepPct={percent(stats.outwardSteps, stats.steps):.1f} " &
      &"switches={stats.switches} visible={stats.visible} " &
      &"unarmed={stats.unarmed}"
  echo "files=", paths.len
  echo "ringLikeDeaths=", ringDeaths
  if ringDeaths > 0:
    echo &"meanRetreatSamples={float(total.samples) / float(ringDeaths):.1f}"
    echo &"unstickPct={percent(total.unstickSamples, total.samples):.1f}"
    echo &"meanPath={total.path / float(ringDeaths):.1f}"
    echo &"meanDisplacement={total.displacement / float(ringDeaths):.1f}"
    echo &"meanRadialProgress={total.radialProgress / float(ringDeaths):.1f}"
    echo &"meanStartSlack={total.startSlack / float(ringDeaths):.1f}"
    echo &"meanEndSlack={total.endSlack / float(ringDeaths):.1f}"
    echo &"zeroStepPct={percent(total.zeroSteps, total.steps):.1f}"
    echo &"outwardStepPct={percent(total.outwardSteps, total.steps):.1f}"
    echo &"visiblePct={percent(total.visible, total.samples):.1f}"
    echo &"unarmedPct={percent(total.unarmed, total.samples):.1f}"
    echo &"meanSwitches={float(total.switches) / float(ringDeaths):.1f}"

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_ring_retreats ARTIFACT_DIRECTORY"
  )

summarize(absolutePath(paramStr(1)))
