import
  std/[algorithm, json, math, os, sequtils, strformat, strutils, tables],
  ../src/ctf/replays,
  ../src/ctf/sim,
  "extract_events"

const
  EarlyTicks = 90 * 24
  InnerRadius = 480.0

type
  BattleRoyaleError = object of CatchableError
  WeaponStats = object
    shots: int
    hits: int
  TargetEstimate = object
    slot: int
    distance: float
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
    weapons: Table[string, WeaponStats]
    pickups: CountTable[string]
    fatalCauses: CountTable[string]
    rangeShots: array[6, int]
    rangeHits: array[6, int]
    targetRangeShots: array[6, int]
    targetRangeHits: array[6, int]
    aimSamples: int
    aimError: int
    compensatedAimError: int
    compensationBetter: int
    radialDistance: float
    radialSamples: int
    earlyRadialDistance: float
    earlyRadialSamples: int
    innerTicks: int
    firstGunTicks: int
    firstGunEpisodes: int
    firstGunRadialDistance: float
    firstGunRadialSamples: int

proc mean(total, count: int): float =
  ## Returns one arithmetic mean or zero for an empty sample.
  if count == 0:
    return 0.0
  total.float / count.float

proc mean(total: float, count: int): float =
  ## Returns one floating-point mean or zero for an empty sample.
  if count == 0:
    return 0.0
  total / count.float

proc percent(part, whole: int): float =
  ## Returns one percentage or zero for an empty denominator.
  100.0 * mean(part, whole)

proc placeOf(results: JsonNode, slot: int): int =
  ## Returns a slot's one-based final placement or zero when it disconnected.
  let placements = results["placementSlots"]
  for place in 0 ..< placements.len:
    if placements[place].getInt() == slot:
      return place + 1
  0

proc fatalCause(
  events: openArray[SimEvent],
  deathIndex: int,
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

proc rangeBin(distance: float): int =
  ## Returns the 100-pixel shot-impact bucket, capped at 500 or farther.
  clamp(int(distance) div 100, 0, 5)

proc bradsOf(x, y: float): int =
  ## Returns the game aim heading from one displacement.
  if abs(x) + abs(y) < 1e-6:
    return 0
  (int(round(arctan2(-y, x) * 128.0 / PI)) + 256) mod 256

proc bradsError(desired, current: int): int =
  ## Returns the absolute shortest heading error.
  abs((desired - current + 384) mod 256 - 128)

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

proc inferredTargetDistance(
  extraction: ExtractResult,
  trigger: SimEvent
): TargetEstimate =
  ## Infers the intended live target nearest the locked trigger heading.
  result.slot = -1
  result.distance = -1.0
  let frame = extraction.frameForTick(trigger.tick)
  if frame < 0:
    return
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
        result.slot = slot
        result.distance = distance

proc addAimSample(
  player: var PlayerStats,
  extraction: ExtractResult,
  trigger, shot: SimEvent,
  target: TargetEstimate
) =
  ## Compares locked aim with own-motion-compensated aim at release.
  let frame = extraction.frameForTick(shot.tick)
  if frame < 0 or target.slot < 0:
    return
  let targetSeat = extraction.frameSeat(frame, target.slot)
  if (targetSeat.flags and 1) == 0:
    return
  let
    actualX = targetSeat.x.float - shot.x
    actualY = targetSeat.y.float - shot.y
    actualHeading = bradsOf(actualX, actualY)
    currentError = bradsError(actualHeading, trigger.headingBrads)
    angle = trigger.headingBrads.float * PI / 128.0
    lockedX = cos(angle) * target.distance
    lockedY = -sin(angle) * target.distance
    ownX = shot.x - trigger.x
    ownY = shot.y - trigger.y
    compensatedHeading = bradsOf(lockedX - ownX, lockedY - ownY)
    compensatedError = bradsError(actualHeading, compensatedHeading)
  inc player.aimSamples
  player.aimError += currentError
  player.compensatedAimError += compensatedError
  if compensatedError < currentError:
    inc player.compensationBetter

proc addReplay(
  stats: var Table[string, PlayerStats],
  replayPath: string
) =
  ## Adds every player's metrics from one hash-validated replay.
  let
    extraction = extractEvents(loadReplay(replayPath), captureFrames = true)
    results = parseJson(extraction.resultsJson)
  if not extraction.finished:
    raise newException(
      BattleRoyaleError,
      "hosted replay did not finish: " & replayPath
    )
  var slotNames = extraction.slotAddress
  for slot in 0 ..< slotNames.len:
    if slotNames[slot].len == 0:
      slotNames[slot] = results["names"][slot].getStr()
  for slot, name in slotNames:
    if name.len == 0:
      raise newException(
        BattleRoyaleError,
        "hosted replay has an unnamed slot: " & replayPath
      )
    var player = stats.mgetOrPut(name, PlayerStats())
    inc player.episodes
    if results["win"][slot].getBool():
      inc player.wins
    player.score += results["scores"][slot].getInt()
    player.kills += results["kills"][slot].getInt()
    player.deaths += results["deaths"][slot].getInt()
    player.damage += results["damage"][slot].getInt()
    player.survivalTicks += results["survivalTicks"][slot].getInt()
    let place = results.placeOf(slot)
    if place > 0:
      player.places += place
      inc player.placeSamples
    player.shots += extraction.slotShotsFired[slot]
    player.hits += extraction.slotShotsHit[slot]
    stats[name] = player
  let center = ffaRingCenter()
  for frame in 0 ..< extraction.frameCount:
    let tick = extraction.frameTick(frame)
    for slot, name in slotNames:
      let seat = extraction.frameSeat(frame, slot)
      if (seat.flags and 1) == 0:
        continue
      let radial = hypot(
        seat.x.float - center.x.float,
        seat.y.float - center.y.float
      )
      stats[name].radialDistance += radial
      inc stats[name].radialSamples
      if tick <= EarlyTicks:
        stats[name].earlyRadialDistance += radial
        inc stats[name].earlyRadialSamples
      if radial <= InnerRadius:
        inc stats[name].innerTicks
  var
    triggers: Table[int64, SimEvent]
    shots: Table[int64, SimEvent]
    firstGunTicks = newSeqWith(slotNames.len, high(int))
  for event in extraction.events:
    if event.kind == GunTrigger:
      triggers[event.actionId] = event
    elif event.kind == Shot:
      shots[event.actionId] = event
  for i, event in extraction.events:
    if event.source >= 0 and event.source < slotNames.len:
      let name = slotNames[event.source]
      if event.kind == Shot:
        inc stats[name].weapons.mgetOrPut(event.weapon, WeaponStats()).shots
      elif event.kind == Hit:
        inc stats[name].weapons.mgetOrPut(event.weapon, WeaponStats()).hits
      elif event.kind == Death:
        stats[name].fatalCauses.inc(extraction.events.fatalCause(i, event.source))
      elif event.kind == Pickup:
        stats[name].pickups.inc(event.item)
        if "gun" in event.item:
          if firstGunTicks[event.source] == high(int):
            stats[name].firstGunRadialDistance += hypot(
              event.x - center.x.float,
              event.y - center.y.float
            )
            inc stats[name].firstGunRadialSamples
          firstGunTicks[event.source] = min(
            firstGunTicks[event.source],
            event.tick
          )
      elif event.kind == ShotImpact and "gun" in event.weapon:
        let bin = event.distance.rangeBin()
        inc stats[name].rangeShots[bin]
        if event.damages.len > 0:
          inc stats[name].rangeHits[bin]
        if event.actionId in triggers:
          let target = extraction.inferredTargetDistance(
            triggers[event.actionId]
          )
          if target.distance >= 0.0:
            let targetBin = target.distance.rangeBin()
            inc stats[name].targetRangeShots[targetBin]
            if event.damages.len > 0:
              inc stats[name].targetRangeHits[targetBin]
            if event.actionId in shots:
              var player = stats[name]
              player.addAimSample(
                extraction,
                triggers[event.actionId],
                shots[event.actionId],
                target
              )
              stats[name] = player
  for slot, tick in firstGunTicks:
    if tick < high(int):
      stats[slotNames[slot]].firstGunTicks += tick
      inc stats[slotNames[slot]].firstGunEpisodes

proc weaponText(player: PlayerStats): string =
  ## Returns compact accuracy totals grouped by weapon.
  var weapons = toSeq(player.weapons.keys)
  weapons.sort()
  for weapon in weapons:
    let counts = player.weapons[weapon]
    if result.len > 0:
      result.add(",")
    result.add(&"{weapon}:{counts.hits}/{counts.shots}")

proc causeText(player: PlayerStats): string =
  ## Returns compact fatal-cause totals.
  var causes = toSeq(player.fatalCauses.keys)
  causes.sort()
  for cause in causes:
    if result.len > 0:
      result.add(",")
    result.add(&"{cause}:{player.fatalCauses[cause]}")

proc pickupText(player: PlayerStats): string =
  ## Returns compact pickup totals grouped by item name.
  var items = toSeq(player.pickups.keys)
  items.sort()
  for item in items:
    if result.len > 0:
      result.add(",")
    result.add(&"{item}:{player.pickups[item]}")

proc rangeText(
  hits: array[6, int],
  shots: array[6, int]
): string =
  ## Returns hits and shots in 100-pixel distance buckets.
  for bin in 0 ..< shots.len:
    if result.len > 0:
      result.add(",")
    let label = if bin < 5: $(bin * 100) else: "500+"
    result.add(
      &"{label}:{hits[bin]}/{shots[bin]}"
    )

proc aimText(player: PlayerStats): string =
  ## Returns current and own-motion-compensated release aim diagnostics.
  if player.aimSamples == 0:
    return "0/0/0"
  &"{mean(player.aimError, player.aimSamples):.2f}/" &
    &"{mean(player.compensatedAimError, player.aimSamples):.2f}/" &
    &"{percent(player.compensationBetter, player.aimSamples):.2f}"

proc summarize(replayDir: string) =
  ## Extracts and prints aggregate metrics for one replay directory.
  var
    paths: seq[string]
    stats: Table[string, PlayerStats]
  for kind, path in walkDir(replayDir):
    if kind == pcFile and path.toLowerAscii().endsWith(".replay"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "no replay files found in " & replayDir
    )
  for path in paths:
    stats.addReplay(path)
  var names = toSeq(stats.keys)
  names.sort()
  echo "replays=", paths.len
  echo "name episodes winPct scoreMean killsMean deathsMean damageMean " &
    "survivalMean placeMean radialMean earlyRadialMean innerPct " &
    "firstGunTick firstGunRadius accuracy weapons pickups impacts targets " &
    "aimError/compError/compBetterPct fatalCauses"
  for name in names:
    let
      player = stats[name]
      firstGunRadius = mean(
        player.firstGunRadialDistance,
        player.firstGunRadialSamples
      )
    echo &"{name} {player.episodes} {percent(player.wins, player.episodes):.2f} " &
      &"{mean(player.score, player.episodes):.2f} " &
      &"{mean(player.kills, player.episodes):.2f} " &
      &"{mean(player.deaths, player.episodes):.2f} " &
      &"{mean(player.damage, player.episodes):.2f} " &
      &"{mean(player.survivalTicks, player.episodes):.2f} " &
      &"{mean(player.places, player.placeSamples):.2f} " &
      &"{mean(player.radialDistance, player.radialSamples):.2f} " &
      &"{mean(player.earlyRadialDistance, player.earlyRadialSamples):.2f} " &
      &"{percent(player.innerTicks, player.radialSamples):.2f} " &
      &"{mean(player.firstGunTicks, player.firstGunEpisodes):.2f} " &
      &"{firstGunRadius:.2f} " &
      &"{percent(player.hits, player.shots):.2f} " &
      &"{player.weaponText()} {player.pickupText()} " &
      &"{rangeText(player.rangeHits, player.rangeShots)} " &
      &"{rangeText(player.targetRangeHits, player.targetRangeShots)} " &
      &"{player.aimText()} {player.causeText()}"

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_replays REPLAY_DIR"
  )

summarize(absolutePath(paramStr(1)))
