import
  std/[algorithm, math, os, sequtils, strformat, strutils, tables],
  ../src/ctf/sim,
  toolutil

const TicksPerSec = 24.0

type
  BattleRoyaleError = object of CatchableError
  LogicPhase = enum
    LogicOpening, LogicLater
  LogicStats = object
    ticks: int
    stationaryTicks: int
    speed: float
    aimTurnTicks: int
    aimDistance: int
    anyUpgradeSamples: int
    anyUpgradeDistance: float
    visibleUpgradeSamples: int
    visibleUpgradeDistance: float
    towardUpgradeTicks: int
    awayUpgradeTicks: int
    visibleEnemySamples: int
    visibleEnemyDistance: float
    armedEnemySamples: int
    towardEnemyTicks: int
    awayEnemyTicks: int
    inwardTicks: int
    outwardTicks: int
    fireTicks: int
  SightStats = object
    pickups: int
    seenPickups: int
    unseenPickups: int
    delayTicks: int
  ScanRunStats = object
    runs: int
    positiveRuns: int
    negativeRuns: int
    ticks: int
    maxTicks: int
  PlayerLogic = object
    cells: array[
      LogicPhase,
      array[4, array[2, array[2, LogicStats]]]
    ]
    deltas: array[4, CountTable[int]]
    scanRuns: array[4, ScanRunStats]
    sights: Table[string, SightStats]
  PreviousAim = object
    valid: bool
    tick: int
    aim: int
    runSign: int
    runTicks: int
    runTier: int
  Upgrade = object
    valid: bool
    tier: int
    x: int
    y: int
    distance: float

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

proc signedBradDelta(current, previous: int): int =
  ## Returns the shortest signed heading delta in native brads.
  (current - previous + 384) mod 256 - 128

proc bradsOf(x, y: float): int =
  ## Returns the native heading for one displacement.
  if abs(x) + abs(y) < 1e-6:
    return 0
  (int(round(arctan2(-y, x) * 128.0 / PI)) + 256) mod 256

proc bradsError(a, b: int): int =
  ## Returns the absolute shortest native heading error.
  abs(signedBradDelta(a, b))

proc gunTier(item: string): int =
  ## Returns the FFA weapon tier encoded by one pickup token.
  case item
  of "low gun":
    1
  of "mid gun":
    2
  of "heavy gun":
    3
  else:
    0

proc phaseText(phase: LogicPhase): string =
  ## Returns a compact logic-phase label.
  if phase == LogicOpening: "0-30s" else: "30s+"

proc pointKey(tier, x, y: int): string =
  ## Returns a stable key for one fixed FFA gun spawn.
  $tier & ":" & $x & ":" & $y

proc seenKey(player: string, tier, x, y: int): string =
  ## Returns a player-qualified key for one seen gun spawn.
  player & "|" & pointKey(tier, x, y)

proc estimatedVisible(
  sim: SimServer,
  playerIndex,
  x,
  y: int
): bool =
  ## Estimates the policy-visible cone using exact range, aim, and LOS rules.
  let
    player = sim.players[playerIndex]
    ownX = player.x + CollisionW div 2
    ownY = player.y + CollisionH div 2
    dx = x - ownX
    dy = y - ownY
    distanceSq = dx * dx + dy * dy
  if distanceSq > sim.visionRange() * sim.visionRange():
    return false
  if not sim.lineOfSightClear(ownX, ownY, x, y):
    return false
  if distanceSq <= sim.config.visionBubble * sim.config.visionBubble:
    return true
  let
    heading = bradsOf(dx.float, dy.float)
    halfCone = sim.config.visionConeDeg.float * 256.0 / 360.0
  bradsError(heading, player.aimBrads).float <= halfCone

proc addSpawn(
  sim: SimServer,
  playerIndex,
  tier: int,
  spawn: PickupSpawn,
  nearestAny,
  nearestVisible: var Upgrade
) =
  ## Considers one present higher-tier spawn for nearest-upgrade summaries.
  let player = sim.players[playerIndex]
  if not spawn.present or tier <= player.weaponTier:
    return
  let distance = hypot(
    (spawn.x - player.x - CollisionW div 2).float,
    (spawn.y - player.y - CollisionH div 2).float
  )
  if not nearestAny.valid or distance < nearestAny.distance:
    nearestAny = Upgrade(
      valid: true,
      tier: tier,
      x: spawn.x,
      y: spawn.y,
      distance: distance
    )
  if sim.estimatedVisible(playerIndex, spawn.x, spawn.y) and
    (not nearestVisible.valid or distance < nearestVisible.distance):
      nearestVisible = Upgrade(
        valid: true,
        tier: tier,
        x: spawn.x,
        y: spawn.y,
        distance: distance
      )

proc nearestUpgrades(
  sim: SimServer,
  playerIndex: int
): tuple[any, visible: Upgrade] =
  ## Returns the nearest present higher-tier guns overall and in view.
  for spawn in sim.lowGunSpawns:
    sim.addSpawn(playerIndex, 1, spawn, result.any, result.visible)
  for spawn in sim.midGunSpawns:
    sim.addSpawn(playerIndex, 2, spawn, result.any, result.visible)
  for spawn in sim.heavyGunSpawns:
    sim.addSpawn(playerIndex, 3, spawn, result.any, result.visible)

proc nearestVisibleEnemy(sim: SimServer, playerIndex: int): Upgrade =
  ## Returns the nearest opponent visible through the policy cone.
  for otherIndex, other in sim.players:
    if otherIndex == playerIndex or not other.alive:
      continue
    if sim.estimatedVisible(
      playerIndex,
      other.x + CollisionW div 2,
      other.y + CollisionH div 2
    ):
      let distance = hypot(
        (other.x - sim.players[playerIndex].x).float,
        (other.y - sim.players[playerIndex].y).float
      )
      if not result.valid or distance < result.distance:
        result = Upgrade(
          valid: true,
          tier: other.weaponTier,
          x: other.x + CollisionW div 2,
          y: other.y + CollisionH div 2,
          distance: distance
        )

proc motionToward(player: Player, upgrade: Upgrade): float =
  ## Returns signed velocity toward one upgrade in pixels per tick.
  if not upgrade.valid or upgrade.distance <= 1e-6:
    return 0.0
  let
    dx = upgrade.x.float -
      (player.x + CollisionW div 2).float
    dy = upgrade.y.float -
      (player.y + CollisionH div 2).float
  (player.velX.float * dx + player.velY.float * dy) / upgrade.distance

proc addTick(
  logic: var PlayerLogic,
  phase: LogicPhase,
  player: Player,
  motionScale: int,
  center: Upgrade,
  upgrades: tuple[any, visible: Upgrade],
  enemy: Upgrade,
  aimDelta: int
) =
  ## Adds one active policy tick to its observable-condition cell.
  let
    tier = clamp(player.weaponTier, 0, 3)
    hasUpgrade = int(upgrades.visible.valid)
    hasEnemy = int(enemy.valid)
  var cell = logic.cells[phase][tier][hasUpgrade][hasEnemy]
  inc cell.ticks
  let speed = hypot(
    player.velX.float,
    player.velY.float
  ) / max(1, motionScale).float
  cell.speed += speed
  if speed < 0.5:
    inc cell.stationaryTicks
  if aimDelta != 0:
    inc cell.aimTurnTicks
    cell.aimDistance += abs(aimDelta)
  if upgrades.any.valid:
    inc cell.anyUpgradeSamples
    cell.anyUpgradeDistance += upgrades.any.distance
  if upgrades.visible.valid:
    inc cell.visibleUpgradeSamples
    cell.visibleUpgradeDistance += upgrades.visible.distance
    let toward = player.motionToward(upgrades.visible)
    if toward > 0.05:
      inc cell.towardUpgradeTicks
    elif toward < -0.05:
      inc cell.awayUpgradeTicks
  if enemy.valid:
    inc cell.visibleEnemySamples
    cell.visibleEnemyDistance += enemy.distance
    if enemy.tier > 0:
      inc cell.armedEnemySamples
    let toward = player.motionToward(enemy)
    if toward > 0.05:
      inc cell.towardEnemyTicks
    elif toward < -0.05:
      inc cell.awayEnemyTicks
  let inward = player.motionToward(center)
  if inward > 0.05:
    inc cell.inwardTicks
  elif inward < -0.05:
    inc cell.outwardTicks
  if player.fireWindup > 0 or player.fireCooldown > 0:
    inc cell.fireTicks
  logic.cells[phase][tier][hasUpgrade][hasEnemy] = cell
  logic.deltas[tier].inc(aimDelta)

proc addRun(
  logic: var PlayerLogic,
  tier,
  sign,
  ticks: int
) =
  ## Adds one uninterrupted scan-direction run.
  if ticks <= 0:
    return
  let index = clamp(tier, 0, 3)
  inc logic.scanRuns[index].runs
  logic.scanRuns[index].ticks += ticks
  logic.scanRuns[index].maxTicks = max(
    logic.scanRuns[index].maxTicks,
    ticks
  )
  if sign > 0:
    inc logic.scanRuns[index].positiveRuns
  elif sign < 0:
    inc logic.scanRuns[index].negativeRuns

proc pickupPlayer(sim: SimServer, sourceSlot: int): string =
  ## Returns the league player name owning one stable pickup-event slot.
  for player in sim.players:
    if player.joinOrder == sourceSlot:
      return player.address

proc addReplay(
  stats: var Table[string, PlayerLogic],
  replayPath: string,
  targets: seq[string]
) =
  ## Adds conditional movement, sensing, and loot logic from one replay.
  let data = loadReplay(replayPath)
  var (sim, replay) = openReplay(data)
  sim.collectEvents = true
  var
    startTick = -1
    previous: Table[string, PreviousAim]
    seenAt: Table[string, int]
  while replay.playing:
    replay.stepReplay(sim)
    if sim.phase == Playing and startTick < 0:
      startTick = sim.tickCount
    if sim.phase == Playing:
      for playerIndex, player in sim.players:
        if not player.alive or not player.address.wanted(targets):
          continue
        let
          relativeTick = max(0, sim.tickCount - startTick)
          phase =
            if relativeTick < 30 * 24:
              LogicOpening
            else:
              LogicLater
          upgrades = sim.nearestUpgrades(playerIndex)
          enemy = sim.nearestVisibleEnemy(playerIndex)
          ringCenter = ffaRingCenter()
          center = Upgrade(
            valid: true,
            x: ringCenter.x,
            y: ringCenter.y,
            distance: hypot(
              (ringCenter.x - player.x - CollisionW div 2).float,
              (ringCenter.y - player.y - CollisionH div 2).float
            )
          )
        var prior = previous.getOrDefault(player.address)
        let
          aimDelta =
            if prior.valid and prior.tick + 1 == sim.tickCount:
              signedBradDelta(player.aimBrads, prior.aim)
            else:
              0
        var logic = stats.getOrDefault(player.address)
        if aimDelta != 0:
          let sign = if aimDelta > 0: 1 else: -1
          if prior.runTicks > 0 and
            prior.runSign == sign and
            prior.runTier == player.weaponTier:
              inc prior.runTicks
          else:
            logic.addRun(
              prior.runTier,
              prior.runSign,
              prior.runTicks
            )
            prior.runSign = sign
            prior.runTicks = 1
            prior.runTier = player.weaponTier
        else:
          logic.addRun(
            prior.runTier,
            prior.runSign,
            prior.runTicks
          )
          prior.runSign = 0
          prior.runTicks = 0
        logic.addTick(
          phase,
          player,
          sim.config.motionScale,
          center,
          upgrades,
          enemy,
          aimDelta
        )
        stats[player.address] = logic
        previous[player.address] = PreviousAim(
          valid: true,
          tick: sim.tickCount,
          aim: player.aimBrads,
          runSign: prior.runSign,
          runTicks: prior.runTicks,
          runTier: prior.runTier
        )
        if upgrades.visible.valid:
          let key = seenKey(
            player.address,
            upgrades.visible.tier,
            upgrades.visible.x,
            upgrades.visible.y
          )
          if key notin seenAt:
            seenAt[key] = sim.tickCount
    for event in sim.events:
      if event.kind != Pickup or event.item.gunTier() == 0:
        continue
      let name = sim.pickupPlayer(event.source)
      if not name.wanted(targets):
        continue
      let
        tier = event.item.gunTier()
        key = seenKey(name, tier, int(event.x), int(event.y))
      var sight = stats[name].sights.getOrDefault(event.item)
      inc sight.pickups
      if key in seenAt:
        inc sight.seenPickups
        sight.delayTicks += max(0, event.tick - seenAt[key])
      else:
        inc sight.unseenPickups
      stats[name].sights[event.item] = sight
    sim.events.setLen(0)
  for name, prior in previous:
    var logic = stats.getOrDefault(name)
    logic.addRun(prior.runTier, prior.runSign, prior.runTicks)
    stats[name] = logic

proc sortedKeys[T](table: Table[string, T]): seq[string] =
  ## Returns a string-keyed table's keys in deterministic order.
  result = toSeq(table.keys)
  result.sort()

proc printCell(
  name: string,
  phase: LogicPhase,
  tier,
  upgrade,
  enemy: int,
  cell: LogicStats
) =
  ## Prints one conditional policy-logic cell.
  let
    anyDistance = mean(
      cell.anyUpgradeDistance,
      cell.anyUpgradeSamples
    )
    visibleDistance = mean(
      cell.visibleUpgradeDistance,
      cell.visibleUpgradeSamples
    )
    towardPct = percent(
      cell.towardUpgradeTicks,
      cell.visibleUpgradeSamples
    )
    awayPct = percent(
      cell.awayUpgradeTicks,
      cell.visibleUpgradeSamples
    )
    enemyDistance = mean(
      cell.visibleEnemyDistance,
      cell.visibleEnemySamples
    )
    armedEnemyPct = percent(
      cell.armedEnemySamples,
      cell.visibleEnemySamples
    )
    towardEnemyPct = percent(
      cell.towardEnemyTicks,
      cell.visibleEnemySamples
    )
    awayEnemyPct = percent(
      cell.awayEnemyTicks,
      cell.visibleEnemySamples
    )
    inwardPct = percent(cell.inwardTicks, cell.ticks)
    outwardPct = percent(cell.outwardTicks, cell.ticks)
  echo &"LOGIC\t{name}\t{phase.phaseText()}\ttier={tier}" &
    &"\tupgrade={upgrade}\tenemy={enemy}\tticks={cell.ticks}" &
    &"\tstationaryPct={percent(cell.stationaryTicks, cell.ticks):.2f}" &
    &"\tspeedPxPerSec={mean(cell.speed, cell.ticks) * TicksPerSec:.2f}" &
    &"\taimTurnPct={percent(cell.aimTurnTicks, cell.ticks):.2f}" &
    &"\taimBradsPerSec={mean(cell.aimDistance, cell.ticks) * TicksPerSec:.2f}" &
    &"\tanyUpgradeDist={anyDistance:.2f}" &
    &"\tvisibleUpgradeDist={visibleDistance:.2f}" &
    &"\ttowardUpgradePct={towardPct:.2f}" &
    &"\tawayUpgradePct={awayPct:.2f}" &
    &"\tvisibleEnemyDist={enemyDistance:.2f}" &
    &"\tarmedEnemyPct={armedEnemyPct:.2f}" &
    &"\ttowardEnemyPct={towardEnemyPct:.2f}" &
    &"\tawayEnemyPct={awayEnemyPct:.2f}" &
    &"\tinwardPct={inwardPct:.2f}" &
    &"\toutwardPct={outwardPct:.2f}" &
    &"\tfirePct={percent(cell.fireTicks, cell.ticks):.2f}"

proc printLogic(stats: Table[string, PlayerLogic]) =
  ## Prints deterministic conditional cells, scan deltas, and sight delays.
  for name in stats.sortedKeys():
    let logic = stats[name]
    for phase in LogicPhase:
      for tier in 0 .. 3:
        for upgrade in 0 .. 1:
          for enemy in 0 .. 1:
            let cell = logic.cells[phase][tier][upgrade][enemy]
            if cell.ticks > 0:
              name.printCell(
                phase,
                tier,
                upgrade,
                enemy,
                cell
              )
    for tier in 0 .. 3:
      var deltas = toSeq(logic.deltas[tier].keys)
      deltas.sort(proc (a, b: int): int =
        result = cmp(logic.deltas[tier][b], logic.deltas[tier][a])
        if result == 0:
          result = cmp(a, b)
      )
      var total = 0
      for delta in deltas:
        total += logic.deltas[tier][delta]
      for i in 0 ..< min(12, deltas.len):
        let delta = deltas[i]
        echo &"SCAN\t{name}\ttier={tier}\tdelta={delta}" &
          &"\tcount={logic.deltas[tier][delta]}" &
          &"\tpct={percent(logic.deltas[tier][delta], total):.2f}"
      let runs = logic.scanRuns[tier]
      if runs.runs > 0:
        echo &"SCAN_RUN\t{name}\ttier={tier}\truns={runs.runs}" &
          &"\tmeanTicks={mean(runs.ticks, runs.runs):.2f}" &
          &"\tmaxTicks={runs.maxTicks}" &
          &"\tpositivePct={percent(runs.positiveRuns, runs.runs):.2f}" &
          &"\tnegativePct={percent(runs.negativeRuns, runs.runs):.2f}"
    for item in logic.sights.sortedKeys():
      let sight = logic.sights[item]
      let delaySec = mean(
        sight.delayTicks,
        sight.seenPickups
      ) / TicksPerSec
      echo &"SIGHT\t{name}\t{item}\tpickups={sight.pickups}" &
        &"\tseen={sight.seenPickups}\tunseen={sight.unseenPickups}" &
        &"\tdelaySec={delaySec:.2f}"

proc summarize(replayDir: string, targets: seq[string]) =
  ## Summarizes conditional sensing and loot logic across hosted replays.
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
  var stats: Table[string, PlayerLogic]
  for i, path in paths:
    stats.addReplay(path, targets)
    if (i + 1) mod 20 == 0:
      stderr.writeLine("processed=", i + 1, "/", paths.len)
  echo "replays=", paths.len
  stats.printLogic()

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_policy_logic REPLAY_DIR PLAYER_NAMES"
  )

summarize(
  absolutePath(paramStr(1)),
  exactTargets(paramStr(2))
)
