import
  std/[algorithm, math, os, sequtils, strformat, strutils, tables],
  ../src/ctf/[replays, sim],
  extract_events

const
  TicksPerSec = 24
  HistorySeconds = [1, 3, 5, 8]

type
  BattleRoyaleError = object of CatchableError
  HistoryStats = object
    samples: int
    distance: float
    closing: int
    enemyDistance: float
    enemySamples: int
    enemyNear100: int
    enemyNear200: int
    enemyNear300: int
  MedKitStats = object
    episodes: int
    woundedEpisodes: int
    heals: int
    healedHp: int
    preHp: CountTable[int]
    phases: CountTable[string]
    tiers: CountTable[int]
    damageAge: CountTable[string]
    positions: CountTable[string]
    histories: array[HistorySeconds.len, HistoryStats]

proc mean(total: float, count: int): float =
  ## Returns a floating-point mean or zero for no samples.
  if count == 0:
    return 0.0
  total / count.float

proc percent(part, whole: int): float =
  ## Returns a percentage or zero for no samples.
  100.0 * mean(part.float, whole)

proc phaseText(relativeTick: int): string =
  ## Returns the strategy phase containing one playing-relative tick.
  if relativeTick < 30 * TicksPerSec:
    "0-30s"
  elif relativeTick < 60 * TicksPerSec:
    "30-60s"
  elif relativeTick < 120 * TicksPerSec:
    "60-120s"
  else:
    "120s+"

proc ageText(age: int): string =
  ## Returns a compact time-since-damage bucket.
  if age < 0:
    "unknown"
  elif age < TicksPerSec:
    "<1s"
  elif age < 3 * TicksPerSec:
    "1-3s"
  elif age < 6 * TicksPerSec:
    "3-6s"
  else:
    "6s+"

proc playingTick(events: openArray[SimEvent]): int =
  ## Returns the tick at which active play began.
  for event in events:
    if event.kind == PhaseChange and event.weapon == "playing":
      return event.tick
  0

proc isGun(item: string): bool =
  ## Reports whether one pickup token is an FFA gun.
  item in ["low gun", "mid gun", "heavy gun"]

proc gunTier(item: string): int =
  ## Returns the tier represented by one FFA gun pickup token.
  case item
  of "low gun":
    1
  of "mid gun":
    2
  of "heavy gun":
    3
  else:
    0

proc frameAtOrBefore(extraction: ExtractResult, tick: int): int =
  ## Returns the latest captured frame at or before one tick.
  var
    low = 0
    high = extraction.frameCount - 1
  result = -1
  while low <= high:
    let
      middle = (low + high) div 2
      frameTick = extraction.frameTick(middle)
    if frameTick <= tick:
      result = middle
      low = middle + 1
    else:
      high = middle - 1

proc distance(seat: FrameSeat, x, y: float): float =
  ## Returns center-to-point distance for one captured player state.
  hypot(
    seat.x.float + CollisionW.float / 2.0 - x,
    seat.y.float + CollisionH.float / 2.0 - y
  )

proc nearestEnemyDistance(
  extraction: ExtractResult,
  frame,
  slot: int
): float =
  ## Returns the nearest living opponent distance in one captured frame.
  result = Inf
  let own = extraction.frameSeat(frame, slot)
  if (own.flags and 1) == 0:
    return
  for otherSlot in 0 ..< extraction.frameSlots:
    if otherSlot == slot:
      continue
    let other = extraction.frameSeat(frame, otherSlot)
    if (other.flags and 1) == 0:
      continue
    result = min(
      result,
      hypot(
        float(other.x - own.x),
        float(other.y - own.y)
      )
    )

proc addHistory(
  history: var HistoryStats,
  extraction: ExtractResult,
  event: SimEvent,
  seconds: int
) =
  ## Adds one pre-heal trajectory and threat-context sample.
  let frame = extraction.frameAtOrBefore(
    event.tick - seconds * TicksPerSec
  )
  if frame < 0 or event.source < 0 or
      event.source >= extraction.frameSlots:
    return
  let seat = extraction.frameSeat(frame, event.source)
  if (seat.flags and 1) == 0:
    return
  let
    pickupDistance = seat.distance(event.x, event.y)
    laterFrame = extraction.frameAtOrBefore(
      min(event.tick, extraction.frameTick(frame) + TicksPerSec)
    )
  inc history.samples
  history.distance += pickupDistance
  if laterFrame > frame:
    let later = extraction.frameSeat(laterFrame, event.source)
    if (later.flags and 1) != 0 and
        pickupDistance - later.distance(event.x, event.y) >= 12.0:
      inc history.closing
  let enemyDistance = extraction.nearestEnemyDistance(frame, event.source)
  if enemyDistance < Inf:
    inc history.enemySamples
    history.enemyDistance += enemyDistance
    if enemyDistance <= 100.0:
      inc history.enemyNear100
    if enemyDistance <= 200.0:
      inc history.enemyNear200
    if enemyDistance <= 300.0:
      inc history.enemyNear300

proc addReplay(
  stats: var Table[string, MedKitStats],
  replayPath: string,
  targets: seq[string]
) =
  ## Adds medkit decisions from one hash-validated hosted replay.
  let
    data = loadReplay(replayPath)
    extraction = extractEvents(data, captureFrames = true)
  if not extraction.finished:
    raise newException(
      BattleRoyaleError,
      "hosted replay did not finish: " & replayPath
    )
  let startTick = extraction.events.playingTick()
  var
    selected = newSeq[bool](extraction.slotAddress.len)
    wounded = newSeq[bool](extraction.slotAddress.len)
    tiers = newSeq[int](extraction.slotAddress.len)
    lastDamage = newSeqWith(extraction.slotAddress.len, -1)
  for slot, name in extraction.slotAddress:
    if name in targets:
      selected[slot] = true
      var player = stats.mgetOrPut(name, MedKitStats())
      inc player.episodes
      stats[name] = player
  for event in extraction.events:
    if event.kind == Pickup and event.source >= 0 and
        event.source < tiers.len and event.item.isGun():
      tiers[event.source] = max(tiers[event.source], event.item.gunTier())
    if event.kind == Damage and event.target >= 0 and
        event.target < lastDamage.len:
      lastDamage[event.target] = event.tick
      wounded[event.target] = true
    if event.kind != Heal or event.source < 0 or
        event.source >= selected.len or not selected[event.source]:
      continue
    let name = extraction.slotAddress[event.source]
    var player = stats[name]
    inc player.heals
    player.healedHp += event.amount
    player.preHp.inc(max(0, event.hp - event.amount))
    player.phases.inc(phaseText(max(0, event.tick - startTick)))
    player.tiers.inc(tiers[event.source])
    player.damageAge.inc(ageText(
      if lastDamage[event.source] < 0:
        -1
      else:
        event.tick - lastDamage[event.source]
    ))
    player.positions.inc(
      $int(round(event.x)) & "," & $int(round(event.y))
    )
    for i, seconds in HistorySeconds:
      player.histories[i].addHistory(
        extraction,
        event,
        seconds
      )
    stats[name] = player
  for slot, name in extraction.slotAddress:
    if selected[slot] and wounded[slot]:
      var player = stats[name]
      inc player.woundedEpisodes
      stats[name] = player

proc sortedCounts[T](counts: CountTable[T]): seq[(T, int)] =
  ## Returns count-table entries in key order.
  for key, value in counts:
    result.add((key, value))
  result.sort(proc(a, b: (T, int)): int = cmp(a[0], b[0]))

proc countText[T](counts: CountTable[T]): string =
  ## Returns sorted key-count pairs on one line.
  var parts: seq[string]
  for pair in counts.sortedCounts():
    parts.add($pair[0] & ":" & $pair[1])
  if parts.len == 0:
    "none"
  else:
    parts.join(",")

proc printStats(name: string, stats: MedKitStats) =
  ## Prints one policy's medkit decision profile.
  echo name
  echo &"  episodes={stats.episodes} woundedEpisodes={stats.woundedEpisodes}" &
    &" heals={stats.heals} healedHp={stats.healedHp}" &
    &" healsPerEpisode={mean(stats.heals.float, stats.episodes):.3f}" &
    &" hpPerEpisode={mean(stats.healedHp.float, stats.episodes):.3f}"
  echo "  preHp=", stats.preHp.countText()
  echo "  phases=", stats.phases.countText()
  echo "  weaponTier=", stats.tiers.countText()
  echo "  sinceDamage=", stats.damageAge.countText()
  echo "  pickupPositions=", stats.positions.countText()
  for i, seconds in HistorySeconds:
    let history = stats.histories[i]
    echo &"  at-{seconds}s samples={history.samples}" &
      &" distance={mean(history.distance, history.samples):.2f}" &
      &" closing={percent(history.closing, history.samples):.2f}%" &
      &" enemyDistance=" &
      &"{mean(history.enemyDistance, history.enemySamples):.2f}" &
      &" near100={percent(history.enemyNear100, history.enemySamples):.2f}%" &
      &" near200={percent(history.enemyNear200, history.enemySamples):.2f}%" &
      &" near300={percent(history.enemyNear300, history.enemySamples):.2f}%"

proc summarize(replayDir: string, targets: seq[string]) =
  ## Summarizes exact target policies across one hosted replay corpus.
  var paths: seq[string]
  for path in walkDirRec(replayDir):
    if path.endsWith(".replay") or path.endsWith(".bitreplay"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "replay directory contains no replays: " & replayDir
    )
  var stats: Table[string, MedKitStats]
  for path in paths:
    stats.addReplay(path, targets)
  for target in targets:
    if target in stats:
      printStats(target, stats[target])
    else:
      echo target, "\n  episodes=0"

if paramCount() < 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_medkit_logic REPLAY_DIR POLICY_NAME [POLICY_NAME ...]"
  )

summarize(
  absolutePath(paramStr(1)),
  commandLineParams()[1 .. ^1]
)
