## Renders every curated-pool map to an annotated PNG plus a JSON manifest
## for the pool-review page: floor/stone/glass like dump_map_mask, with the
## protected zones tinted, pedestal positions dotted, and the med-kit
## candidate/active points marked.
## Usage: nim c -r tools/render_map_pool.nim [--br] [outDir]
## Demo/curation tooling; not part of the server.
import
  std/[json, md5, os, sequtils, strformat],
  pixie,
  ../src/ctf/[map_pool, sim],
  map_render

proc centerData(gameMap: CtfMap): tuple[
    wall, trench, puddle: string, kits: seq[MapPoint]] =
  let
    centerX = gameMap.width div 2
    centerY = gameMap.height div 2
    radius2 = BrCenterKeepOut * BrCenterKeepOut
    obstacles = buildArenaObstacles(gameMap)
    wallMask = rasterizeRestWallMask(
      gameMap,
      obstacles,
      proc (x, y: int): bool = mapProtectedFloorAt(gameMap, x, y),
    )
  for y in centerY - BrCenterKeepOut .. centerY + BrCenterKeepOut:
    for x in centerX - BrCenterKeepOut .. centerX + BrCenterKeepOut:
      let
        dx = x - centerX
        dy = y - centerY
      if dx * dx + dy * dy > radius2:
        continue
      let index = y * gameMap.width + x
      result.wall.add char(if wallMask[index]: 1 else: 0)
      var trench, puddle: bool
      for shape in gameMap.trenches:
        if inShape(x, y, shape):
          trench = true
          break
      for item in gameMap.puddles:
        if inPuddle(x, y, item):
          puddle = true
          break
      result.trench.add char(if trench: 1 else: 0)
      result.puddle.add char(if puddle: 1 else: 0)
  for point in gameMap.medKitCandidates:
    let
      dx = point.x - centerX
      dy = point.y - centerY
    if dx * dx + dy * dy <= radius2:
      result.kits.add point

proc centerChecksum(gameMap: CtfMap): string =
  let data = centerData(gameMap)
  var encoded = data.wall & "\x00" & data.trench & "\x00" & data.puddle
  for point in data.kits:
    encoded.add "\x00" & $point.x & "," & $point.y
  $toMD5(encoded)

when isMainModule:
  let br = paramCount() >= 1 and paramStr(1) == "--br"
  let outDir =
    if br:
      if paramCount() >= 2: paramStr(2) else: "brpool-preview"
    elif paramCount() >= 1:
      paramStr(1)
    else:
      "pool-preview"
  createDir(outDir)
  var manifest = newJArray()
  let seeds = if br: BrMapPoolSeeds.toSeq else: MapPoolSeeds.toSeq
  for i, seed in seeds:
    let
      gameMap =
        if br:
          brPoolCtfMap(i, brCanonicalOverrides())
        else:
          loadCtfMapMetadata("gen:" & $seed)
      renderOptions = MapRenderOptions(
        maxDimension: (if br: 1600 else: 0),
        overlays: {overlayProtected, overlayPickups},
        pickupKinds: {pickupMedKitActive, pickupMedKitCandidate},
      )
    doAssert gameMap.genSeed == seed, "pool seed rolled forward: " & $seed
    let img = renderMap(gameMap, renderOptions).image
    let name = &"pool-{i:02}-seed-{seed}.png"
    img.writeFile(outDir / name)
    var kits = newJArray()
    for p in gameMap.medKitSpawns:
      kits.add %*[p.x, p.y]
    var candidates = newJArray()
    for p in gameMap.medKitCandidates:
      candidates.add %*[p.x, p.y]
    var entry = %*{
      "index": i,
      "seed": seed,
      "file": name,
      "width": gameMap.width,
      "height": gameMap.height,
      "symmetry": (
        if gameMap.symmetry == symMirror: "mirror" else: "rot180"),
      "endzone": (
        case gameMap.endzone
        of ezColumn: "column"
        of ezDisc: "disc"
        of ezSquare: "square"),
      "endzoneRadius": gameMap.endzoneRadius,
      "homeX": gameMap.teamHomeX(Red),
      "obstacles": gameMap.leftObstacles.len,
      "trenches": gameMap.trenches.len,
      "medKitSpawns": kits,
      "medKitCandidates": candidates,
    }
    if br:
      let
        thumbnailOptions = MapRenderOptions(
          maxDimension: 320,
          overlays: {overlayProtected, overlayPickups},
          pickupKinds: {pickupMedKitActive, pickupMedKitCandidate},
        )
        thumbnailName = &"thumb-{i:02}-seed-{seed}.png"
      renderMap(gameMap, thumbnailOptions).image.writeFile(
        outDir / thumbnailName)
      entry["thumbnail"] = %thumbnailName
      entry["centerChecksum"] = %centerChecksum(gameMap)
    manifest.add entry
    echo "rendered ", name
  if br:
    let
      reference = generateMapAttempt(BrCanonicalCenterSeed, brCanonicalOverrides())
      options = MapRenderOptions(
        maxDimension: 1600,
        overlays: {overlayProtected, overlayPickups},
        pickupKinds: {pickupMedKitActive, pickupMedKitCandidate},
      )
    renderMap(reference, options).image.writeFile(
      outDir / "br-canonical-reference.png")
    echo "rendered br-canonical-reference.png"
  writeFile(outDir / "manifest.json", pretty(manifest))
  echo "wrote ", outDir / "manifest.json"
