import
  std/[algorithm, json, math, os, strutils],
  zippy/ziparchives

const DeathWindowTicks = 5 * 24

type
  BattleRoyaleError = object of CatchableError
  TickSample = object
    tick: int
    x: float
    y: float
    hp: int
    tier: int
    visible: int
    objective: string
    action: string
    dead: bool
  DamageTotals = object
    files: int
    deaths: int
    drops: int
    damage: int
    ringDrops: int
    combatDrops: int
    visibleCombatDrops: int
    armedVisibleCombatDrops: int
    holdVisibleCombatDrops: int
    stationaryVisibleCombatDrops: int
    lethalVisibleCombatDrops: int

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

proc sample(node: JsonNode): TickSample =
  ## Parses the damage-analysis fields from one artifact tick.
  result.tick = node["t"].getInt()
  result.x = node["x"].getFloat()
  result.y = node["y"].getFloat()
  result.hp = node["hp"].getInt()
  result.tier = node["tier"].getInt()
  result.visible = node["vis"].getInt()
  result.objective = node["obj"].getStr()
  result.action = node["act"].getStr()
  result.dead = node.hasKey("dead") and node["dead"].getBool()

proc samples(zipPath: string): seq[TickSample] {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Parses all sampled ticks from one hosted artifact.
  for line in tickStream(zipPath).splitLines():
    if line.len > 0:
      result.add(sample(parseJson(line)))

proc ringLike(previous, current: TickSample): bool =
  ## Reports whether a sampled HP drop occurs during ring safety.
  previous.objective == "safe_zone" or
    current.objective == "safe_zone" or
    previous.action in ["retreat_ring", "ring_unstick"] or
    current.action in ["retreat_ring", "ring_unstick"]

proc visible(previous, current: TickSample): bool =
  ## Reports whether either sample around a damage drop saw an opponent.
  previous.visible > 0 or current.visible > 0

proc addArtifact(
  totals: var DamageTotals,
  zipPath: string
) {.raises: [Exception].} =
  ## Adds sampled HP-drop windows from one hosted artifact.
  let ticks = samples(zipPath)
  inc totals.files
  var deathTick = -1
  for tick in ticks:
    if tick.dead:
      deathTick = tick.tick
      inc totals.deaths
      break
  for i in 1 ..< ticks.len:
    let
      previous = ticks[i - 1]
      current = ticks[i]
    if previous.dead or current.dead or current.hp >= previous.hp:
      continue
    inc totals.drops
    totals.damage += previous.hp - current.hp
    if ringLike(previous, current):
      inc totals.ringDrops
      continue
    inc totals.combatDrops
    if not visible(previous, current):
      continue
    inc totals.visibleCombatDrops
    if previous.tier > 0 or current.tier > 0:
      inc totals.armedVisibleCombatDrops
    if previous.action == "hold_band" or current.action == "hold_band":
      inc totals.holdVisibleCombatDrops
    if hypot(current.x - previous.x, current.y - previous.y) < 4.0:
      inc totals.stationaryVisibleCombatDrops
    if deathTick >= current.tick and
        deathTick - current.tick <= DeathWindowTicks:
      inc totals.lethalVisibleCombatDrops

proc summarize(artifactDirs: seq[string]) {.raises: [Exception].} =
  ## Summarizes received-damage windows across hosted artifact directories.
  var
    paths: seq[string]
    totals: DamageTotals
  for artifactDir in artifactDirs:
    for path in walkDirRec(artifactDir):
      if path.endsWith(".zip"):
        paths.add(path)
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "artifact directories contain no zip files"
    )
  paths.sort()
  for path in paths:
    totals.addArtifact(path)
  echo "files=", totals.files
  echo "deaths=", totals.deaths
  echo "drops=", totals.drops
  echo "damage=", totals.damage
  echo "ringDrops=", totals.ringDrops
  echo "combatDrops=", totals.combatDrops
  echo "visibleCombatDrops=", totals.visibleCombatDrops
  echo "armedVisibleCombatDrops=", totals.armedVisibleCombatDrops
  echo "holdVisibleCombatDrops=", totals.holdVisibleCombatDrops
  echo "stationaryVisibleCombatDrops=", totals.stationaryVisibleCombatDrops
  echo "lethalVisibleCombatDrops=", totals.lethalVisibleCombatDrops

if paramCount() < 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_damage_windows ARTIFACT_DIRECTORY [...]"
  )

var artifactDirs: seq[string]
for path in commandLineParams():
  artifactDirs.add(absolutePath(path))
summarize(artifactDirs)
