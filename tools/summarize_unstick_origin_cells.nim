import
  std/[algorithm, json, math, os, strformat, strutils, tables],
  zippy/ziparchives,
  ../src/ctf/sim,
  toolutil

const
  NavCell = 8
  PolicyFps = 24

type
  BattleRoyaleError = object of CatchableError
  Direction = tuple[x, y: float]
  RaySelection = object
    octant: int
    fallback: bool
  OriginTotals = object
    files: int
    unstickFiles: int
    blockedOriginFiles: int
    unstickSamples: int
    blockedOriginSamples: int
    actualBlockedSamples: int
    anyOpen8Samples: int
    anyOpen16Samples: int
    anyOpen32Samples: int
    upOpen8Samples: int
    upOpen16Samples: int
    upOpen32Samples: int
    open32Octants: array[8, int]
    selectorDiffSamples: int
    coarseFallbackSamples: int
    fineFallbackSamples: int

const
  Octants = [
    (-1.0, -1.0),
    (0.0, -1.0),
    (1.0, -1.0),
    (-1.0, 0.0),
    (1.0, 0.0),
    (-1.0, 1.0),
    (0.0, 1.0),
    (1.0, 1.0)
  ]
  OctantNames = ["ul", "u", "ur", "l", "r", "dl", "d", "dr"]

proc episodeId(path: string): string =
  ## Returns the hosted episode ID encoded in an artifact filename.
  let
    name = path.extractFilename()
    marker = name.find("-policy_agent_")
  if marker < 0:
    return name.changeFileExt("")
  name[0 ..< marker]

proc policySlot(path: string): int =
  ## Returns the policy seat encoded after the artifact filename marker.
  let
    name = path.extractFilename()
    marker = name.find("-policy_agent_")
  if marker < 0:
    return 0
  let start = marker + "-policy_agent_".len
  var finish = start
  while finish < name.len and name[finish] in {'0' .. '9'}:
    inc finish
  if finish == start:
    return 0
  parseInt(name[start ..< finish])

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

proc actualRayClear(
  game: SimServer,
  x, y: int,
  direction: tuple[x, y: float],
  probe: int
): bool =
  ## Checks actual player-footprint clearance along one movement octant.
  let scale = hypot(direction.x, direction.y)
  for step in 1 .. probe:
    let
      px = x + int(round(direction.x / scale * float(step)))
      py = y + int(round(direction.y / scale * float(step)))
    if not game.canOccupy(px, py):
      return false
  true

proc coarseRayClear(
  game: SimServer,
  x, y: int,
  direction: Direction,
  probe: int
): bool =
  ## Checks clearance with the submitted eight-pixel nav-grid semantics.
  let
    scale = hypot(direction.x, direction.y)
    steps = probe div 4 + 1
  for step in 0 .. steps:
    let
      distance = float(probe * step) / float(steps)
      px = x + int(round(direction.x / scale * distance))
      py = y + int(round(direction.y / scale * distance))
      cellX = px div NavCell * NavCell + NavCell div 2
      cellY = py div NavCell * NavCell + NavCell div 2
    if not game.canOccupy(cellX, cellY):
      return false
  true

proc normalized(direction: Direction): Direction =
  ## Returns a unit direction or zero when its input has no magnitude.
  let scale = hypot(direction.x, direction.y)
  if scale == 0.0:
    return (0.0, 0.0)
  (direction.x / scale, direction.y / scale)

proc octant(direction: Direction): int =
  ## Quantizes one vector to the policy's clockwise movement octants.
  var angle = arctan2(direction.y, direction.x)
  if angle < 0.0:
    angle += 2.0 * PI
  int(floor((angle + PI / 8.0) / (PI / 4.0))) mod 8

proc selectRay(
  game: SimServer,
  x, y, tick, slot: int,
  fine: bool
): RaySelection =
  ## Replays the submitted or pixel-accurate unstick direction selector.
  let
    center = ffaRingCenter()
    inward = normalized((float(center.x - x), float(center.y - y)))
  var side: Direction = (-inward.y, inward.x)
  if (tick div PolicyFps + slot) mod 2 != 0:
    side = (-side.x, -side.y)
  let candidates: array[5, Direction] = [
    side,
    (-side.x, -side.y),
    normalized((side.x + inward.x * 0.5,
      side.y + inward.y * 0.5)),
    normalized((-side.x + inward.x * 0.5,
      -side.y + inward.y * 0.5)),
    inward
  ]
  for direction in candidates:
    let clear =
      if fine:
        game.actualRayClear(x, y, direction, 32)
      else:
        game.coarseRayClear(x, y, direction, 32)
    if clear:
      return RaySelection(octant: octant(direction), fallback: false)
  RaySelection(octant: 6, fallback: true)

proc hasOpenOctant(game: SimServer, x, y, probe: int): bool =
  ## Returns true when any real movement octant clears the probe distance.
  for direction in Octants:
    if game.actualRayClear(x, y, direction, probe):
      return true
  false

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
    episode = OriginTotals()
    slot = policySlot(zipPath)
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
      tick = sample["t"].getInt()
      coarse = game.selectRay(x, y, tick, slot, false)
      fine = game.selectRay(x, y, tick, slot, true)
    hasUnstick = true
    inc totals.unstickSamples
    inc episode.unstickSamples
    if not game.canOccupy(x, y):
      inc totals.actualBlockedSamples
      inc episode.actualBlockedSamples
    if not game.canOccupy(cellX, cellY):
      hasBlockedOrigin = true
      inc totals.blockedOriginSamples
      inc episode.blockedOriginSamples
    if game.hasOpenOctant(x, y, 8):
      inc totals.anyOpen8Samples
      inc episode.anyOpen8Samples
    if game.hasOpenOctant(x, y, 16):
      inc totals.anyOpen16Samples
      inc episode.anyOpen16Samples
    if game.hasOpenOctant(x, y, 32):
      inc totals.anyOpen32Samples
      inc episode.anyOpen32Samples
    if game.actualRayClear(x, y, (0.0, -1.0), 8):
      inc totals.upOpen8Samples
      inc episode.upOpen8Samples
    if game.actualRayClear(x, y, (0.0, -1.0), 16):
      inc totals.upOpen16Samples
      inc episode.upOpen16Samples
    if game.actualRayClear(x, y, (0.0, -1.0), 32):
      inc totals.upOpen32Samples
      inc episode.upOpen32Samples
    for i, direction in Octants:
      if game.actualRayClear(x, y, direction, 32):
        inc totals.open32Octants[i]
        inc episode.open32Octants[i]
    if coarse.octant != fine.octant:
      inc totals.selectorDiffSamples
      inc episode.selectorDiffSamples
    if coarse.fallback:
      inc totals.coarseFallbackSamples
      inc episode.coarseFallbackSamples
    if fine.fallback:
      inc totals.fineFallbackSamples
      inc episode.fineFallbackSamples
  if hasUnstick:
    inc totals.unstickFiles
    echo &"episode={episodeId(zipPath)} samples={episode.unstickSamples} " &
      &"blockedOrigin={episode.blockedOriginSamples} " &
      &"anyOpen8={episode.anyOpen8Samples} " &
      &"anyOpen16={episode.anyOpen16Samples} " &
      &"anyOpen32={episode.anyOpen32Samples} " &
      &"upOpen8={episode.upOpen8Samples} " &
      &"upOpen16={episode.upOpen16Samples} " &
      &"upOpen32={episode.upOpen32Samples} " &
      &"open32={episode.open32Octants} " &
      &"selectorDiff={episode.selectorDiffSamples} " &
      &"coarseFallback={episode.coarseFallbackSamples} " &
      &"fineFallback={episode.fineFallbackSamples}"
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
  echo "anyOpen8Samples=", totals.anyOpen8Samples
  echo "anyOpen16Samples=", totals.anyOpen16Samples
  echo "anyOpen32Samples=", totals.anyOpen32Samples
  echo "upOpen8Samples=", totals.upOpen8Samples
  echo "upOpen16Samples=", totals.upOpen16Samples
  echo "upOpen32Samples=", totals.upOpen32Samples
  for i, name in OctantNames:
    echo "open32", name, "Samples=", totals.open32Octants[i]
  echo "selectorDiffSamples=", totals.selectorDiffSamples
  echo "coarseFallbackSamples=", totals.coarseFallbackSamples
  echo "fineFallbackSamples=", totals.fineFallbackSamples

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
