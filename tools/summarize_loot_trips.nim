import
  std/[algorithm, json, os, strutils, tables],
  zippy/ziparchives

const
  TicksPerSec = 24.0

type
  BattleRoyaleError = object of CatchableError
  LootOutcome = enum
    LootSuccess, LootAbort, LootDeath, LootOpen
  LootRun = object
    ticks: int
    outcome: LootOutcome
  LootTotals = object
    files: int
    exactStarts: int
    aliveSamples: int
    unarmedSamples: int
    runs: seq[LootRun]

proc artifactFiles(zipPath: string): Table[string, string] {.raises: [
  IOError,
  OSError,
  ZippyError
].} =
  ## Returns the files stored in one player artifact.
  let reader = openZipArchive(zipPath)
  defer:
    reader.close()
  for path in reader.walkFiles:
    result[path] = reader.extractFile(path)

proc addRun(
  totals: var LootTotals,
  startTick: int,
  endTick: int,
  outcome: LootOutcome
) =
  ## Adds one sampled loot-trip run to the aggregate.
  totals.runs.add(LootRun(
    ticks: max(0, endTick - startTick),
    outcome: outcome
  ))

proc addArtifact(
  totals: var LootTotals,
  zipPath: string
) {.raises: [IOError, OSError, ValueError, ZippyError,
    BattleRoyaleError].} =
  ## Adds loot-trip samples and outcomes from one artifact.
  let files = artifactFiles(zipPath)
  if "summary.json" notin files or "ticks.jsonl" notin files:
    raise newException(
      BattleRoyaleError,
      "artifact lacks summary or ticks: " & zipPath
    )
  let summary = parseJson(files["summary.json"])
  inc totals.files
  totals.exactStarts += summary["lootTrips"].getInt()
  var
    inTrip = false
    startTick = 0
    lastTick = 0
    lastDead = false
    lastTier = 0
  for line in files["ticks.jsonl"].splitLines():
    if line.len == 0:
      continue
    let
      sample = parseJson(line)
      tick = sample["t"].getInt()
      dead = sample.hasKey("dead") and sample["dead"].getBool()
      tier = sample["tier"].getInt()
      isTrip = not dead and sample["obj"].getStr() == "loot_trip"
    lastTick = tick
    lastDead = dead
    lastTier = tier
    if not dead:
      inc totals.aliveSamples
      if tier == 0:
        inc totals.unarmedSamples
    if isTrip and not inTrip:
      inTrip = true
      startTick = tick
    elif not isTrip and inTrip:
      let outcome =
        if dead:
          LootDeath
        elif tier >= 1:
          LootSuccess
        else:
          LootAbort
      totals.addRun(startTick, tick, outcome)
      inTrip = false
  if inTrip:
    let outcome =
      if lastDead:
        LootDeath
      elif lastTier >= 1:
        LootSuccess
      else:
        LootOpen
    totals.addRun(startTick, lastTick, outcome)

proc percentile(sortedValues: seq[int], fraction: float): float =
  ## Returns a nearest-rank percentile from sorted integers.
  if sortedValues.len == 0:
    return 0.0
  let index = min(
    sortedValues.high,
    max(0, int(fraction * float(sortedValues.high) + 0.5))
  )
  float(sortedValues[index])

proc countAtLeast(runs: seq[LootRun], seconds: float): int =
  ## Counts sampled loot trips lasting at least the given seconds.
  let threshold = int(seconds * TicksPerSec)
  for run in runs:
    if run.ticks >= threshold:
      inc result

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_loot_trips ARTIFACT_DIRECTORY"
  )

let artifactDir = paramStr(1)
var totals: LootTotals
for path in walkDirRec(artifactDir):
  if path.endsWith(".zip"):
    totals.addArtifact(path)

if totals.files == 0:
  raise newException(
    BattleRoyaleError,
    "artifact directory contains no zip files: " & artifactDir
  )

var
  durations: seq[int]
  outcomes: array[LootOutcome, int]
  totalTicks = 0
for run in totals.runs:
  durations.add(run.ticks)
  totalTicks += run.ticks
  inc outcomes[run.outcome]
durations.sort()

echo "files=", totals.files
echo "exactStarts=", totals.exactStarts
echo "sampledRuns=", totals.runs.len
echo "successes=", outcomes[LootSuccess]
echo "aborts=", outcomes[LootAbort]
echo "deaths=", outcomes[LootDeath]
echo "open=", outcomes[LootOpen]
echo "unarmedSampleFrac=", float(totals.unarmedSamples) /
  float(max(1, totals.aliveSamples))
echo "meanDurationSec=", float(totalTicks) /
  float(max(1, totals.runs.len)) / TicksPerSec
echo "medianDurationSec=", percentile(durations, 0.5) / TicksPerSec
echo "p90DurationSec=", percentile(durations, 0.9) / TicksPerSec
echo "maxDurationSec=", percentile(durations, 1.0) / TicksPerSec
echo "atLeast10Sec=", totals.runs.countAtLeast(10.0)
echo "atLeast20Sec=", totals.runs.countAtLeast(20.0)
echo "atLeast29Sec=", totals.runs.countAtLeast(29.0)
