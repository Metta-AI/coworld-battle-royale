import
  std/[algorithm, json, math, os, strutils],
  zippy/ziparchives

type
  BattleRoyaleError = object of CatchableError
  HoldTotals = object
    files: int
    holdFiles: int
    samples: int
    windows: int
    zeroMaskSamples: int
    transitions: int
    stationaryTransitions: int
    slowTransitions: int
    stepDistance: float

proc tickStream(zipPath: string): string {.raises: [
  IOError,
  OSError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Loads the sampled tick stream from one hosted policy artifact.
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
  totals: var HoldTotals,
  zipPath: string
) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Adds passive-band input and displacement samples from one artifact.
  var
    active = false
    fileActive = false
    previousX = 0
    previousY = 0
  inc totals.files
  for line in tickStream(zipPath).splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    let qualifies = not sample.hasKey("dead") and
      sample.hasKey("obj") and sample["obj"].getStr() == "passive_band" and
      sample.hasKey("act") and sample["act"].getStr() == "hold_band"
    if not qualifies:
      active = false
      continue
    let
      x = sample["x"].getInt()
      y = sample["y"].getInt()
    inc totals.samples
    if sample["mask"].getInt() == 0:
      inc totals.zeroMaskSamples
    if not active:
      inc totals.windows
    else:
      let movement = hypot(
        float(x - previousX),
        float(y - previousY)
      )
      inc totals.transitions
      totals.stepDistance += movement
      if movement < 1.0:
        inc totals.stationaryTransitions
      if movement < 12.0:
        inc totals.slowTransitions
    active = true
    fileActive = true
    previousX = x
    previousY = y
  if fileActive:
    inc totals.holdFiles

proc percent(numerator, denominator: int): float =
  ## Returns a guarded percentage for two integer counters.
  if denominator <= 0:
    return 0.0
  100.0 * float(numerator) / float(denominator)

proc summarize(artifactDir: string) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Summarizes passive-band immobility in hosted policy artifacts.
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
  var totals: HoldTotals
  for path in paths:
    totals.addArtifact(path)
  echo "files=", totals.files
  echo "holdFiles=", totals.holdFiles
  echo "holdSamples=", totals.samples
  echo "holdWindows=", totals.windows
  echo "zeroMaskSamples=", totals.zeroMaskSamples
  echo "zeroMaskPct=", totals.zeroMaskSamples.percent(totals.samples)
  echo "holdTransitions=", totals.transitions
  echo "stationaryTransitions=", totals.stationaryTransitions
  echo "stationaryPct=",
    totals.stationaryTransitions.percent(totals.transitions)
  echo "slowTransitions=", totals.slowTransitions
  echo "slowPct=", totals.slowTransitions.percent(totals.transitions)
  echo "meanStepDistance=", totals.stepDistance /
    float(max(1, totals.transitions))

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_hold_motion ARTIFACT_DIRECTORY"
  )

summarize(absolutePath(paramStr(1)))
