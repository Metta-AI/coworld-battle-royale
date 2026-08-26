import
  std/[algorithm, json, math, os, osproc, streams, strformat, strutils,
    tables],
  zippy/ziparchives

type
  BattleRoyaleError = object of CatchableError
  MetricKind = enum
    LastTickMetric,
    ArmedFractionMetric,
    LootTripsMetric,
    DamageMetric,
    HealMetric,
    FightTicksMetric,
    RingTicksMetric,
    UnstickTicksMetric,
    HoldTicksMetric
  ArtifactRow = object
    episode: string
    score: float
    lastTick: float
    armedFraction: float
    lootTrips: float
    damage: float
    heal: float
    fightTicks: float
    ringTicks: float
    unstickTicks: float
    holdTicks: float

proc loadEpisodes(source: string): JsonNode {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Loads hosted episode JSON for one experience request.
  let process = startProcess(
    "uv",
    args = [
      "run",
      "coworld",
      "xp-request",
      "episodes",
      source,
      "--json"
    ],
    options = {poUsePath}
  )
  defer:
    process.close()
  let output = process.outputStream.readAll()
  if process.waitForExit() != 0:
    raise newException(
      BattleRoyaleError,
      "hosted XP episode request failed: " & source
    )
  result = parseJson(output)
  if result.kind != JArray:
    raise newException(
      BattleRoyaleError,
      "hosted XP episode JSON is not an array: " & source
    )

proc loadScores(
  sources: string,
  policyLabel: string
): Table[string, float] {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Maps hosted episode request IDs to one policy's score.
  for source in sources.split(','):
    for episode in loadEpisodes(source):
      var position = -1
      for participant in episode["participants"]:
        if participant["label"].getStr() == policyLabel:
          position = participant["position"].getInt()
          break
      if position < 0:
        raise newException(
          BattleRoyaleError,
          "policy is absent from hosted XP episode: " & policyLabel
        )
      var found = false
      for item in episode["participant_scores"]:
        if item["position"].getInt() == position:
          result[episode["id"].getStr()] = item["score"].getFloat()
          found = true
          break
      if not found:
        raise newException(
          BattleRoyaleError,
          "policy score is absent from hosted XP episode: " & policyLabel
        )

proc artifactSummary(zipPath: string): JsonNode {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Returns summary.json from one hosted player artifact.
  let reader = openZipArchive(zipPath)
  defer:
    reader.close()
  for path in reader.walkFiles:
    if path == "summary.json":
      return parseJson(reader.extractFile(path))
  raise newException(
    BattleRoyaleError,
    "artifact has no summary.json: " & zipPath
  )

proc episodeId(path: string): string =
  ## Returns the hosted episode request ID from an artifact filename.
  let
    name = path.extractFilename()
    marker = name.find("-policy_agent_")
  if marker < 0:
    return name.changeFileExt("")
  name[0 ..< marker]

proc summaryCount(summary: JsonNode, section, key: string): float =
  ## Returns one summary counter or zero when the counter is absent.
  if not summary.hasKey(section) or not summary[section].hasKey(key):
    return 0.0
  float(summary[section][key].getInt())

proc artifactRow(
  path: string,
  scores: Table[string, float]
): ArtifactRow {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Joins one hosted artifact summary to its hosted policy score.
  let
    episode = episodeId(path)
    summary = artifactSummary(path)
  if episode notin scores:
    raise newException(
      BattleRoyaleError,
      "artifact episode is absent from hosted scores: " & episode
    )
  result = ArtifactRow(
    episode: episode,
    score: scores[episode],
    lastTick: float(summary["lastTick"].getInt()),
    armedFraction: summary["armedFrac"].getFloat(),
    lootTrips: float(summary["lootTrips"].getInt()),
    damage: summary.summaryCount("events", "damage"),
    heal: summary.summaryCount("events", "heal"),
    fightTicks: summary.summaryCount("objectiveTicks", "fight"),
    ringTicks: summary.summaryCount("objectiveTicks", "safe_zone"),
    unstickTicks:
      summary.summaryCount("actionTicks", "ring_unstick") +
      summary.summaryCount("actionTicks", "ring_unstick_flip"),
    holdTicks: summary.summaryCount("objectiveTicks", "passive_band")
  )

proc metric(row: ArtifactRow, kind: MetricKind): float =
  ## Returns one selected artifact metric.
  case kind
  of LastTickMetric:
    row.lastTick
  of ArmedFractionMetric:
    row.armedFraction
  of LootTripsMetric:
    row.lootTrips
  of DamageMetric:
    row.damage
  of HealMetric:
    row.heal
  of FightTicksMetric:
    row.fightTicks
  of RingTicksMetric:
    row.ringTicks
  of UnstickTicksMetric:
    row.unstickTicks
  of HoldTicksMetric:
    row.holdTicks

proc metricName(kind: MetricKind): string =
  ## Returns a stable metric label.
  case kind
  of LastTickMetric:
    "lastTick"
  of ArmedFractionMetric:
    "armedFraction"
  of LootTripsMetric:
    "lootTrips"
  of DamageMetric:
    "damageEvents"
  of HealMetric:
    "healEvents"
  of FightTicksMetric:
    "fightTicks"
  of RingTicksMetric:
    "ringTicks"
  of UnstickTicksMetric:
    "unstickTicks"
  of HoldTicksMetric:
    "holdTicks"

proc pearson(rows: seq[ArtifactRow], kind: MetricKind): float =
  ## Returns the Pearson correlation between hosted score and one metric.
  if rows.len < 2:
    return 0.0
  var
    scoreMean = 0.0
    metricMean = 0.0
  for row in rows:
    scoreMean += row.score
    metricMean += row.metric(kind)
  scoreMean /= float(rows.len)
  metricMean /= float(rows.len)
  var
    covariance = 0.0
    scoreSquares = 0.0
    metricSquares = 0.0
  for row in rows:
    let
      scoreDelta = row.score - scoreMean
      metricDelta = row.metric(kind) - metricMean
    covariance += scoreDelta * metricDelta
    scoreSquares += scoreDelta * scoreDelta
    metricSquares += metricDelta * metricDelta
  let denominator = sqrt(scoreSquares * metricSquares)
  if denominator <= 0.0:
    return 0.0
  covariance / denominator

proc analyze(
  sources: string,
  policyLabel: string,
  artifactDir: string
) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Prints joined hosted episode metrics and score correlations.
  let scores = loadScores(sources, policyLabel)
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
  var rows: seq[ArtifactRow]
  for path in paths:
    rows.add(artifactRow(path, scores))
  echo "episode\tscore\tlastTick\tarmedFrac\tlootTrips\tdamage\theal\t" &
    "fightTicks\tringTicks\tunstickTicks\tholdTicks"
  for row in rows:
    echo row.episode, "\t", &"{row.score:.1f}", "\t",
      int(row.lastTick), "\t", &"{row.armedFraction:.4f}", "\t",
      int(row.lootTrips), "\t", int(row.damage), "\t", int(row.heal),
      "\t", int(row.fightTicks), "\t", int(row.ringTicks), "\t",
      int(row.unstickTicks), "\t", int(row.holdTicks)
  for kind in MetricKind:
    echo "correlation ", kind.metricName(), "=", &"{rows.pearson(kind):.4f}"

if paramCount() != 3:
  raise newException(
    BattleRoyaleError,
    "usage: correlate_xp_artifacts XP_IDS POLICY_LABEL ARTIFACT_DIRECTORY"
  )

analyze(paramStr(1), paramStr(2), absolutePath(paramStr(3)))
