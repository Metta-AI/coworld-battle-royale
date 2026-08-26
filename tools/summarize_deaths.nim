import
  std/[algorithm, json, os, strformat, strutils, tables],
  zippy/ziparchives

type
  BattleRoyaleError = object of CatchableError
  DamageSample = object
    tick: int
    hp: int
    amount: int
  EventData = object
    damages: seq[DamageSample]
    deathTick: int
  TickSample = object
    tick: int
    hp: int
    tier: int
    visible: int
    objective: string
    action: string
  DeathCause = enum
    UnknownCause,
    RingCause,
    TwoDamageCause,
    MidDamageCause,
    FourDamageCause,
    HeavyDamageCause

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

proc parseEvents(text: string): EventData {.raises: [
  IOError,
  OSError,
  ValueError
].} =
  ## Parses self-damage and the policy's terminal death tick.
  result.deathTick = -1
  for line in text.splitLines():
    if line.len == 0:
      continue
    let event = parseJson(line)
    case event["e"].getStr()
    of "damage":
      let
        hp = event["hp"].getInt()
        previous = event["from"].getInt()
      result.damages.add(DamageSample(
        tick: event["t"].getInt(),
        hp: hp,
        amount: previous - hp
      ))
    of "death":
      result.deathTick = event["t"].getInt()
    else:
      discard

proc parseTicks(text: string): seq[TickSample] {.raises: [
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
      hp: sample["hp"].getInt(),
      tier: sample["tier"].getInt(),
      visible: sample["vis"].getInt(),
      objective: sample["obj"].getStr(),
      action: sample["act"].getStr()
    ))

proc lastLiveSample(
  samples: seq[TickSample],
  deathTick: int
): TickSample =
  ## Returns the last live policy sample at or before death.
  for i in countdown(samples.high, 0):
    if samples[i].tick <= deathTick and samples[i].hp > 0:
      return samples[i]

proc ringFatal(events: EventData): bool =
  ## Detects a terminal one-damage ring cadence.
  if events.deathTick < 0 or events.damages.len == 0:
    return false
  let last = events.damages[^1]
  if last.hp == 1 and
      last.amount == 1 and
      events.deathTick - last.tick in 40 .. 56:
    return true
  if events.damages.len < 3:
    return false
  let start = events.damages.len - 3
  for i in start ..< events.damages.len:
    if events.damages[i].amount != 1:
      return false
    if i > start and
        events.damages[i].tick - events.damages[i - 1].tick != 48:
      return false
  true

proc deathCause(events: EventData): DeathCause =
  ## Classifies the terminal damage amount without guessing a weapon.
  if events.ringFatal():
    return RingCause
  if events.deathTick < 0 or events.damages.len == 0:
    return UnknownCause
  let last = events.damages[^1]
  if events.deathTick - last.tick > 60:
    return UnknownCause
  case last.amount
  of 2:
    TwoDamageCause
  of 3:
    MidDamageCause
  of 4:
    FourDamageCause
  of 5:
    HeavyDamageCause
  else:
    UnknownCause

proc causeName(cause: DeathCause): string =
  ## Returns a stable terminal-cause label.
  case cause
  of UnknownCause:
    "unknown"
  of RingCause:
    "ring"
  of TwoDamageCause:
    "damage_2"
  of MidDamageCause:
    "damage_3"
  of FourDamageCause:
    "damage_4"
  of HeavyDamageCause:
    "damage_5"

proc episodeId(path: string): string =
  ## Returns the hosted episode ID from an artifact filename.
  let
    name = path.extractFilename()
    marker = name.find("-policy_agent_")
  if marker < 0:
    return name.changeFileExt("")
  name[0 ..< marker]

proc summarize(artifactDir: string) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Summarizes terminal cause and policy state for hosted deaths.
  var paths: seq[string]
  for path in walkDirRec(artifactDir):
    if path.endsWith(".zip"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "artifact directory contains no zip files: " & artifactDir
    )
  var
    deaths = 0
    causes = initCountTable[string]()
    tiers = initCountTable[int]()
    visibleDeaths = 0
  for path in paths:
    let
      streams = artifactFiles(path)
      events = parseEvents(streams.events)
    if events.deathTick < 0:
      continue
    let
      sample = lastLiveSample(parseTicks(streams.ticks), events.deathTick)
      cause = events.deathCause()
      lastDamage =
        if events.damages.len > 0: events.damages[^1].amount else: 0
      damageGap =
        if events.damages.len > 0:
          events.deathTick - events.damages[^1].tick
        else:
          -1
    inc deaths
    causes.inc(cause.causeName())
    tiers.inc(sample.tier)
    if sample.visible > 0:
      inc visibleDeaths
    echo &"episode={episodeId(path)} deathTick={events.deathTick} " &
      &"cause={cause.causeName()} lastDamage={lastDamage} " &
      &"damageGap={damageGap} tier={sample.tier} " &
      &"visible={sample.visible} objective={sample.objective} " &
      &"action={sample.action}"
  echo "files=", paths.len
  echo "deaths=", deaths
  for cause, count in causes.pairs:
    echo "cause ", cause, "=", count
  for tier, count in tiers.pairs:
    echo "tier ", tier, "=", count
  echo "visibleDeaths=", visibleDeaths

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_deaths ARTIFACT_DIRECTORY"
  )

summarize(absolutePath(paramStr(1)))
