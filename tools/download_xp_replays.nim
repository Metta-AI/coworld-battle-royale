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

proc loadEpisodes(source: string): JsonNode {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Loads the episodes in one hosted Experience Request.
  result = parseJson(runCoworld(@[
    "xp-request",
    "episodes",
    source,
    "--json"
  ]))
  if result.kind != JArray:
    raise newException(
      BattleRoyaleError,
      "hosted XP episode JSON is not an array: " & source
    )

proc downloadSources(
  sources: string,
  outputDir: string
) {.raises: [OSError, IOError, ValueError, BattleRoyaleError,
    CatchableError].} =
  ## Downloads completed replays from comma-separated XP requests.
  createDir(outputDir)
  let curl = newCurly(4)
  defer:
    curl.close()
  var downloaded = 0
  for source in sources.split(','):
    let episodes = loadEpisodes(source)
    for episode in episodes:
      if episode["status"].getStr() != "completed":
        raise newException(
          BattleRoyaleError,
          "hosted episode is not complete: " & episode["id"].getStr()
        )
      let
        episodeId = episode["id"].getStr()
        replayUrl = episode["replay_url"].getStr()
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
  echo "downloaded=", downloaded, " outputDir=", outputDir

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: download_xp_replays XP_SOURCES OUTPUT_DIR"
  )

try:
  downloadSources(
    paramStr(1),
    absolutePath(paramStr(2))
  )
except ValueError:
  raise newException(
    BattleRoyaleError,
    "invalid hosted XP episode data: " & getCurrentExceptionMsg()
  )
