import
  std/[os, strutils]

type
  BattleRoyaleError = object of CatchableError

proc startupLine(logPath: string): string
    {.raises: [IOError, BattleRoyaleError].} =
  ## Returns the policy startup line from a hosted agent log.
  for line in lines(logPath):
    if line.contains("ffaDoctrine="):
      return line
  raise newException(
    BattleRoyaleError,
    "hosted log has no FFA doctrine marker: " & logPath
  )

proc checkDoctrine(
  logPath: string,
  expectedDoctrine: string,
  expectedFragments: seq[string]
) {.raises: [IOError, BattleRoyaleError].} =
  ## Checks and prints the hosted policy startup marker.
  let
    line = startupLine(logPath)
    expected = "ffaDoctrine=" & expectedDoctrine
  if not line.contains(expected):
    raise newException(
      BattleRoyaleError,
      "expected " & expected & " in hosted log: " & line
    )
  for fragment in expectedFragments:
    if not line.contains(fragment):
      raise newException(
        BattleRoyaleError,
        "expected " & fragment & " in hosted log: " & line
      )
  echo line

if paramCount() < 2:
  raise newException(
    BattleRoyaleError,
    "usage: extract_hosted_doctrine AGENT_LOG EXPECTED_DOCTRINE " &
    "[EXPECTED_FRAGMENT ...]"
  )

var expectedFragments: seq[string]
for i in 3 .. paramCount():
  expectedFragments.add(paramStr(i))
checkDoctrine(paramStr(1), paramStr(2), expectedFragments)
