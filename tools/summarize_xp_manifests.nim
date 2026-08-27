import
  std/[algorithm, json, os, strutils, tables]

type
  VersionTotals = object
    requests: int
    episodes: int

proc addManifest(
  path: string,
  totals: var Table[string, VersionTotals]
) {.raises: [IOError, OSError, ValueError].} =
  ## Adds one hosted XP manifest to its evaluated policy version total.
  let
    manifest = parseFile(path)
    policyRef = manifest["roster"][0]["player"]["policy_ref"].getStr()
    episodes = manifest["num_episodes"].getInt()
  var version = totals.getOrDefault(policyRef)
  inc version.requests
  version.episodes += episodes
  totals[policyRef] = version

proc printTotals(totals: Table[string, VersionTotals]) =
  ## Prints hosted XP request and episode totals by evaluated policy version.
  var policyRefs: seq[string]
  for policyRef in totals.keys:
    policyRefs.add(policyRef)
  policyRefs.sort()
  var
    requests = 0
    episodes = 0
  for policyRef in policyRefs:
    let version = totals[policyRef]
    echo policyRef, "\t", version.requests, "\t", version.episodes
    requests += version.requests
    episodes += version.episodes
  echo "TOTAL\t", requests, "\t", episodes

if paramCount() != 1:
  raise newException(
    ValueError,
    "usage: summarize_xp_manifests MANIFEST_DIRECTORY"
  )

var totals: Table[string, VersionTotals]
for path in walkDirRec(paramStr(1)):
  if path.endsWith(".json"):
    addManifest(path, totals)
printTotals(totals)
