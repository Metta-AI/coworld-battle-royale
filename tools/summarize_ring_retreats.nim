import
  std/[algorithm, json, math, os, strformat, strutils],
  zippy/ziparchives

const
  RingDamageInterval = 48
  TargetFps = 120
  WindowSec = 10

type
  BattleRoyaleError = object of CatchableError
  DamageSample = object
    tick: int
    hp: int
  EventData = object
    damages: seq[DamageSample]
    endTick: int
  TickSample = object
    tick: int
    x: float
    y: float
    action: string
    objective: string
    visible: int
    tier: int
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
  ## Parses damage events and the terminal artifact tick.
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
    of "game_end":
      result.endTick = event["t"].getInt()
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
      tier: sample["tier"].getInt()
    ))

proc terminalRingRun(events: EventData): seq[DamageSample] =
  ## Returns a fatal unit-damage cadence consistent with the ring.
  var fatal = -1
  for i in countdown(events.damages.high, 0):
    let damage = events.damages[i]
    if damage.hp == 0 or
        (damage.hp == 1 and events.endTick - damage.tick in 0 .. 48):
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
  if result.len < 3:
    result.setLen(0)

proc distance(a, b: TickSample): float =
  ## Returns Euclidean distance between two sampled positions.
  hypot(b.x - a.x, b.y - a.y)

proc retreatStats(
  samples: seq[TickSample],
  fatalTick: int
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
    if sample.action notin ["retreat_ring", "ring_unstick"]:
      continue
    retreatSamples.add(sample)
    inc result.samples
    if sample.action == "ring_unstick":
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
  for i in 1 ..< retreatSamples.len:
    let step = distance(retreatSamples[i - 1], retreatSamples[i])
    result.path += step
    inc result.steps
    if step < 0.8:
      inc result.zeroSteps

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
      run = terminalRingRun(parseEventData(streams.events))
    if run.len == 0:
      continue
    let stats = retreatStats(parseTickSamples(streams.ticks), run[^1].tick)
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
    echo &"episode={episodeId(path)} ringHits={run.len} " &
      &"fatalTick={run[^1].tick} retreatSamples={stats.samples} " &
      &"unstickSamples={stats.unstickSamples} " &
      &"path={stats.path:.1f} displacement={stats.displacement:.1f} " &
      &"zeroStepPct={percent(stats.zeroSteps, stats.steps):.1f} " &
      &"switches={stats.switches} visible={stats.visible} " &
      &"unarmed={stats.unarmed}"
  echo "files=", paths.len
  echo "ringLikeDeaths=", ringDeaths
  if ringDeaths > 0:
    echo &"meanRetreatSamples={float(total.samples) / float(ringDeaths):.1f}"
    echo &"unstickPct={percent(total.unstickSamples, total.samples):.1f}"
    echo &"meanPath={total.path / float(ringDeaths):.1f}"
    echo &"meanDisplacement={total.displacement / float(ringDeaths):.1f}"
    echo &"zeroStepPct={percent(total.zeroSteps, total.steps):.1f}"
    echo &"visiblePct={percent(total.visible, total.samples):.1f}"
    echo &"unarmedPct={percent(total.unarmed, total.samples):.1f}"
    echo &"meanSwitches={float(total.switches) / float(ringDeaths):.1f}"

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_ring_retreats ARTIFACT_DIRECTORY"
  )

summarize(absolutePath(paramStr(1)))
