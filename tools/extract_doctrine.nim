import
  std/[os, osproc, streams, strtabs, strutils]

proc inheritedEnv(): StringTableRef =
  ## Returns a mutable copy of the current process environment.
  result = newStringTable(modeCaseSensitive)
  for key, value in envPairs():
    result[key] = value

proc startupLine(binaryPath: string): string =
  ## Captures the policy startup line with no doctrine override.
  let env = inheritedEnv()
  env["COWORLD_PLAYER_WS_URL"] = "ws://127.0.0.1:1/?slot=0"
  env.del("COGAMES_ENGINE_WS_URL")
  env.del("CTF_BOT_FFA_DOCTRINE")
  let process = startProcess(
    binaryPath,
    env = env,
    options = {poStdErrToStdOut}
  )
  defer:
    if process.running:
      process.terminate()
    process.close()
  result = process.outputStream.readLine()

if paramCount() < 2:
  raise newException(
    ValueError,
    "usage: extract_doctrine POLICY_BINARY EXPECTED_DOCTRINE " &
    "[EXPECTED_FRAGMENT ...]"
  )

let
  line = startupLine(paramStr(1))
  expected = "ffaDoctrine=" & paramStr(2)

doAssert line.contains(expected),
  "expected " & expected & " in startup log: " & line
for i in 3 .. paramCount():
  doAssert line.contains(paramStr(i)),
    "expected " & paramStr(i) & " in startup log: " & line
echo line
