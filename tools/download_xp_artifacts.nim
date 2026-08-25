import
  std/[json, os, osproc, streams, strutils]

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

proc policyPosition(
  episode: JsonNode,
  policyLabel: string
): int {.raises: [KeyError, BattleRoyaleError].} =
  ## Returns the requested policy's seat in one hosted episode.
  for participant in episode["participants"]:
    if participant["label"].getStr() == policyLabel:
      return participant["position"].getInt()
  raise newException(
    BattleRoyaleError,
    "policy is absent from hosted episode: " & policyLabel
  )

proc downloadArtifact(
  episodeId: string,
  position: int,
  outputDir: string
) {.raises: [OSError, IOError, ValueError, BattleRoyaleError].} =
  ## Downloads one policy seat's hosted log and artifact.
  discard runCoworld(@[
    "episode-logs",
    episodeId,
    "--agent",
    $position,
    "--download-dir",
    outputDir
  ])

proc downloadSources(
  sources: string,
  policyLabel: string,
  outputDir: string
) {.raises: [OSError, IOError, ValueError, BattleRoyaleError].} =
  ## Downloads one policy's artifacts from comma-separated XP requests.
  createDir(outputDir)
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
        position = policyPosition(episode, policyLabel)
      downloadArtifact(episodeId, position, outputDir)
      inc downloaded
  echo "downloaded=", downloaded, " outputDir=", outputDir

if paramCount() != 3:
  raise newException(
    BattleRoyaleError,
    "usage: download_xp_artifacts XP_SOURCES POLICY_LABEL OUTPUT_DIR"
  )

try:
  downloadSources(
    paramStr(1),
    paramStr(2),
    absolutePath(paramStr(3))
  )
except ValueError:
  raise newException(
    BattleRoyaleError,
    "invalid hosted XP episode data: " & getCurrentExceptionMsg()
  )
