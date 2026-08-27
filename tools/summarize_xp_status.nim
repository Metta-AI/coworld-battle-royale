import
  std/[json, os, osproc, streams]

type
  BattleRoyaleError = object of CatchableError

proc loadRequest(requestId: string): JsonNode {.raises: [
  OSError,
  IOError,
  ValueError,
  BattleRoyaleError
].} =
  ## Loads one hosted Experience Request as JSON.
  let process = startProcess(
    "uv",
    args = @[
      "run",
      "coworld",
      "xp-request",
      "get",
      requestId,
      "--json"
    ],
    options = {poUsePath, poStdErrToStdOut}
  )
  defer:
    process.close()
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit()
  if exitCode != 0:
    raise newException(
      BattleRoyaleError,
      "Coworld request failed: " & output
    )
  result = parseJson(output)
  if result.kind != JObject or result["id"].getStr() != requestId:
    raise newException(
      BattleRoyaleError,
      "hosted XP response does not match: " & requestId
    )

proc printStatus(request: JsonNode) =
  ## Prints concise completion counts for one hosted Experience Request.
  echo request["id"].getStr(),
    " status=", request["status"].getStr(),
    " pending=", request["pending_count"].getInt(),
    " submitted=", request["submitted_count"].getInt(),
    " running=", request["running_count"].getInt(),
    " completed=", request["completed_count"].getInt(),
    " failed=", request["failed_count"].getInt()

let requestIds = commandLineParams()
if requestIds.len == 0:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_xp_status XP_REQUEST_ID..."
  )
for requestId in requestIds:
  printStatus(loadRequest(requestId))
