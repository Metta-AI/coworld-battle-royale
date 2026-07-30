## Renders the PERMANENT terrain paint buildup over a match to PNGs, so the
## "corridors covered in paint by the end" effect can be judged by eye instead
## of inferred from stain counts.
##
## Plays a recorded replay (real bot traffic, so the paint lands where players
## actually fight) and composites the REAL broadcast packet at several ticks —
## the offline eyes-on pattern from tools/render_frame.nim: decode every sprite,
## sort the map-layer objects by z, blit at obj.x/obj.y.
##
## Usage: nim r tools/stain_probe.nim <replay.bitreplay> <outDir> [tick,tick,..]
import
  std/[algorithm, os, sequtils, strutils],
  pixie, supersnappy,
  bitworld/spriteprotocol,
  ../src/ctf/global, ../src/ctf/replays, ../src/ctf/sim

proc renderBoard(sim: var SimServer, state: var GlobalViewerState): Image =
  ## Composites one real broadcast frame into an image, at board scale.
  var next: GlobalViewerState
  let messages = sim.buildSpriteProtocolUpdates(state, next).parseSpritePacket()
  state = next
  # The packet is a DELTA: sprites/objects defined on earlier frames are not
  # re-sent (that is the whole point of the stain design), so the probe has to
  # accumulate exactly like the client does.
  var sprites {.global.}: seq[tuple[id: int, image: Image]]
  var objects {.global.}: seq[SpritePacketObject]
  proc putSprite(id: int, image: Image) =
    for i in 0 ..< sprites.len:
      if sprites[i].id == id:
        sprites[i].image = image
        return
    sprites.add((id, image))
  proc spriteImage(id: int): Image =
    for s in sprites:
      if s.id == id:
        return s.image
    nil
  for m in messages:
    case m.kind
    of spkSprite:
      let raw = supersnappy.uncompress(m.sprite.compressedPixels)
      if raw.len < m.sprite.width * m.sprite.height * 4:
        continue                      # palette sprite (UI); board art is RGBA.
      var image = newImage(m.sprite.width, m.sprite.height)
      for y in 0 ..< m.sprite.height:
        for x in 0 ..< m.sprite.width:
          let i = y * m.sprite.width + x
          image[x, y] = rgba(
            raw[i * 4 + 0], raw[i * 4 + 1], raw[i * 4 + 2], raw[i * 4 + 3]
          )
      putSprite(m.sprite.id, image)
    of spkObject:
      var replaced = false
      for i in 0 ..< objects.len:
        if objects[i].id == m.objectDef.id:
          objects[i] = m.objectDef
          replaced = true
          break
      if not replaced:
        objects.add(m.objectDef)
    of spkDeleteObject:
      for i in 0 ..< objects.len:
        if objects[i].id == m.objectId:
          objects.delete(i)
          break
    of spkClearObjects:
      objects.setLen(0)
    else:
      discard

  # The board layer is the one carrying the full-width map bands.
  var mapLayer = 0
  var bandIds: seq[int]
  for s in sprites:
    if s.image.width == MapWidth * RenderScale:
      bandIds.add(s.id)
  for obj in objects:
    if obj.spriteId in bandIds:
      mapLayer = obj.layer
  var ordered: seq[SpritePacketObject]
  for obj in objects:
    if obj.layer == mapLayer:
      ordered.add(obj)
  # Client order: z, then y, then id.
  ordered.sort(proc (a, b: SpritePacketObject): int =
    result = cmp(a.z, b.z)
    if result == 0: result = cmp(a.y, b.y)
    if result == 0: result = cmp(a.id, b.id))

  result = newImage(MapWidth * RenderScale, MapHeight * RenderScale)
  result.fill(rgba(20, 18, 16, 255))
  for obj in ordered:
    let image = spriteImage(obj.spriteId)
    if image.isNil:
      continue
    result.draw(image, translate(vec2(float32(obj.x), float32(obj.y))))

proc main() =
  let
    replayPath = paramStr(1)
    outDir = paramStr(2)
    ticks =
      if paramCount() >= 3: paramStr(3).split(',').map(parseInt)
      else: @[1, 600, 1500, 3000, 100_000]
  createDir(outDir)
  let data = loadReplay(replayPath)
  var config = defaultGameConfig()
  config.update(data.configJson)
  var sim = initSimServer(config)
  sim.gameEventLoggingEnabled = false
  var replay = initReplayPlayer(data)
  replay.looping = false
  replay.mismatchQuit = false

  var state = initGlobalViewerState()
  var shotFor: seq[int]
  for target in ticks.sorted():
    while sim.tickCount < target and sim.tickCount < replay.replayMaxTick():
      replay.stepReplay(sim)
    let image = renderBoard(sim, state)
    let path = outDir / "stains-t" & align($sim.tickCount, 5, '0') & ".png"
    image.writeFile(path)
    echo "tick ", sim.tickCount, ": stains=", sim.paintStains.len,
      " sent=", state.stainsSent, " -> ", path
    shotFor.add(sim.tickCount)
    if sim.tickCount >= replay.replayMaxTick():
      break

main()
