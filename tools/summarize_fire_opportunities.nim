import
  std/[algorithm, json, os, strutils],
  zippy/ziparchives

const
  CurrentRange = 520.0
  LowGunRange = 700.0
  FullGunRange = 1050.0

type
  BattleRoyaleError = object of CatchableError
  FireTotals = object
    files: int
    visibleSamples: int
    armedVisibleSamples: int
    lowLongSamples: int
    midHeavyLongSamples: int
    midHeavyLongFiles: int
    midHeavy520To700: int
    midHeavy700To900: int
    midHeavy900To1050: int
    midHeavyBeyond1050: int

proc tickStream(zipPath: string): string {.raises: [
  IOError,
  OSError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Loads the sampled tick stream from one hosted artifact.
  let reader = openZipArchive(zipPath)
  defer:
    reader.close()
  for path in reader.walkFiles:
    if path == "ticks.jsonl":
      return reader.extractFile(path)
  raise newException(
    BattleRoyaleError,
    "artifact has no ticks.jsonl: " & zipPath
  )

proc addArtifact(
  totals: var FireTotals,
  zipPath: string
) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Adds visible armed-target distance samples from one artifact.
  inc totals.files
  var hasMidHeavyLong = false
  for line in tickStream(zipPath).splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    if sample.hasKey("dead") or not sample.hasKey("eng"):
      continue
    let
      tier = sample["tier"].getInt()
      distance = sample["eng"].getFloat()
    inc totals.visibleSamples
    if tier <= 0:
      continue
    inc totals.armedVisibleSamples
    if tier == 1 and distance > CurrentRange and distance <= LowGunRange:
      inc totals.lowLongSamples
    if tier < 2 or distance <= CurrentRange:
      continue
    if distance <= FullGunRange:
      inc totals.midHeavyLongSamples
      hasMidHeavyLong = true
      if distance <= LowGunRange:
        inc totals.midHeavy520To700
      elif distance <= 900.0:
        inc totals.midHeavy700To900
      else:
        inc totals.midHeavy900To1050
    else:
      inc totals.midHeavyBeyond1050
  if hasMidHeavyLong:
    inc totals.midHeavyLongFiles

proc summarize(artifactDir: string) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Summarizes unused hosted FFA gun-range opportunities.
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
  var totals: FireTotals
  for path in paths:
    totals.addArtifact(path)
  echo "files=", totals.files
  echo "visibleSamples=", totals.visibleSamples
  echo "armedVisibleSamples=", totals.armedVisibleSamples
  echo "lowLongSamples=", totals.lowLongSamples
  echo "midHeavyLongSamples=", totals.midHeavyLongSamples
  echo "midHeavyLongFiles=", totals.midHeavyLongFiles
  echo "midHeavy520To700=", totals.midHeavy520To700
  echo "midHeavy700To900=", totals.midHeavy700To900
  echo "midHeavy900To1050=", totals.midHeavy900To1050
  echo "midHeavyBeyond1050=", totals.midHeavyBeyond1050

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_fire_opportunities ARTIFACT_DIRECTORY"
  )

summarize(absolutePath(paramStr(1)))
