import
  std/[algorithm, json, math, os, strformat, strutils, tables],
  ../src/ctf/replays,
  ../src/ctf/sim,
  extract_events

const
  TargetFps = 24.0

type
  BattleRoyaleError = object of CatchableError
  MarginBand = enum
    MarginOutside,
    Margin0To40,
    Margin40To80,
    Margin80To120,
    Margin120To160,
    Margin160To240,
    Margin240Plus
  MotionStats = object
    frames: int
    steps: int
    path: float
    inward: int
    outward: int
    stationary: int
    slack: float
  PlayerStats = object
    episodes: int
    bands: array[MarginBand, MotionStats]
  SlotTrack = object
    previous: FrameSeat
    previousTick: int
    valid: bool

proc mean(total: float, count: int): float =
  ## Returns a floating-point mean or zero for no samples.
  if count == 0:
    return 0.0
  total / count.float

proc percent(part, whole: int): float =
  ## Returns a percentage or zero for no samples.
  100.0 * mean(part.float, whole)

proc bandFor(slack: float): MarginBand =
  ## Maps ring slack in pixels to one stable behavior band.
  if slack < 0.0:
    MarginOutside
  elif slack < 40.0:
    Margin0To40
  elif slack < 80.0:
    Margin40To80
  elif slack < 120.0:
    Margin80To120
  elif slack < 160.0:
    Margin120To160
  elif slack < 240.0:
    Margin160To240
  else:
    Margin240Plus

proc bandName(band: MarginBand): string =
  ## Returns the stable report name for one margin band.
  case band
  of MarginOutside:
    "outside"
  of Margin0To40:
    "0-40"
  of Margin40To80:
    "40-80"
  of Margin80To120:
    "80-120"
  of Margin120To160:
    "120-160"
  of Margin160To240:
    "160-240"
  of Margin240Plus:
    "240+"

proc targetsFrom(value: string): seq[string] =
  ## Parses comma-separated exact player names, with star selecting all.
  for part in value.split(','):
    let name = part.strip()
    if name.len > 0:
      result.add(name)

proc wanted(name: string, targets: seq[string]): bool =
  ## Reports whether one exact player name is selected.
  if targets.len == 1 and targets[0] == "*":
    return true
  for target in targets:
    if name == target:
      return true

proc playingTick(events: openArray[SimEvent]): int =
  ## Returns the tick at which active play began.
  for event in events:
    if event.kind == PhaseChange and event.weapon == "playing":
      return event.tick
  0

proc addMotion(
  stats: var MotionStats,
  seat: FrameSeat,
  radial,
  slack: float,
  tick: int,
  track: SlotTrack
) =
  ## Adds one living frame to a ring-margin motion profile.
  inc stats.frames
  stats.slack += slack
  if not track.valid or tick != track.previousTick + 1:
    return
  let
    center = ffaRingCenter()
    moveX = seat.x.float - track.previous.x.float
    moveY = seat.y.float - track.previous.y.float
    distance = hypot(moveX, moveY)
    previousRadial = hypot(
      track.previous.x.float - center.x.float,
      track.previous.y.float - center.y.float
    )
    inward = previousRadial - radial
  inc stats.steps
  stats.path += distance
  if distance < 0.5:
    inc stats.stationary
  if inward > 0.05:
    inc stats.inward
  elif inward < -0.05:
    inc stats.outward

proc addReplay(
  stats: var Table[string, PlayerStats],
  replayPath: string,
  targets: seq[string]
) =
  ## Adds exact target-player ring motion from one hosted replay.
  let
    data = loadReplay(replayPath)
    extraction = extractEvents(data, captureFrames = true)
    results = parseJson(extraction.resultsJson)
  if not extraction.finished:
    raise newException(
      BattleRoyaleError,
      "hosted replay did not finish: " & replayPath
    )
  var
    config = defaultGameConfig()
    names = extraction.slotAddress
  config.update(data.configJson)
  for slot in 0 ..< names.len:
    if names[slot].len == 0:
      names[slot] = results["names"][slot].getStr()
  var
    selected = newSeq[bool](names.len)
    tracks = newSeq[SlotTrack](names.len)
  for slot, name in names:
    if name.wanted(targets):
      selected[slot] = true
      inc stats.mgetOrPut(name, PlayerStats()).episodes
  let startTick = extraction.events.playingTick()
  for frame in 0 ..< extraction.frameCount:
    let
      tick = extraction.frameTick(frame)
      relativeTick = tick - startTick
    if relativeTick < 0:
      continue
    let ringRadius = config.ffaRingRadiusAt(relativeTick).float
    for slot, name in names:
      if not selected[slot]:
        continue
      let seat = extraction.frameSeat(frame, slot)
      if (seat.flags and 1) == 0:
        tracks[slot].valid = false
        continue
      let
        center = ffaRingCenter()
        radial = hypot(
          seat.x.float - center.x.float,
          seat.y.float - center.y.float
        )
        slack = ringRadius - radial
        band = slack.bandFor()
      stats[name].bands[band].addMotion(
        seat,
        radial,
        slack,
        tick,
        tracks[slot]
      )
      tracks[slot].previous = seat
      tracks[slot].previousTick = tick
      tracks[slot].valid = true

proc printStats(stats: Table[string, PlayerStats]) =
  ## Prints deterministic ring-margin movement profiles.
  var names: seq[string]
  for name in stats.keys:
    names.add(name)
  names.sort()
  for name in names:
    let player = stats[name]
    echo &"PLAYER\t{name}\tepisodes={player.episodes}"
    for band in MarginBand:
      let motion = player.bands[band]
      echo &"RING\t{name}\tmargin={band.bandName()}" &
        &"\tseconds={motion.frames.float / TargetFps:.2f}" &
        &"\tmeanSlack={mean(motion.slack, motion.frames):.2f}" &
        &"\tpathPerSec={mean(motion.path, motion.steps) * TargetFps:.2f}" &
        &"\tstationaryPct={percent(motion.stationary, motion.steps):.2f}" &
        &"\tinwardPct={percent(motion.inward, motion.steps):.2f}" &
        &"\toutwardPct={percent(motion.outward, motion.steps):.2f}"

proc summarize(replayDir: string, targets: seq[string]) =
  ## Summarizes ring-margin logic across one hosted replay corpus.
  var paths: seq[string]
  for kind, path in walkDir(replayDir):
    if kind == pcFile and path.toLowerAscii().endsWith(".replay"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "no replay files found in " & replayDir
    )
  var stats: Table[string, PlayerStats]
  for i, path in paths:
    stats.addReplay(path, targets)
    if (i + 1) mod 20 == 0:
      stderr.writeLine("processed=", i + 1, "/", paths.len)
  echo "replays=", paths.len
  stats.printStats()

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_ring_logic REPLAY_DIR PLAYER_NAMES"
  )

summarize(
  absolutePath(paramStr(1)),
  targetsFrom(paramStr(2))
)
