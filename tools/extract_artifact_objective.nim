import
  std/[json, os],
  zippy/ziparchives

type
  BattleRoyaleError = object of CatchableError

proc artifactSummary(zipPath: string): JsonNode {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Returns summary.json from a hosted player artifact.
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

proc checkObjective(
  zipPath: string,
  expectedObjective: string
) {.raises: [
  IOError,
  OSError,
  ValueError,
  ZippyError,
  BattleRoyaleError
].} =
  ## Checks and prints a hosted artifact objective tick count.
  let summary = artifactSummary(zipPath)
  if not summary.hasKey("objectiveTicks") or
      not summary["objectiveTicks"].hasKey(expectedObjective):
    raise newException(
      BattleRoyaleError,
      "artifact has no objective: " & expectedObjective
    )
  let ticks = summary["objectiveTicks"][expectedObjective].getInt()
  if ticks <= 0:
    raise newException(
      BattleRoyaleError,
      "artifact objective did not fire: " & expectedObjective
    )
  echo expectedObjective, " ticks=", ticks

if paramCount() != 2:
  raise newException(
    BattleRoyaleError,
    "usage: extract_artifact_objective ARTIFACT_ZIP EXPECTED_OBJECTIVE"
  )

checkObjective(paramStr(1), paramStr(2))
