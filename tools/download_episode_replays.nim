import
  std/[json, os, osproc, streams, strutils],
  curly

type
  BattleRoyaleError = object of CatchableError

proc runCoworld(args: seq[string]): string {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Runs one Coworld CLI command and returns its output.
  let process = startProcess(
    "uv",
    args = @["run", "coworld"] & args,
    options = {poUsePath, poStdErrToStdOut}
  )
  defer:
    process.close()
  result = process.outputStream.readAll()
  let exitCode = process.waitForExit()
  if exitCode != 0:
    raise newException(
      BattleRoyaleError,
      "Coworld command failed: " & result
    )

proc loadEpisode(episodeId: string): JsonNode {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Loads one hosted episode request by its exact ID.
  result = parseJson(runCoworld(@[
    "episodes",
    episodeId,
    "--json"
  ]))
  if result.kind != JObject or result["id"].getStr() != episodeId:
    raise newException(
      BattleRoyaleError,
      "hosted episode JSON does not match: " & episodeId
    )

proc containsPolicy(episode: JsonNode, policyLabel: string): bool =
  ## Reports whether one hosted episode contains a policy label.
  if policyLabel.len == 0:
    return true
  for participant in episode["participants"]:
    if participant["label"].getStr() == policyLabel:
      return true

proc downloadEpisodes(
  episodeIds,
  policyLabel,
  outputDir: string
) {.raises: [OSError, IOError, ValueError, BattleRoyaleError,
    CatchableError].} =
  ## Downloads completed replays containing the requested policy.
  createDir(outputDir)
  let curl = newCurly(4)
  defer:
    curl.close()
  var
    downloaded = 0
    skipped = 0
  for episodeId in episodeIds.split(','):
    let episode = loadEpisode(episodeId)
    if episode["status"].getStr() != "completed":
      raise newException(
        BattleRoyaleError,
        "hosted episode is not complete: " & episodeId
      )
    if not episode.containsPolicy(policyLabel):
      inc skipped
      continue
    let replayUrl = episode["replay_url"].getStr()
    if replayUrl.len == 0:
      raise newException(
        BattleRoyaleError,
        "hosted episode has no replay: " & episodeId
      )
    let response = curl.get(replayUrl, timeout = 120)
    if response.code != 200:
      raise newException(
        BattleRoyaleError,
        "replay download failed with HTTP " & $response.code &
          ": " & episodeId
      )
    writeFile(outputDir / (episodeId & ".replay"), response.body)
    inc downloaded
  echo "downloaded=", downloaded
  echo "skipped=", skipped
  echo "outputDir=", outputDir

if paramCount() != 3:
  raise newException(
    BattleRoyaleError,
    "usage: download_episode_replays EPISODE_IDS POLICY_LABEL OUTPUT_DIR"
  )

try:
  downloadEpisodes(
    paramStr(1),
    paramStr(2),
    absolutePath(paramStr(3))
  )
except ValueError:
  raise newException(
    BattleRoyaleError,
    "invalid hosted episode data: " & getCurrentExceptionMsg()
  )
