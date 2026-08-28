type
  VisionPoint* = object
    x*, y*: float

  DiamondBox* = object
    x0*, y0*, x1*, y1*: int

proc contains*(box: DiamondBox, x, y: int): bool {.inline.} =
  x >= box.x0 and x < box.x1 and y >= box.y0 and y < box.y1

proc pointInAnyDiamond*(boxes: openArray[DiamondBox], x, y: int): bool =
  for box in boxes:
    if box.contains(x, y):
      return true
  false

proc maskRayClear*(
    mask: openArray[bool],
    w, h: int,
    boxes: openArray[DiamondBox],
    a, b: VisionPoint
): bool =
  let
    ax = int(a.x)
    ay = int(a.y)
    bx = int(b.x)
    by = int(b.y)
    steps = max(abs(bx - ax), abs(by - ay))
  if steps == 0:
    return true
  for s in 1 .. steps:
    let
      x = ax + (bx - ax) * s div steps
      y = ay + (by - ay) * s div steps
    if x < 0 or y < 0 or x >= w or y >= h:
      return false
    if pointInAnyDiamond(boxes, x, y):
      continue
    if not mask[y * w + x]:
      return false
  true

proc shotAllowed*(
    sightingConfirmed: bool,
    mask: openArray[bool],
    w, h: int,
    boxes: openArray[DiamondBox],
    a, b: VisionPoint
): bool =
  if sightingConfirmed:
    return true
  maskRayClear(mask, w, h, boxes, a, b)
