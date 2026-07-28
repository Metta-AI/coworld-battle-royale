import
  std/os,
  ctf/sim

## Verifies the rotating center diamonds block movement, shots, and vision.
## Usage: nim r tools/diamond_probe.nim  (from the repo root)

when isMainModule:
  let simServer = initSimServer(defaultGameConfig())
  echo "animated diamonds: ", AnimatedDiamonds.len
  var bad = 0
  for spot in AnimatedDiamonds:
    let
      leftX = spot.cx - spot.radius - 8
      rightX = spot.cx + spot.radius + 8
      y = spot.cy
      centerWall = simServer.wallMask[mapIndex(spot.cx, spot.cy)]
      losClear = simServer.lineOfSightClear(leftX, y, rightX, y)
      fovOpaque = simServer.fovBlocked[
        (spot.cy div FovCellSize) * FovGridW + spot.cx div FovCellSize]
      walkable = simServer.walkMask[mapIndex(spot.cx, spot.cy)]
    echo "diamond (", spot.cx, ",", spot.cy, ") r=", spot.radius,
      " wall=", centerWall,
      " shotBlocked=", not losClear,
      " fovBlocked=", fovOpaque,
      " walkable=", walkable
    if not centerWall or losClear or not fovOpaque or walkable:
      inc bad
  if bad > 0:
    echo "PROBLEM: ", bad, " diamonds are not full cover"
    quit(1)
  echo "all diamonds are full cover (move+shot+vision blocked)"
