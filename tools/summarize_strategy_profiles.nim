import
  std/[algorithm, json, math, os, sequtils, strformat, strutils, tables],
  ../src/ctf/replays,
  ../src/ctf/sim,
  extract_events

const
  TicksPerSec = 24.0
  SnapshotTicks = [5 * 24, 15 * 24, 30 * 24]

type
  BattleRoyaleError = object of CatchableError
  StrategyPhase = enum
    PhaseOpening, PhaseEarly, PhaseMiddle, PhaseLate
  MotionStats = object
    frames: int
    movedFrames: int
    stationaryFrames: int
    pathDistance: float
    radialDistance: float
    ringRatio: float
    ringMargin: float
    outsideFrames: int
    inwardFrames: int
    outwardFrames: int
    orbitClockwiseFrames: int
    orbitCounterFrames: int
    angularDistance: float
    aimTurnFrames: int
    aimDistance: int
    opponentSamples: int
    opponentDistance: float
    opponentNear100: int
    opponentNear200: int
    opponentNear300: int
    towardOpponentFrames: int
    awayOpponentFrames: int
    strafeDistance: float
  PlayerStats = object
    episodes: int
    wins: int
    score: int
    kills: int
    deaths: int
    damage: int
    survivalTicks: int
    places: int
    placeSamples: int
    shots: int
    hits: int
    triggers: int
    damageDealt: int
    damageReceived: int
    ringDamage: int
    shieldBlocked: int
    heals: int
    grenadeThrows: int
    sprayTicks: int
    shouts: int
    firstGunTicks: int
    firstGunEpisodes: int
    firstGunRadius: float
    secondGunTicks: int
    secondGunEpisodes: int
    pickups: CountTable[string]
    firstGuns: CountTable[string]
    pickupOrders: CountTable[string]
    fatalCauses: CountTable[string]
    rangeShots: array[6, int]
    rangeHits: array[6, int]
    phases: array[StrategyPhase, array[2, MotionStats]]
    snapshotDistance: array[3, float]
    snapshotInward: array[3, float]
    snapshotAim: array[3, int]
    snapshotSamples: array[3, int]
  SlotTrack = object
    previous: FrameSeat
    previousTick: int
    previousValid: bool
    start: FrameSeat
    startRadial: float
    startAim: int
    startValid: bool
    sampled: array[3, bool]

proc mean(total: float, count: int): float =
  ## Returns a floating-point mean or zero for no samples.
  if count == 0:
    return 0.0
  total / count.float

proc mean(total, count: int): float =
  ## Returns an integer-total mean or zero for no samples.
  mean(total.float, count)

proc percent(part, whole: int): float =
  ## Returns a percentage or zero for no samples.
  100.0 * mean(part, whole)

proc phaseOf(relativeTick: int): StrategyPhase =
  ## Maps a playing-relative tick to a strategy phase.
  if relativeTick < 30 * 24:
    PhaseOpening
  elif relativeTick < 60 * 24:
    PhaseEarly
  elif relativeTick < 120 * 24:
    PhaseMiddle
  else:
    PhaseLate

proc phaseText(phase: StrategyPhase): string =
  ## Returns a compact strategy-phase label.
  case phase
  of PhaseOpening:
    "0-30s"
  of PhaseEarly:
    "30-60s"
  of PhaseMiddle:
    "60-120s"
  of PhaseLate:
    "120s+"

proc stateText(index: int): string =
  ## Returns the weapon-state label for one state index.
  if index == 0: "unarmed" else: "armed"

proc isGun(item: string): bool =
  ## Reports whether an item token is an FFA gun pickup.
  item in ["low gun", "mid gun", "heavy gun"]

proc gunTier(item: string): int =
  ## Returns the tier encoded by an FFA gun pickup token.
  case item
  of "low gun":
    1
  of "mid gun":
    2
  of "heavy gun":
    3
  else:
    0

proc rangeBin(distance: float): int =
  ## Returns a 100-pixel range bucket capped at 500 or farther.
  clamp(int(distance) div 100, 0, 5)

proc signedBradDelta(current, previous: int): int =
  ## Returns the shortest signed heading delta in native brads.
  (current - previous + 384) mod 256 - 128

proc angleDelta(current, previous: float): float =
  ## Returns the shortest signed angular delta in radians.
  var value = current - previous
  while value > PI:
    value -= 2.0 * PI
  while value < -PI:
    value += 2.0 * PI
  value

proc bradsOf(x, y: float): int =
  ## Returns the native aim heading for one displacement.
  if abs(x) + abs(y) < 1e-6:
    return 0
  (int(round(arctan2(-y, x) * 128.0 / PI)) + 256) mod 256

proc bradsError(desired, current: int): int =
  ## Returns the absolute shortest native heading error.
  abs(signedBradDelta(desired, current))

proc frameForTick(extraction: ExtractResult, tick: int): int =
  ## Returns the exact frame index for one tick or negative one.
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

proc inferredTargetDistance(
  extraction: ExtractResult,
  trigger: SimEvent
): float =
  ## Infers the live target best aligned with one locked trigger heading.
  let frame = extraction.frameForTick(trigger.tick)
  if frame < 0:
    return -1.0
  var
    bestError = high(int)
    bestDistance = -1.0
  for slot in 0 ..< extraction.frameSlots:
    if slot == trigger.source:
      continue
    let target = extraction.frameSeat(frame, slot)
    if (target.flags and 1) == 0:
      continue
    let
      dx = target.x.float - trigger.x
      dy = target.y.float - trigger.y
      distance = hypot(dx, dy)
      error = bradsError(bradsOf(dx, dy), trigger.headingBrads)
    if error < bestError or
      (error == bestError and
        (bestDistance < 0.0 or distance < bestDistance)):
        bestError = error
        bestDistance = distance
  bestDistance

proc placeOf(results: JsonNode, slot: int): int =
  ## Returns one slot's one-based placement or zero if absent.
  let placements = results["placementSlots"]
  for place in 0 ..< placements.len:
    if placements[place].getInt() == slot:
      return place + 1
  0

proc fatalCause(
  events: openArray[SimEvent],
  deathIndex,
  victim: int
): string =
  ## Returns the weapon or hazard responsible for one death.
  let tick = events[deathIndex].tick
  var i = deathIndex - 1
  while i >= 0 and events[i].tick == tick:
    let event = events[i]
    if event.kind == Damage and
      event.target == victim and
      event.hp == 0:
        return if event.weapon.len > 0: event.weapon else: "unknown"
    dec i
  "unknown"

proc playingTick(events: openArray[SimEvent]): int =
  ## Returns the tick at which active play began.
  for event in events:
    if event.kind == PhaseChange and event.weapon == "playing":
      return event.tick
  0

proc exactTargets(value: string): seq[string] =
  ## Parses a comma-separated set of exact league player names.
  for part in value.split(','):
    let name = part.strip()
    if name.len > 0:
      result.add(name)

proc wanted(name: string, targets: seq[string]): bool =
  ## Reports whether one exact player name is selected.
  for target in targets:
    if name == target:
      return true

proc nearestOpponent(
  extraction: ExtractResult,
  frame,
  ownSlot: int
): tuple[slot: int, distance: float] =
  ## Returns the nearest living opponent in one frame.
  result.slot = -1
  result.distance = Inf
  let own = extraction.frameSeat(frame, ownSlot)
  for slot in 0 ..< extraction.frameSlots:
    if slot == ownSlot:
      continue
    let other = extraction.frameSeat(frame, slot)
    if (other.flags and 1) == 0:
      continue
    let distance = hypot(
      other.x.float - own.x.float,
      other.y.float - own.y.float
    )
    if distance < result.distance:
      result.slot = slot
      result.distance = distance

proc addSnapshot(
  player: var PlayerStats,
  track: var SlotTrack,
  seat: FrameSeat,
  radial: float,
  relativeTick: int
) =
  ## Records fixed opening displacement, inward gain, and aim sweep samples.
  for i, threshold in SnapshotTicks:
    if track.sampled[i] or relativeTick < threshold:
      continue
    player.snapshotDistance[i] += hypot(
      seat.x.float - track.start.x.float,
      seat.y.float - track.start.y.float
    )
    player.snapshotInward[i] += track.startRadial - radial
    player.snapshotAim[i] += abs(signedBradDelta(
      seat.aimBrads,
      track.startAim
    ))
    inc player.snapshotSamples[i]
    track.sampled[i] = true

proc addMotion(
  player: var PlayerStats,
  motion: var MotionStats,
  extraction: ExtractResult,
  frame,
  slot,
  ringRadius: int,
  track: SlotTrack
) =
  ## Adds one living frame to a phase and weapon-state motion profile.
  let
    seat = extraction.frameSeat(frame, slot)
    center = ffaRingCenter()
    radial = hypot(
      seat.x.float - center.x.float,
      seat.y.float - center.y.float
    )
  inc motion.frames
  motion.radialDistance += radial
  motion.ringRatio += radial / max(1, ringRadius).float
  motion.ringMargin += ringRadius.float - radial
  if radial > ringRadius.float:
    inc motion.outsideFrames
  let opponent = extraction.nearestOpponent(frame, slot)
  if opponent.slot >= 0:
    inc motion.opponentSamples
    motion.opponentDistance += opponent.distance
    if opponent.distance < 100.0:
      inc motion.opponentNear100
    if opponent.distance < 200.0:
      inc motion.opponentNear200
    if opponent.distance < 300.0:
      inc motion.opponentNear300
  if not track.previousValid or
    extraction.frameTick(frame) != track.previousTick + 1:
      return
  let
    moveX = seat.x.float - track.previous.x.float
    moveY = seat.y.float - track.previous.y.float
    distance = hypot(moveX, moveY)
    previousRadial = hypot(
      track.previous.x.float - center.x.float,
      track.previous.y.float - center.y.float
    )
    radialChange = previousRadial - radial
    aimChange = abs(signedBradDelta(
      seat.aimBrads,
      track.previous.aimBrads
    ))
  motion.pathDistance += distance
  if distance < 0.5:
    inc motion.stationaryFrames
  else:
    inc motion.movedFrames
  if radialChange > 0.05:
    inc motion.inwardFrames
  elif radialChange < -0.05:
    inc motion.outwardFrames
  let angular = angleDelta(
    arctan2(
      seat.y.float - center.y.float,
      seat.x.float - center.x.float
    ),
    arctan2(
      track.previous.y.float - center.y.float,
      track.previous.x.float - center.x.float
    )
  )
  motion.angularDistance += abs(angular)
  if angular > 1e-5:
    inc motion.orbitCounterFrames
  elif angular < -1e-5:
    inc motion.orbitClockwiseFrames
  if aimChange > 0:
    inc motion.aimTurnFrames
    motion.aimDistance += aimChange
  if opponent.slot >= 0 and opponent.distance > 1e-6:
    let other = extraction.frameSeat(frame, opponent.slot)
    let
      unitX = (other.x.float - seat.x.float) / opponent.distance
      unitY = (other.y.float - seat.y.float) / opponent.distance
      toward = moveX * unitX + moveY * unitY
      strafe = abs(moveX * -unitY + moveY * unitX)
    motion.strafeDistance += strafe
    if toward > 0.05:
      inc motion.towardOpponentFrames
    elif toward < -0.05:
      inc motion.awayOpponentFrames

proc addReplay(
  stats: var Table[string, PlayerStats],
  replayPath: string,
  targets: seq[string]
) =
  ## Adds exact target-player behavior from one hash-validated replay.
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
    slotNames = extraction.slotAddress
  config.update(data.configJson)
  for slot in 0 ..< slotNames.len:
    if slotNames[slot].len == 0:
      slotNames[slot] = results["names"][slot].getStr()
  var selected = newSeq[bool](slotNames.len)
  for slot, name in slotNames:
    if not name.wanted(targets):
      continue
    selected[slot] = true
    var player = stats.mgetOrPut(name, PlayerStats())
    inc player.episodes
    if results["win"][slot].getBool():
      inc player.wins
    player.score += results["scores"][slot].getInt()
    player.kills += results["kills"][slot].getInt()
    player.deaths += results["deaths"][slot].getInt()
    player.damage += results["damage"][slot].getInt()
    player.survivalTicks += results["survivalTicks"][slot].getInt()
    player.shots += extraction.slotShotsFired[slot]
    player.hits += extraction.slotShotsHit[slot]
    let place = results.placeOf(slot)
    if place > 0:
      player.places += place
      inc player.placeSamples
    stats[name] = player
  let startTick = extraction.events.playingTick()
  var
    tiers = newSeq[int](slotNames.len)
    tracks = newSeq[SlotTrack](slotNames.len)
    eventIndex = 0
  for frame in 0 ..< extraction.frameCount:
    let
      tick = extraction.frameTick(frame)
      relativeTick = tick - startTick
    while eventIndex < extraction.events.len and
      extraction.events[eventIndex].tick <= tick:
        let event = extraction.events[eventIndex]
        if event.kind == Pickup and
          event.source >= 0 and
          event.source < tiers.len and
          event.item.isGun():
            tiers[event.source] = max(
              tiers[event.source],
              event.item.gunTier()
            )
        inc eventIndex
    if relativeTick < 0:
      continue
    let ringRadius = config.ffaRingRadiusAt(relativeTick)
    for slot, name in slotNames:
      if not selected[slot]:
        continue
      let seat = extraction.frameSeat(frame, slot)
      if (seat.flags and 1) == 0:
        tracks[slot].previousValid = false
        continue
      let
        center = ffaRingCenter()
        radial = hypot(
          seat.x.float - center.x.float,
          seat.y.float - center.y.float
        )
      if not tracks[slot].startValid:
        tracks[slot].start = seat
        tracks[slot].startRadial = radial
        tracks[slot].startAim = seat.aimBrads
        tracks[slot].startValid = true
      var player = stats[name]
      player.addSnapshot(
        tracks[slot],
        seat,
        radial,
        relativeTick
      )
      let
        phase = relativeTick.phaseOf()
        state = if tiers[slot] > 0: 1 else: 0
      player.addMotion(
        player.phases[phase][state],
        extraction,
        frame,
        slot,
        ringRadius,
        tracks[slot]
      )
      stats[name] = player
      tracks[slot].previous = seat
      tracks[slot].previousTick = tick
      tracks[slot].previousValid = true
  var
    pickupOrders = newSeq[seq[string]](slotNames.len)
    firstGun = newSeqWith(slotNames.len, -1)
    secondGun = newSeqWith(slotNames.len, -1)
  for i, event in extraction.events:
    if event.source >= 0 and
      event.source < selected.len and
      selected[event.source]:
        let name = slotNames[event.source]
        case event.kind
        of Pickup:
          stats[name].pickups.inc(event.item)
          pickupOrders[event.source].add(event.item)
          if event.item.isGun():
            if firstGun[event.source] < 0:
              firstGun[event.source] = event.tick
              stats[name].firstGuns.inc(event.item)
              stats[name].firstGunTicks += max(0, event.tick - startTick)
              stats[name].firstGunRadius += hypot(
                event.x - ffaRingCenter().x.float,
                event.y - ffaRingCenter().y.float
              )
              inc stats[name].firstGunEpisodes
            elif secondGun[event.source] < 0:
              secondGun[event.source] = event.tick
              stats[name].secondGunTicks += max(
                0,
                event.tick - firstGun[event.source]
              )
              inc stats[name].secondGunEpisodes
        of GunTrigger:
          inc stats[name].triggers
        of Damage:
          if event.source >= 0:
            stats[name].damageDealt += event.amount
        of Kill:
          discard
        of Heal:
          stats[name].heals += event.amount
        of GrenadeThrow:
          inc stats[name].grenadeThrows
        of SprayUse:
          inc stats[name].sprayTicks
        of ShoutEvent:
          inc stats[name].shouts
        of Death:
          stats[name].fatalCauses.inc(
            extraction.events.fatalCause(i, event.source)
          )
        else:
          discard
    if event.target >= 0 and
      event.target < selected.len and
      selected[event.target] and
      event.kind == Damage:
        let name = slotNames[event.target]
        stats[name].damageReceived += event.amount
        stats[name].shieldBlocked += event.blocked
        if event.weapon == "ring" or event.source < 0:
          stats[name].ringDamage += event.amount
    if event.kind == ShotImpact and
      event.source >= 0 and
      event.source < selected.len and
      selected[event.source] and
      "gun" in event.weapon:
        let distance = extraction.inferredTargetDistance(event)
        if distance >= 0.0:
          let
            name = slotNames[event.source]
            bin = distance.rangeBin()
          inc stats[name].rangeShots[bin]
          if event.damages.len > 0:
            inc stats[name].rangeHits[bin]
  for slot, name in slotNames:
    if not selected[slot] or pickupOrders[slot].len == 0:
      continue
    stats[name].pickupOrders.inc(pickupOrders[slot].join(">"))

proc sortedKeys[T](table: Table[string, T]): seq[string] =
  ## Returns a table's string keys in deterministic order.
  result = toSeq(table.keys)
  result.sort()

proc sortedKeys(table: CountTable[string]): seq[string] =
  ## Returns a count table's string keys in deterministic order.
  result = toSeq(table.keys)
  result.sort()

proc rangeText(player: PlayerStats): string =
  ## Returns compact target-range accuracy buckets.
  for bin in 0 ..< player.rangeShots.len:
    if result.len > 0:
      result.add(",")
    let label = if bin < 5: $(bin * 100) else: "500+"
    result.add(
      label & ":" & $player.rangeHits[bin] & "/" &
        $player.rangeShots[bin]
    )

proc printProfile(name: string, player: PlayerStats) =
  ## Prints one player's overall strategy profile.
  let
    survivalSec = mean(
      player.survivalTicks,
      player.episodes
    ) / TicksPerSec
    firstGunSec = mean(
      player.firstGunTicks,
      player.firstGunEpisodes
    ) / TicksPerSec
    firstGunRadius = mean(
      player.firstGunRadius,
      player.firstGunEpisodes
    )
    secondGunSec = mean(
      player.secondGunTicks,
      player.secondGunEpisodes
    ) / TicksPerSec
  echo &"PROFILE\t{name}\tepisodes={player.episodes}" &
    &"\twinPct={percent(player.wins, player.episodes):.2f}" &
    &"\tscore={mean(player.score, player.episodes):.2f}" &
    &"\tkills={mean(player.kills, player.episodes):.2f}" &
    &"\tdamage={mean(player.damage, player.episodes):.2f}" &
    &"\tsurvivalSec={survivalSec:.2f}" &
    &"\tplace={mean(player.places, player.placeSamples):.2f}" &
    &"\taccuracy={percent(player.hits, player.shots):.2f}" &
    &"\ttriggers={mean(player.triggers, player.episodes):.2f}" &
    &"\treceived={mean(player.damageReceived, player.episodes):.2f}" &
    &"\tringDamage={mean(player.ringDamage, player.episodes):.2f}" &
    &"\tblocked={mean(player.shieldBlocked, player.episodes):.2f}" &
    &"\theals={mean(player.heals, player.episodes):.2f}" &
    &"\tfirstGunSec={firstGunSec:.2f}" &
    &"\tfirstGunRadius={firstGunRadius:.2f}" &
    &"\tsecondGunDelaySec={secondGunSec:.2f}" &
    &"\tgrenades={mean(player.grenadeThrows, player.episodes):.2f}" &
    &"\tsprayTicks={mean(player.sprayTicks, player.episodes):.2f}" &
    &"\tshouts={mean(player.shouts, player.episodes):.2f}" &
    &"\tranges={player.rangeText()}"

proc printMotion(
  name: string,
  phase: StrategyPhase,
  state: int,
  motion: MotionStats
) =
  ## Prints one phase and weapon-state motion profile.
  let
    pathPerSec = motion.pathDistance /
      max(1, motion.frames).float * TicksPerSec
    aimPerSec = motion.aimDistance.float /
      max(1, motion.frames).float * TicksPerSec
    opponentDist = mean(
      motion.opponentDistance,
      motion.opponentSamples
    )
    near100Pct = percent(
      motion.opponentNear100,
      motion.opponentSamples
    )
    near200Pct = percent(
      motion.opponentNear200,
      motion.opponentSamples
    )
    near300Pct = percent(
      motion.opponentNear300,
      motion.opponentSamples
    )
    strafePerSec = motion.strafeDistance /
      max(1, motion.frames).float * TicksPerSec
  echo &"PHASE\t{name}\t{phase.phaseText()}\t{state.stateText()}" &
    &"\tseconds={motion.frames.float / TicksPerSec:.2f}" &
    &"\tpathPerSec={pathPerSec:.2f}" &
    &"\tstationaryPct={percent(motion.stationaryFrames, motion.frames):.2f}" &
    &"\tradial={mean(motion.radialDistance, motion.frames):.2f}" &
    &"\tringRatio={mean(motion.ringRatio, motion.frames):.3f}" &
    &"\tringMargin={mean(motion.ringMargin, motion.frames):.2f}" &
    &"\toutsidePct={percent(motion.outsideFrames, motion.frames):.2f}" &
    &"\tinwardPct={percent(motion.inwardFrames, motion.frames):.2f}" &
    &"\toutwardPct={percent(motion.outwardFrames, motion.frames):.2f}" &
    &"\torbitCwPct={percent(motion.orbitClockwiseFrames, motion.frames):.2f}" &
    &"\torbitCcwPct={percent(motion.orbitCounterFrames, motion.frames):.2f}" &
    &"\taimTurnPct={percent(motion.aimTurnFrames, motion.frames):.2f}" &
    &"\taimBradsPerSec={aimPerSec:.2f}" &
    &"\topponentDist={opponentDist:.2f}" &
    &"\tnear100Pct={near100Pct:.2f}" &
    &"\tnear200Pct={near200Pct:.2f}" &
    &"\tnear300Pct={near300Pct:.2f}" &
    &"\ttowardPct={percent(motion.towardOpponentFrames, motion.frames):.2f}" &
    &"\tawayPct={percent(motion.awayOpponentFrames, motion.frames):.2f}" &
    &"\tstrafePerSec={strafePerSec:.2f}"

proc printStats(stats: Table[string, PlayerStats]) =
  ## Prints deterministic overall, phase, pickup, and opening profiles.
  for name in stats.sortedKeys():
    let player = stats[name]
    name.printProfile(player)
    for i, threshold in SnapshotTicks:
      let
        distance = mean(
          player.snapshotDistance[i],
          player.snapshotSamples[i]
        )
        inward = mean(
          player.snapshotInward[i],
          player.snapshotSamples[i]
        )
        aim = mean(
          player.snapshotAim[i],
          player.snapshotSamples[i]
        )
      echo &"SNAPSHOT\t{name}\tsec={threshold.float / TicksPerSec:.0f}" &
        &"\tdistance={distance:.2f}" &
        &"\tinwardGain={inward:.2f}" &
        &"\taimSweep={aim:.2f}" &
        &"\tsamples={player.snapshotSamples[i]}"
    for phase in StrategyPhase:
      for state in 0 .. 1:
        name.printMotion(phase, state, player.phases[phase][state])
    for item in player.pickups.sortedKeys():
      echo &"PICKUP\t{name}\t{item}\tcount={player.pickups[item]}" &
        &"\tperEpisode={mean(player.pickups[item], player.episodes):.3f}"
    for item in player.firstGuns.sortedKeys():
      echo &"FIRST_GUN\t{name}\t{item}\tcount={player.firstGuns[item]}" &
        &"\tpct={percent(player.firstGuns[item], player.firstGunEpisodes):.2f}"
    var orders = player.pickupOrders.sortedKeys()
    orders.sort(proc (a, b: string): int =
      result = cmp(player.pickupOrders[b], player.pickupOrders[a])
      if result == 0:
        result = cmp(a, b)
    )
    for i in 0 ..< min(10, orders.len):
      let order = orders[i]
      echo &"ORDER\t{name}\t{order}\tcount={player.pickupOrders[order]}"
    for cause in player.fatalCauses.sortedKeys():
      echo &"FATAL\t{name}\t{cause}\tcount={player.fatalCauses[cause]}"

proc summarize(replayDir: string, targets: seq[string]) =
  ## Summarizes current strategy profiles across one hosted replay corpus.
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
    "usage: summarize_strategy_profiles REPLAY_DIR PLAYER_NAMES"
  )

summarize(
  absolutePath(paramStr(1)),
  exactTargets(paramStr(2))
)
