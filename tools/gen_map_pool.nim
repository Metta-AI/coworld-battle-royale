## Regenerates src/ctf/map_pool.nim: scans seeds upward and keeps the first
## ones whose map passes every validator on the FIRST attempt (so the pool
## entry IS the map — no re-roll drift if validators tighten later), under
## small size-class and endzone-shape quotas for variety.
## Usage: nim c -r tools/gen_map_pool.nim [startSeed]
## Demo/curation tooling; not part of the server.
import std/[os, strutils, strformat], ../src/ctf/sim

const
  PoolSize = 20
  BrPoolSize = 256
  SizeQuota = [4, 5, 4, 4, 3]  ## small, standard, large, huge, giant.
  ShapeQuota = [10, 5, 5]      ## column, disc, square.

proc sizeClassIndex(gameMap: CtfMap): int =
  case gameMap.width
  of 1050: 0
  of 1235: 1
  of 1606: 2
  of 2223: 3
  of 3211: 4
  else:
    raise newException(CtfError, "Unexpected map width: " & $gameMap.width)

proc shapeIndex(gameMap: CtfMap): int =
  case gameMap.endzone
  of ezColumn: 0
  of ezDisc: 1
  of ezSquare: 2

when isMainModule:
  let start = if paramCount() >= 1: parseInt(paramStr(1)) else: 1001
  var
    seeds: seq[int]
    counts = [0, 0, 0, 0, 0]
    shapeCounts = [0, 0, 0]
    seed = start
    scanned, rejected = 0
  while seeds.len < PoolSize:
    let gameMap = generateMapAttempt(seed, MapGenOverrides(windows: -1, pits: -1, pitDensity: -1))
    inc scanned
    let reason = validateGeneratedMap(gameMap)
    if reason.len > 0:
      inc rejected
      echo &"seed={seed} REJECT {reason}"
    else:
      let
        sizeIndex = gameMap.sizeClassIndex()
        shape = gameMap.shapeIndex()
      if counts[sizeIndex] < SizeQuota[sizeIndex] and
          shapeCounts[shape] < ShapeQuota[shape]:
        seeds.add seed
        inc counts[sizeIndex]
        inc shapeCounts[shape]
        echo &"pool[{seeds.len - 1}] seed={seed} " &
          &"{gameMap.width}x{gameMap.height} sym={gameMap.symmetry} " &
          &"endzone={gameMap.endzone} r={gameMap.endzoneRadius} " &
          &"home={gameMap.teamHomeX(Red)} " &
          &"obstacles={gameMap.leftObstacles.len}"
      else:
        echo &"seed={seed} ok but quota full"
    stdout.flushFile()
    inc seed
  echo &"scanned={scanned} rejected={rejected}"

  let
    brOverrides = brCanonicalOverrides()
    canonical = generateMapAttempt(BrCanonicalCenterSeed, brOverrides)
  var
    brSeeds: seq[int]
    brSeed = 3001
    brScanned, brRejected = 0
  proc centerMatches(candidate, reference: CtfMap): bool =
    let
      centerX = candidate.width div 2
      centerY = candidate.height div 2
      radius2 = BrCenterKeepOut * BrCenterKeepOut
      x0 = max(0, centerX - BrCenterKeepOut)
      y0 = max(0, centerY - BrCenterKeepOut)
      x1 = min(candidate.width - 1, centerX + BrCenterKeepOut)
      y1 = min(candidate.height - 1, centerY + BrCenterKeepOut)
      candidateObstacles = buildArenaObstacles(candidate)
      referenceObstacles = buildArenaObstacles(reference)
    for y in y0 .. y1:
      for x in x0 .. x1:
        let
          dx = x - centerX
          dy = y - centerY
        if dx * dx + dy * dy > radius2:
          continue
        if mapWallAt(candidate, candidateObstacles, x, y) !=
            mapWallAt(reference, referenceObstacles, x, y):
          return false
        var candidateTrench, referenceTrench: bool
        for trench in candidate.trenches:
          if inShape(x, y, trench):
            candidateTrench = true
            break
        for trench in reference.trenches:
          if inShape(x, y, trench):
            referenceTrench = true
            break
        if candidateTrench != referenceTrench:
          return false
        var candidatePuddle, referencePuddle: bool
        for puddle in candidate.puddles:
          if inPuddle(x, y, puddle):
            candidatePuddle = true
            break
        for puddle in reference.puddles:
          if inPuddle(x, y, puddle):
            referencePuddle = true
            break
        if candidatePuddle != referencePuddle:
          return false
    var candidateKits, referenceKits: seq[MapPoint]
    for point in candidate.medKitCandidates:
      let dx = point.x - centerX
      let dy = point.y - centerY
      if dx * dx + dy * dy <= radius2:
        candidateKits.add point
    for point in reference.medKitCandidates:
      let dx = point.x - centerX
      let dy = point.y - centerY
      if dx * dx + dy * dy <= radius2:
        referenceKits.add point
    candidateKits == referenceKits

  while brSeeds.len < BrPoolSize:
    let raw = generateMapAttempt(brSeed, brOverrides)
    inc brScanned
    var reason = ""
    if raw.width != canonical.width or raw.height != canonical.height or
        raw.symmetry != canonical.symmetry or
        raw.endzone != canonical.endzone or
        raw.endzoneRadius != canonical.endzoneRadius:
      reason = "dimensions/symmetry/endzone mismatch"
    else:
      reason = validateGeneratedMap(raw)
      if reason.len == 0:
        var stamped = raw
        stamped.stampBrCanonicalCenter(canonical)
        reason = validateGeneratedMap(stamped)
        if reason.len == 0 and not centerMatches(stamped, canonical):
          reason = "canonical center mismatch after stamp"
    if reason.len > 0:
      inc brRejected
      echo &"br seed={brSeed} REJECT {reason}"
    else:
      brSeeds.add brSeed
      echo &"brpool[{brSeeds.len - 1}] seed={brSeed} " &
        &"{canonical.width}x{canonical.height} sym={canonical.symmetry} " &
        &"endzone={canonical.endzone} r={canonical.endzoneRadius}"
    stdout.flushFile()
    inc brSeed
  echo &"br scanned={brScanned} rejected={brRejected}"

  var lines = @[
    "## GENERATED by `nim c -r tools/gen_map_pool.nim` — do not edit by hand.",
    "## The curated terrain pool: seeds whose generated maps pass every " &
      "validator",
    "## on their FIRST attempt (so the pool entry IS the map, no re-roll " &
      "drift).",
    "",
    "const MapPoolSeeds*: array[" & $PoolSize & ", int] = [",
  ]
  for i in countup(0, PoolSize - 1, 10):
    var chunk: seq[string]
    for j in i ..< min(i + 10, PoolSize):
      chunk.add $seeds[j]
    lines.add "  " & chunk.join(", ") & ","
  lines.add "]"
  lines.add ""
  lines.add "const BrMapPoolSeeds*: array[" & $BrPoolSize & ", int] = ["
  for i in countup(0, BrPoolSize - 1, 8):
    var chunk: seq[string]
    for j in i ..< min(i + 8, BrPoolSize):
      chunk.add $brSeeds[j]
    lines.add "  " & chunk.join(", ") & ","
  lines.add "]"
  let outPath =
    currentSourcePath.parentDir.parentDir / "src" / "ctf" / "map_pool.nim"
  writeFile(outPath, lines.join("\n") & "\n")
  echo "wrote ", outPath
