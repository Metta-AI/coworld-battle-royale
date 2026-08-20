## Renders the baked arena board (the spectator/replay visual) for a config
## file to a PNG — the fastest way to iterate on the map-art palette without
## booting a server. Renders the HOT variant of renderArenaRgbaPair at the
## requested scale, honoring the config's mode (FFA boards drop the CTF
## presentation exactly like the live server does).
## Usage: nim c -d:release -r tools/render_ffa_board.nim <config.json> <out.png> [scale]
## Demo/curation tooling; not part of the server.
import std/[os, strutils], pixie, ../src/ctf/sim

when isMainModule:
  if paramCount() < 2:
    quit("Usage: render_ffa_board <config.json> <out.png> [scale]")
  let
    cfgPath = paramStr(1)
    outPath = paramStr(2)
    scale = if paramCount() >= 3: parseInt(paramStr(3)) else: 1
  var config = defaultGameConfig()
  config.update(readFile(cfgPath))
  let gameMap = loadCtfMap(config)
  let pair = renderArenaRgbaPair(
    gameMap, scale, withCtfPresentation = not config.isFfa())
  let
    w = gameMap.width * scale
    h = gameMap.height * scale
  var img = newImage(w, h)
  for i in 0 ..< w * h:
    img.data[i] = rgbx(
      pair.hot[i * 4], pair.hot[i * 4 + 1], pair.hot[i * 4 + 2], 255)
  img.writeFile(outPath)
  echo "wrote ", outPath, " (", w, "x", h, ")"
