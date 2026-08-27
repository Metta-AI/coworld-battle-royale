import
  std/[json, os, strutils],
  curly

const DashBase =
  "https://softmaxdash-nginx.tail0f4a29.ts.net/league/"

type
  BattleRoyaleError = object of CatchableError

proc fetch(curl: Curly, url: string): string {.raises: [
  CatchableError,
  BattleRoyaleError
].} =
  ## Fetches one dashboard or replay URL and validates its HTTP response.
  let response = curl.get(url, timeout = 120)
  if response.code != 200:
    raise newException(
      BattleRoyaleError,
      "HTTP " & $response.code & " while fetching " & url
    )
  response.body

proc fetchJson(curl: Curly, url: string): JsonNode {.raises: [
  CatchableError,
  ValueError,
  BattleRoyaleError
].} =
  ## Fetches and parses one dashboard JSON document.
  result = parseJson(curl.fetch(url))
  if result.kind != JObject:
    raise newException(
      BattleRoyaleError,
      "dashboard response is not an object: " & url
    )

proc parseLabels(value: string): seq[string] =
  ## Parses a comma-separated set of exact policy labels.
  for part in value.split(','):
    let label = part.strip()
    if label.len > 0:
      result.add(label)

proc hasTarget(policies: string, labels: seq[string]): bool =
  ## Reports whether a participant list contains an exact target label.
  for part in policies.split(','):
    let label = part.strip()
    for target in labels:
      if label == target:
        return true

proc safeField(value: string): string =
  ## Makes one value safe for a tab-separated manifest.
  value.replace('\t', ' ').replace('\r', ' ').replace('\n', ' ')

proc downloadRounds(
  leagueSlug: string,
  newestRound,
  roundCount: int,
  labels: seq[string],
  outputDir: string
) {.raises: [
  CatchableError,
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Downloads recent round replays containing any exact target policy.
  if newestRound <= 0 or roundCount <= 0:
    raise newException(
      BattleRoyaleError,
      "round numbers and counts must be positive"
    )
  if labels.len == 0:
    raise newException(
      BattleRoyaleError,
      "at least one exact policy label is required"
    )
  createDir(outputDir)
  let curl = newCurly(4)
  defer:
    curl.close()
  var
    downloaded = 0
    existing = 0
    matched = 0
    manifest = "round\tgame\tepisode_id\treplay_url\tpolicies\n"
  for roundNumber in countdown(
    newestRound,
    newestRound - roundCount + 1
  ):
    let
      roundPath = leagueSlug & "/rounds/" & $roundNumber
      roundUrl = DashBase & roundPath & ".json"
      roundData = curl.fetchJson(roundUrl)
    if not roundData.hasKey("games") or
      roundData["games"].kind != JArray:
        raise newException(
          BattleRoyaleError,
          "round has no games array: " & $roundNumber
        )
    for game in roundData["games"]:
      let policies = game["policies"].getStr()
      if not policies.hasTarget(labels):
        continue
      inc matched
      let
        gameNumber = game["number"].getInt()
        episodeId = game["id"].getStr()
        detailUrl = DashBase & roundPath & "/" & $gameNumber & ".json"
        detail = curl.fetchJson(detailUrl)
        replayUrl = detail["replayDataUrl"].getStr()
      if replayUrl.len == 0:
        raise newException(
          BattleRoyaleError,
          "game has no replay URL: " & episodeId
        )
      let replayPath = outputDir / (
        "round" & $roundNumber & "-game" & $gameNumber & "-" &
          episodeId & ".replay"
      )
      if fileExists(replayPath):
        inc existing
      else:
        writeFile(replayPath, curl.fetch(replayUrl))
        inc downloaded
      manifest.add(
        $roundNumber & "\t" & $gameNumber & "\t" & episodeId & "\t" &
          replayUrl.safeField() & "\t" & policies.safeField() & "\n"
      )
  writeFile(outputDir / "manifest.tsv", manifest)
  echo "matched=", matched
  echo "downloaded=", downloaded
  echo "existing=", existing
  echo "outputDir=", outputDir

if paramCount() != 5:
  raise newException(
    BattleRoyaleError,
    "usage: download_round_replays LEAGUE_SLUG NEWEST_ROUND " &
      "ROUND_COUNT POLICY_LABELS OUTPUT_DIR"
  )

try:
  downloadRounds(
    paramStr(1),
    parseInt(paramStr(2)),
    parseInt(paramStr(3)),
    parseLabels(paramStr(4)),
    absolutePath(paramStr(5))
  )
except ValueError:
  raise newException(
    BattleRoyaleError,
    "invalid dashboard or command data: " & getCurrentExceptionMsg()
  )
