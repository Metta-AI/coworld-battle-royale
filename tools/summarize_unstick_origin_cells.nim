import
  std/[algorithm, json, os, strutils, tables],
  zippy/ziparchives,
  ../src/ctf/sim,
  toolutil

const
  NavCell = 8

type
  BattleRoyaleError = object of CatchableError
  OriginTotals = object
    files: int
    unstickFiles: int
    blockedOriginFiles: int
    unstickSamples: int
    blockedOriginSamples: int
    actualBlockedSamples: int

proc episodeId(path: string): string =
  ## Returns the hosted episode ID encoded in an artifact filename.
  let
    name = path.extractFilename()
    marker = name.find("-policy_agent_")
  if marker < 0:
    return name.changeFileExt("")
  name[0 ..< marker]

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

proc replayPaths(replayDir: string): Table[string, string] =
  ## Maps hosted episode IDs to downloaded replay paths.
  for path in walkDirRec(replayDir):
    if path.endsWith(".replay") or path.endsWith(".bitreplay"):
      result[path.extractFilename().changeFileExt("")] = path

proc addArtifact(
  totals: var OriginTotals,
  zipPath: string,
  replayPath: string
) {.raises: [Exception].} =
  ## Adds unstick samples whose coarse origin nav cell is blocked.
  let (game, replay) = openReplay(replayPath)
  discard replay
  inc totals.files
  var
    hasUnstick = false
    hasBlockedOrigin = false
  for line in tickStream(zipPath).splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    if sample["act"].getStr() != "ring_unstick":
      continue
    let
      x = sample["x"].getInt()
      y = sample["y"].getInt()
      cellX = x div NavCell * NavCell + NavCell div 2
      cellY = y div NavCell * NavCell + NavCell div 2
    hasUnstick = true
    inc totals.unstickSamples
    if not game.canOccupy(x, y):
      inc totals.actualBlockedSamples
    if not game.canOccupy(cellX, cellY):
      hasBlockedOrigin = true
      inc totals.blockedOriginSamples
  if hasUnstick:
    inc totals.unstickFiles
  if hasBlockedOrigin:
    inc totals.blockedOriginFiles

proc summarize(
  artifactDir: string,
  replayDir: string
) {.raises: [Exception].} =
  ## Summarizes the coarse-origin rejection in hosted unstick samples.
  let replays = replayPaths(replayDir)
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
  var totals: OriginTotals
  for path in paths:
    let episode = episodeId(path)
    if episode notin replays:
      raise newException(
        BattleRoyaleError,
        "artifact has no matching replay: " & episode
      )
    totals.addArtifact(path, replays[episode])
  echo "files=", totals.files
  echo "unstickFiles=", totals.unstickFiles
  echo "blockedOriginFiles=", totals.blockedOriginFiles
  echo "unstickSamples=", totals.unstickSamples
  echo "blockedOriginSamples=", totals.blockedOriginSamples
  echo "actualBlockedSamples=", totals.actualBlockedSamples

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_unstick_origin_cells ARTIFACT_DIR REPLAY_DIR"
  )

chdirGameDir()
summarize(
  absolutePath(paramStr(1)),
  absolutePath(paramStr(2))
)
