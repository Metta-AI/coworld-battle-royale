import
  std/[algorithm, json, math, os, strutils, tables],
  zippy/ziparchives,
  ../src/ctf/replays,
  ../src/ctf/sim,
  extract_events,
  toolutil

const
  AliveFlag = 1
  GrenadeFlag = 8
  SafeThrowMin = float(GrenadeBlastRadius + PlayerHalf + 12)

type
  BattleRoyaleError = object of CatchableError
  GrenadeTotals = object
    files: int
    carriedFiles: int
    pickupEvents: int
    throwEvents: int
    carriedTicks: int
    carriedSamples: int
    visibleSamples: int
    safeVisibleSamples: int
    safePairTicks: int

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

proc policySlot(extraction: ExtractResult, policyName: string): int =
  ## Returns one hosted policy's stable replay slot.
  for slot, name in extraction.slotAddress:
    if name == policyName:
      return slot
  raise newException(
    BattleRoyaleError,
    "hosted replay has no policy named: " & policyName
  )

proc frameForTick(extraction: ExtractResult, tick: int): int =
  ## Returns the frame index for a sim tick or negative one when absent.
  var
    low = 0
    high = extraction.frameCount - 1
  while low <= high:
    let
      middle = (low + high) div 2
      frameTick = extraction.frameTick(middle)
    if frameTick == tick:
      return middle
    if frameTick < tick:
      low = middle + 1
    else:
      high = middle - 1
  -1

proc distance(a, b: FrameSeat): float =
  ## Returns the Euclidean distance between two replay seats.
  hypot(float(a.x - b.x), float(a.y - b.y))

proc hasSafePair(
  extraction: ExtractResult,
  frame, policySlot: int
): bool =
  ## Reports whether one carried grenade could cover two living opponents.
  let me = extraction.frameSeat(frame, policySlot)
  for a in 0 ..< extraction.frameSlots:
    if a == policySlot:
      continue
    let first = extraction.frameSeat(frame, a)
    if (first.flags and AliveFlag) == 0 or
      distance(me, first) < SafeThrowMin or
      distance(me, first) > float(GrenadeMaxRange):
        continue
    for b in a + 1 ..< extraction.frameSlots:
      if b == policySlot:
        continue
      let second = extraction.frameSeat(frame, b)
      if (second.flags and AliveFlag) != 0 and
        distance(first, second) <=
          float(2 * (GrenadeBlastRadius + PlayerHalf)):
          return true
  false

proc addReplay(
  totals: var GrenadeTotals,
  artifactPath, replayPath, policyName: string
) {.raises: [Exception].} =
  ## Adds grenade carriage and visible-target windows from one hosted game.
  let extraction = extractEvents(loadReplay(replayPath), captureFrames = true)
  if not extraction.finished:
    raise newException(
      BattleRoyaleError,
      "hosted replay did not finish: " & replayPath
    )
  let slot = extraction.policySlot(policyName)
  inc totals.files
  var carried = false
  for frame in 0 ..< extraction.frameCount:
    let me = extraction.frameSeat(frame, slot)
    if (me.flags and AliveFlag) == 0 or
      (me.flags and GrenadeFlag) == 0:
        continue
    carried = true
    inc totals.carriedTicks
    if extraction.hasSafePair(frame, slot):
      inc totals.safePairTicks
  if carried:
    inc totals.carriedFiles
  for event in extraction.events:
    if event.source != slot or event.item != "grenade":
      continue
    if event.kind == Pickup:
      inc totals.pickupEvents
    elif event.kind == GrenadeThrow:
      inc totals.throwEvents
  for line in tickStream(artifactPath).splitLines():
    if line.len == 0:
      continue
    let sample = parseJson(line)
    if sample.hasKey("dead"):
      continue
    let frame = extraction.frameForTick(sample["t"].getInt())
    if frame < 0:
      continue
    let me = extraction.frameSeat(frame, slot)
    if (me.flags and GrenadeFlag) == 0:
      continue
    inc totals.carriedSamples
    if not sample.hasKey("eng"):
      continue
    inc totals.visibleSamples
    let targetDistance = sample["eng"].getFloat()
    if targetDistance >= SafeThrowMin and
      targetDistance <= float(GrenadeMaxRange):
        inc totals.safeVisibleSamples

proc summarize(
  artifactDir, replayDir, policyName: string
) {.raises: [Exception].} =
  ## Summarizes unused hosted FFA grenade opportunities.
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
  var totals: GrenadeTotals
  for path in paths:
    let episode = episodeId(path)
    if episode notin replays:
      raise newException(
        BattleRoyaleError,
        "artifact has no matching replay: " & episode
      )
    totals.addReplay(path, replays[episode], policyName)
  echo "files=", totals.files
  echo "carriedFiles=", totals.carriedFiles
  echo "pickupEvents=", totals.pickupEvents
  echo "throwEvents=", totals.throwEvents
  echo "carriedTicks=", totals.carriedTicks
  echo "carriedSamples=", totals.carriedSamples
  echo "visibleSamplesWhileCarried=", totals.visibleSamples
  echo "safeVisibleSamplesWhileCarried=", totals.safeVisibleSamples
  echo "safePairTicksWhileCarried=", totals.safePairTicks

if paramCount() != 3:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_grenade_opportunities " &
      "ARTIFACT_DIR REPLAY_DIR POLICY_NAME"
  )

chdirGameDir()
summarize(
  absolutePath(paramStr(1)),
  absolutePath(paramStr(2)),
  paramStr(3)
)
