import
  std/[os, osproc, streams, strtabs, strutils]

proc inheritedEnv(): StringTableRef =
  ## Returns a mutable copy of the current process environment.
  result = newStringTable(modeCaseSensitive)
  for key, value in envPairs():
    result[key] = value

proc removeContainer(name: string) =
  ## Removes the named temporary Docker container.
  let process = startProcess(
    "docker",
    args = ["rm", "-f", name],
    options = {poUsePath, poParentStreams}
  )
  defer:
    process.close()
  discard process.waitForExit()

proc startupLine(source: string): string =
  ## Captures a binary or Docker policy startup line without an override.
  let
    env = inheritedEnv()
    isDocker = source.startsWith("docker:")
    containerName = "coworld-doctrine-" & $getCurrentProcessId()
  env["COWORLD_PLAYER_WS_URL"] = "ws://127.0.0.1:1/?slot=0"
  env.del("COGAMES_ENGINE_WS_URL")
  env.del("CTF_BOT_FFA_DOCTRINE")
  let process =
    if isDocker:
      startProcess(
        "docker",
        args = [
          "run",
          "--rm",
          "--name",
          containerName,
          "--network=none",
          "-e",
          "COWORLD_PLAYER_WS_URL=ws://127.0.0.1:1/?slot=0",
          source["docker:".len .. ^1]
        ],
        env = env,
        options = {poStdErrToStdOut, poUsePath}
      )
    else:
      startProcess(
        source,
        env = env,
        options = {poStdErrToStdOut}
      )
  defer:
    if isDocker:
      removeContainer(containerName)
    if process.running:
      process.terminate()
    process.close()
  while not process.outputStream.atEnd():
    let line = process.outputStream.readLine()
    if line.contains("ffaDoctrine="):
      return line
  raise newException(
    ValueError,
    "policy output has no FFA doctrine marker: " & source
  )

if paramCount() < 2:
  raise newException(
    ValueError,
    "usage: extract_doctrine POLICY_BINARY_OR_DOCKER_IMAGE " &
    "EXPECTED_DOCTRINE " &
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
