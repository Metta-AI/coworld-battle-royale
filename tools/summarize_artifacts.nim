import
  std/[algorithm, json, os, strutils, tables],
  zippy/ziparchives

type
  BattleRoyaleError = object of CatchableError
  ArtifactTotals = object
    files: int
    ticks: int
    armedFraction: float
    lootTrips: int
    samples: int
    visibleSamples: int
    heavyStrafeSamples: int
    armedHeavyStrafeSamples: int
    events: CountTable[string]
    objectives: CountTable[string]
    actions: CountTable[string]
    reasons: CountTable[string]
    bands: CountTable[string]
    tiers: CountTable[string]

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

proc addCounts(
  target: var CountTable[string],
  source: JsonNode
) =
  ## Adds a JSON count object to an aggregate count table.
  for key, value in source:
    target.inc(key, value.getInt())

proc addArtifact(
  totals: var ArtifactTotals,
  zipPath: string
) {.raises: [IOError, OSError, ValueError, ZippyError,
    BattleRoyaleError].} =
  ## Adds one hosted player artifact to aggregate totals.
  let files = artifactFiles(zipPath)
  if "summary.json" notin files or "ticks.jsonl" notin files:
    raise newException(
      BattleRoyaleError,
      "artifact lacks summary or ticks: " & zipPath
    )
  let summary = parseJson(files["summary.json"])
  inc totals.files
  totals.ticks += summary["lastTick"].getInt()
  totals.armedFraction += summary["armedFrac"].getFloat()
  totals.lootTrips += summary["lootTrips"].getInt()
  totals.events.addCounts(summary["events"])
  totals.objectives.addCounts(summary["objectiveTicks"])
  totals.actions.addCounts(summary["actionTicks"])
  for line in files["ticks.jsonl"].splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    inc totals.samples
    if sample["vis"].getInt() > 0:
      inc totals.visibleSamples
    if sample["engageReason"].getStr() == "heavy_threat_lateral":
      inc totals.heavyStrafeSamples
      if sample["tier"].getInt() > 0:
        inc totals.armedHeavyStrafeSamples
    totals.reasons.inc(sample["engageReason"].getStr())
    totals.bands.inc(sample["band"].getStr())
    totals.tiers.inc($sample["tier"].getInt())

proc printCounts(label: string, counts: CountTable[string]) =
  ## Prints one aggregate count table in stable key order.
  var keys: seq[string]
  for key in counts.keys:
    keys.add(key)
  keys.sort()
  for key in keys:
    echo label, " ", key, "=", counts[key]

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_artifacts ARTIFACT_DIRECTORY"
  )

let artifactDir = paramStr(1)
var totals: ArtifactTotals
for path in walkDirRec(artifactDir):
  if path.endsWith(".zip"):
    totals.addArtifact(path)

if totals.files == 0:
  raise newException(
    BattleRoyaleError,
    "artifact directory contains no zip files: " & artifactDir
  )

echo "files=", totals.files
echo "meanLastTick=", totals.ticks div totals.files
echo "meanArmedFrac=", totals.armedFraction / float(totals.files)
echo "meanLootTrips=", float(totals.lootTrips) / float(totals.files)
echo "visibleSampleFrac=", float(totals.visibleSamples) /
  float(max(1, totals.samples))
echo "heavyStrafeSamples=", totals.heavyStrafeSamples
echo "armedHeavyStrafeSamples=", totals.armedHeavyStrafeSamples
echo "unarmedHeavyStrafeSamples=",
  totals.heavyStrafeSamples - totals.armedHeavyStrafeSamples
printCounts("event", totals.events)
printCounts("objective", totals.objectives)
printCounts("action", totals.actions)
printCounts("reason", totals.reasons)
printCounts("band", totals.bands)
printCounts("tier", totals.tiers)
