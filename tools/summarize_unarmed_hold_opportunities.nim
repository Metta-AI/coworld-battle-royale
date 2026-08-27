import
  std/[algorithm, json, os, strutils],
  zippy/ziparchives

type
  BattleRoyaleError = object of CatchableError
  HoldTotals = object
    files: int
    samples: int
    windows: int
    opportunityFiles: int
    armedHoldSamples: int

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
  ## Adds submitted unarmed fallback-hold opportunities from one artifact.
  var
    active = false
    fileQualifies = false
  inc totals.files
  for line in tickStream(zipPath).splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    if sample.hasKey("dead") or not sample.hasKey("tier") or
        not sample.hasKey("engageReason") or not sample.hasKey("band"):
      active = false
      continue
    let
      tier = sample["tier"].getInt()
      reason = sample["engageReason"].getStr()
      band = sample["band"].getStr()
      qualifies = tier == 0 and reason == "hold" and band == "0.850"
    if qualifies:
      inc totals.samples
      if not active:
        inc totals.windows
      fileQualifies = true
    elif tier > 0 and reason == "hold" and band == "0.850":
      inc totals.armedHoldSamples
    active = qualifies
  if fileQualifies:
    inc totals.opportunityFiles

proc summarize(artifactDir: string) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Summarizes the submitted Hunter's unarmed fallback-hold coverage.
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
  echo "unarmedHoldSamples=", totals.samples
  echo "unarmedHoldWindows=", totals.windows
  echo "unarmedHoldFiles=", totals.opportunityFiles
  echo "armedHoldSamples=", totals.armedHoldSamples

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_unarmed_hold_opportunities ARTIFACT_DIRECTORY"
  )

summarize(absolutePath(paramStr(1)))
