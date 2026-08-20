## The map ART bake: trench-edge noise art, rooftop/glass materials, the
## supersampled arena RGBA pair (renderArenaRgbaPair), layer loading
## (loadMapLayers) and the dark background. Consumed by global.nim and the
## endzone bake tool; nothing here is in gameHash. Stage 3 of
## docs/plans/2026-08-01-sim-split.md.

import
  std/[math, os],
  bitworld/aseprite, bitworld/server, bitworld/spriteprotocol, pixie,
  sim_types, rig_art, arena

const
  TrenchBevelPx = 8                          ## width of the pit's inner
                                             ## shadow bevel, px.
  TrenchLipColor = rgba(30, 22, 12, 255)     ## crisp dark cut line around
                                             ## the pit lip.
  TrenchLipAlpha = 185                       ## shadow strength at the lip...
  TrenchFloorAlpha = 95                      ## ...easing to this over the
                                             ## bevel and holding on the pit
                                             ## floor.
  TrenchEdgeWavePeriod = 9                   ## px between wander knots along
                                             ## a side of the cut line.
  TrenchEdgeWaveAmp = 3.5                    ## smooth in/out wander of the
                                             ## cut line, px.
  TrenchEdgeChipAmp = 1.0                    ## per-pixel nick on top of the
                                             ## wander, so the lip reads
                                             ## chipped, not machined.
  TrenchArtPadPx* = 5                        ## how far outside the exact
                                             ## gameplay square the dug art
                                             ## may reach; must stay >=
                                             ## WaveAmp + ChipAmp.

  PuddleRimColor = rgba(88, 24, 108, 255)    ## dark violet edge line tracing
                                             ## the spill — deliberately NO
                                             ## team's paint color, so the
                                             ## hazard reads neutral.
  PuddleFillTint = rgba(158, 48, 186, 235)   ## the near-opaque wet paint body.
  PuddleGlossTint = rgba(226, 150, 240, 90)  ## soft off-center sheen so the
                                             ## surface reads WET, not dyed
                                             ## floor.

proc overTint(base, tint: ColorRGBA): ColorRGBA =
  ## Alpha-composites a translucent tint over an opaque base color.
  ## (Moved from arena.nim in the round-2 audit: pure color math, art-only.)
  let a = tint.a.int
  rgba(
    uint8((base.r.int * (255 - a) + tint.r.int * a) div 255),
    uint8((base.g.int * (255 - a) + tint.g.int * a) div 255),
    uint8((base.b.int * (255 - a) + tint.b.int * a) div 255),
    255
  )

proc trenchEdgeNoise(seed, knot, salt: int): float =
  ## Deterministic hash noise in [-1, 1]: a pure function of its inputs (no
  ## RNG state), so the same trench bakes the same rough edge every run and
  ## replays match the live render.
  ## The prime mix MUST run in uint64: seed reaches tens of millions, so
  ## seed * 73856093 overflows the 32-bit `int` of the wasm32 replay viewer
  ## and the overflow check kills the whole viewer ("stuck warming up" —
  ## every map bakes trench art). uint64 wrap reproduces the exact bit
  ## pattern the original 64-bit signed math produced, keeping the baked
  ## edges byte-identical to already-recorded replays.
  let mixed = cast[uint64](seed) * 73856093'u64 xor
    cast[uint64](knot) * 19349663'u64 xor
    cast[uint64](salt) * 83492791'u64
  var h = uint32(mixed and 0x7FFFFFFF'u64)
  h = h xor (h shr 13)
  h = h * 0x85EBCA6B'u32
  h = h xor (h shr 16)
  float(h and 0xFFFF) / 32767.5 - 1.0

proc trenchEdgeWave(trench: MapRect, side, t: int): float =
  ## How far one side of the pit's cut line is displaced (px, + = outward)
  ## at along-coordinate t: cosine-interpolated value noise with knots every
  ## TrenchEdgeWavePeriod px, plus a per-pixel chip. Seeded off the trench's
  ## position, so each dig gets its own stable edge.
  let
    seed = (trench.x * 8191 + trench.y) * 4 + side
    k0 = floorDiv(t, TrenchEdgeWavePeriod)
    u = float(t - k0 * TrenchEdgeWavePeriod) / TrenchEdgeWavePeriod
    s = (1 - cos(u * PI)) / 2
    n0 = trenchEdgeNoise(seed, k0, 0)
    n1 = trenchEdgeNoise(seed, k0 + 1, 0)
  (n0 + (n1 - n0) * s) * TrenchEdgeWaveAmp +
    trenchEdgeNoise(seed, t, 1) * TrenchEdgeChipAmp



proc trenchRoughEdge*(trench: MapRect, x, y: int): float =
  ## Signed distance (px) from map pixel (x, y) to the trench's ROUGH edge:
  ## the gameplay square with each side's cut line displaced by
  ## trenchEdgeWave, corners rounding and chipping naturally via the min.
  ## Negative = undug ground, ~0 = the lip, growing toward the pit floor.
  ## The displacement never exceeds WaveAmp + ChipAmp, so the art stays
  ## within TrenchArtPadPx of the exact square.
  let
    dl = float(x - trench.x) + trenchEdgeWave(trench, 0, y)
    dr = float(trench.x + trench.w - 1 - x) + trenchEdgeWave(trench, 1, y)
    dt = float(y - trench.y) + trenchEdgeWave(trench, 2, x)
    db = float(trench.y + trench.h - 1 - y) + trenchEdgeWave(trench, 3, x)
  min(min(dl, dr), min(dt, db))

proc trenchArtColorAt(base: ColorRGBA, x, y: int): ColorRGBA =
  ## Returns the floor color with the trench art applied at logical (x, y):
  ## a dug pit — a crisp dark lip line tracing a rough, shovel-dug edge
  ## (trenchRoughEdge), an inner shadow bevel easing down from the lip, and
  ## a uniformly darkened sunken floor, so the recess reads at a glance.
  ## Cosmetic only — the collision masks and gameplay (trenchIndexAt) keep
  ## the exact square; the art wanders at most TrenchArtPadPx around it.
  for trench in ArenaTrenches:
    let tr = shapeAsRect(trench)
    if x < tr.x - TrenchArtPadPx or
        x >= tr.x + tr.w + TrenchArtPadPx or
        y < tr.y - TrenchArtPadPx or
        y >= tr.y + tr.h + TrenchArtPadPx:
      continue
    # Rect pits get the rough dug edge; other kinds fill flat (inside only).
    let edge =
      if trench.kind == shapeRect: trenchRoughEdge(tr, x, y)
      elif inShape(x, y, trench): float(TrenchBevelPx) + 1.0
      else: -1.0
    if edge < 0:
      continue                # undug ground inside the pad ring
    if edge < 1:
      return TrenchLipColor
    let
      depth = min(edge - 1, float(TrenchBevelPx))
      alpha = float(TrenchLipAlpha) -
        float(TrenchLipAlpha - TrenchFloorAlpha) * depth / float(TrenchBevelPx)
    return overTint(base, rgba(12, 9, 5, uint8(alpha)))
  base

proc puddleArtColorAt(base: ColorRGBA, x, y: int): ColorRGBA =
  ## Returns the floor color with paint-puddle art applied at logical (x, y).
  ## A puddle is a UNION of overlapping paint discs (the splat silhouette),
  ## and the spill outline IS the gameplay shape: pixels outside every disc
  ## stay clean floor, the union boundary's inner 2px trace a dark rim, and
  ## the body is near-opaque violet with an off-center sheen so the surface
  ## reads wet. The painted area therefore matches the damage area exactly.
  for puddle in ArenaPuddles:
    let pr = puddleBounds(puddle)
    if x < pr.x - 1 or x >= pr.x + pr.w + 1 or
        y < pr.y - 1 or y >= pr.y + pr.h + 1:
      continue
    ## Depth into the union: the deepest any single disc submerges the
    ## pixel (its radius minus the distance to its center). Negative =
    ## outside every disc; the union's boundary is depth 0.
    var depth = -1.0
    for s in puddle.spots:
      let
        dx = float(x - s.cx)
        dy = float(y - s.cy)
      depth = max(depth, float(s.r) - sqrt(dx * dx + dy * dy))
    if depth < 0.0:
      continue                # clean floor: the paint never leaves the splat
    if depth < 2.0:
      return PuddleRimColor
    var color = overTint(base, PuddleFillTint)
    # The sheen: an off-center inner ellipse, brightest toward its middle.
    let
      gx = float(x - (pr.x + pr.w * 2 div 5))
      gy = float(y - (pr.y + pr.h * 2 div 5))
      gr = float(min(pr.w, pr.h)) * 0.32
      gd = (gx * gx + gy * gy) / (gr * gr)
    if gd < 1.0:
      color = overTint(color, rgba(
        PuddleGlossTint.r, PuddleGlossTint.g, PuddleGlossTint.b,
        uint8(float(PuddleGlossTint.a) * (1.0 - gd))
      ))
    return color
  base

## --- FFA floor variety (battle-royale presentation only) ---
## The CTF board earns its large-scale color from the team endzones and
## pedestals; the FFA board drops all of that (withCtfPresentation = false)
## and was left as one flat grey field — walls, pits, and floor all within a
## narrow band of the same tone. These tints re-introduce large-scale,
## DETERMINISTIC variation for the battle-royale board only: low-frequency
## seed-derived ground zones (a cool slate drift against a warm earth drift),
## a paved plaza marking the center loot cluster, and a soft vignette toward
## the arena edge so the middle of the board reads brighter than the death
## ring's eventual home. Everything is a pure function of (genSeed, x, y) —
## no RNG state — so a seed bakes the same board every run and replays match
## the live render. Alphas stay low so the concrete texture shows through and
## the 16 player identity colors remain the most saturated thing on screen.
## Cosmetic only: collision/walk masks and gameplay geometry are untouched.
const
  FfaZoneCellPx = 148                        ## px between ground-zone knots.
  FfaZoneCoolTint = rgba(58, 76, 104, 255)   ## slate drift hue.
  FfaZoneWarmTint = rgba(134, 108, 66, 255)  ## dry-earth drift hue.
  FfaZoneHueAlpha = 52.0                     ## max hue-drift strength.
  FfaZoneMossTint = rgba(96, 116, 66, 255)   ## overgrown patches.
  FfaZoneMossAlpha = 40.0                    ## max overgrowth strength.
  FfaZoneLightTint = rgba(214, 208, 190, 255) ## pale worn patches.
  FfaZoneDarkTint = rgba(14, 16, 22, 255)    ## scorched/damp patches.
  FfaZoneShadeAlpha = 34.0                   ## max value-drift strength.
  FfaPlazaTint = rgba(196, 172, 108, 255)    ## center loot plaza wash.
  FfaPlazaAlpha = 30                         ## plaza wash strength.
  FfaPlazaRingAlpha = 110                    ## painted plaza boundary ring.
  FfaPlazaRingW = 4.0                        ## px width of that ring.
  FfaVignettePx = 90                         ## how far the edge shade reaches.
  FfaVignetteTint = rgba(6, 8, 14, 255)      ## edge shade color.
  FfaVignetteAlpha = 90.0                    ## edge shade strength at the wall.

proc ffaZoneHash(seed, gx, gy, salt: int): float =
  ## Deterministic 2D lattice noise in [-1, 1]: the same uint64 prime mix as
  ## trenchEdgeNoise (wasm32-safe), keyed by ground-zone knot coordinates.
  let mixed = cast[uint64](seed) * 2654435761'u64 xor
    cast[uint64](gx) * 73856093'u64 xor
    cast[uint64](gy) * 19349663'u64 xor
    cast[uint64](salt) * 83492791'u64
  var h = uint32(mixed and 0x7FFFFFFF'u64)
  h = h xor (h shr 13)
  h = h * 0x85EBCA6B'u32
  h = h xor (h shr 16)
  float(h and 0xFFFF) / 32767.5 - 1.0

proc ffaZoneNoise(seed, x, y, salt: int): float =
  ## Cosine-interpolated value noise over the FfaZoneCellPx lattice — smooth
  ## board-scale drifts, not per-pixel speckle.
  let
    gx = floorDiv(x, FfaZoneCellPx)
    gy = floorDiv(y, FfaZoneCellPx)
    ux = float(x - gx * FfaZoneCellPx) / FfaZoneCellPx
    uy = float(y - gy * FfaZoneCellPx) / FfaZoneCellPx
    sx = (1 - cos(ux * PI)) / 2
    sy = (1 - cos(uy * PI)) / 2
    n00 = ffaZoneHash(seed, gx, gy, salt)
    n10 = ffaZoneHash(seed, gx + 1, gy, salt)
    n01 = ffaZoneHash(seed, gx, gy + 1, salt)
    n11 = ffaZoneHash(seed, gx + 1, gy + 1, salt)
  (n00 + (n10 - n00) * sx) +
    ((n01 + (n11 - n01) * sx) - (n00 + (n10 - n00) * sx)) * sy

proc tintOver(acc, tint: ColorRGBA): ColorRGBA =
  ## Composites a translucent tint over an accumulated translucent tint, so a
  ## stack of washes collapses to ONE rgba whose overTint over any base equals
  ## applying the stack in order (straight-alpha src-over).
  let
    a1 = acc.a.int
    a2 = tint.a.int
    outA = a2 + a1 * (255 - a2) div 255
  if outA == 0:
    return rgba(0, 0, 0, 0)
  rgba(
    uint8((tint.r.int * a2 * 255 + acc.r.int * a1 * (255 - a2)) div (outA * 255)),
    uint8((tint.g.int * a2 * 255 + acc.g.int * a1 * (255 - a2)) div (outA * 255)),
    uint8((tint.b.int * a2 * 255 + acc.b.int * a1 * (255 - a2)) div (outA * 255)),
    uint8(outA))

proc ffaFloorTint(gameMap: CtfMap, x, y: int): ColorRGBA =
  ## The combined FFA floor wash for one LOGICAL pixel: ground-zone hue drift,
  ## worn/scorched value drift, the center loot plaza, and the edge vignette,
  ## pre-composited into a single rgba (see tintOver). Applying it is one
  ## overTint per pixel in the bake loops.
  let seed = gameMap.genSeed
  result = rgba(0, 0, 0, 0)
  # Hue drift: negative → cool slate, positive → warm earth.
  let hue = clamp(ffaZoneNoise(seed, x, y, 11), -1.0, 1.0)
  if hue < 0:
    result = tintOver(result, rgba(FfaZoneCoolTint.r, FfaZoneCoolTint.g,
      FfaZoneCoolTint.b, uint8(-hue * FfaZoneHueAlpha)))
  else:
    result = tintOver(result, rgba(FfaZoneWarmTint.r, FfaZoneWarmTint.g,
      FfaZoneWarmTint.b, uint8(hue * FfaZoneHueAlpha)))
  # Overgrown moss patches: a third, sparser channel — only the top of its
  # noise range grows anything, so moss reads as distinct islands, not a wash.
  let moss = ffaZoneNoise(seed, x + FfaZoneCellPx div 3,
    y - FfaZoneCellPx div 3, 37)
  if moss > 0.35:
    result = tintOver(result, rgba(FfaZoneMossTint.r, FfaZoneMossTint.g,
      FfaZoneMossTint.b, uint8(clamp((moss - 0.35) / 0.65, 0.0, 1.0) *
      FfaZoneMossAlpha)))
  # Value drift on an offset lattice so light/dark patches do not track the
  # hue zones one-for-one.
  let shade = clamp(ffaZoneNoise(seed, x + FfaZoneCellPx div 2,
    y + FfaZoneCellPx div 2, 23), -1.0, 1.0)
  if shade < 0:
    result = tintOver(result, rgba(FfaZoneDarkTint.r, FfaZoneDarkTint.g,
      FfaZoneDarkTint.b, uint8(-shade * FfaZoneShadeAlpha)))
  else:
    result = tintOver(result, rgba(FfaZoneLightTint.r, FfaZoneLightTint.g,
      FfaZoneLightTint.b, uint8(shade * FfaZoneShadeAlpha)))
  # The center loot plaza: a warm paved wash bounded by a painted ring at the
  # loot-cluster radius, so the hot zone reads at a glance.
  let
    dx = float(x - gameMap.center.x)
    dy = float(y - gameMap.center.y)
    d = sqrt(dx * dx + dy * dy)
  if d <= float(FfaLootRadius):
    if d >= float(FfaLootRadius) - FfaPlazaRingW:
      result = tintOver(result, rgba(FfaPlazaTint.r, FfaPlazaTint.g,
        FfaPlazaTint.b, FfaPlazaRingAlpha))
    else:
      result = tintOver(result, rgba(FfaPlazaTint.r, FfaPlazaTint.g,
        FfaPlazaTint.b, FfaPlazaAlpha))
  # Edge vignette: eases in over FfaVignettePx toward the perimeter wall.
  let edge = min(
    min(x - ArenaBorder, gameMap.width - 1 - ArenaBorder - x),
    min(y - ArenaBorder, gameMap.height - 1 - ArenaBorder - y))
  if edge < FfaVignettePx:
    let t = 1.0 - clamp(float(edge) / FfaVignettePx, 0.0, 1.0)
    result = tintOver(result, rgba(FfaVignetteTint.r, FfaVignetteTint.g,
      FfaVignetteTint.b, uint8(t * t * FfaVignetteAlpha)))

proc ffaFloorTintMap(gameMap: CtfMap): seq[ColorRGBA] =
  ## The FFA floor wash baked once at LOGICAL resolution; the scale× renderer
  ## indexes it per logical pixel (the wash is low-frequency by construction,
  ## so logical granularity is invisible at board scale).
  result = newSeq[ColorRGBA](gameMap.width * gameMap.height)
  for y in 0 ..< gameMap.height:
    for x in 0 ..< gameMap.width:
      result[y * gameMap.width + x] = ffaFloorTint(gameMap, x, y)

proc tileSample(tex: Image, x, y: int): ColorRGBA =
  ## Samples a seamless texture tiled across the arena (opaque source).
  tex.unsafe[x mod tex.width, y mod tex.height].rgba

proc tileSampleF(tex: Image, fx, fy: float): ColorRGBA =
  ## Bilinear tile sample at a fractional map-pixel coordinate (wrapping).
  ## The texture still tiles 1:1 with LOGICAL map pixels — a scale× renderer
  ## passes fractional coords, so the floor texture keeps its 1× world size but
  ## resolves smoothly between texels. At integer-center coords this returns
  ## exactly tileSample's nearest texel.
  let
    sx = fx - 0.5
    sy = fy - 0.5
    fx0 = floor(sx)
    fy0 = floor(sy)
    tx = sx - fx0
    ty = sy - fy0
    xa = ((int(fx0) mod tex.width) + tex.width) mod tex.width
    xb = (xa + 1) mod tex.width
    ya = ((int(fy0) mod tex.height) + tex.height) mod tex.height
    yb = (ya + 1) mod tex.height
    c00 = tex.unsafe[xa, ya].rgba
    c10 = tex.unsafe[xb, ya].rgba
    c01 = tex.unsafe[xa, yb].rgba
    c11 = tex.unsafe[xb, yb].rgba
  template lerp(a, b: uint8, t: float): float =
    a.float + (b.float - a.float) * t
  rgba(
    uint8(lerp(c00.r, c10.r, tx) + (lerp(c01.r, c11.r, tx) - lerp(c00.r, c10.r, tx)) * ty),
    uint8(lerp(c00.g, c10.g, tx) + (lerp(c01.g, c11.g, tx) - lerp(c00.g, c10.g, tx)) * ty),
    uint8(lerp(c00.b, c10.b, tx) + (lerp(c01.b, c11.b, tx) - lerp(c00.b, c10.b, tx)) * ty),
    255
  )

const PedestalDimFactor = 0.34
  ## How dark the powered-down (cold) pedestal disc goes: each lit pixel's RGB is
  ## scaled to this fraction so the disc reads as an unlit socket, not a bright
  ## team light, when the heart has been carried away. Alpha is untouched so the
  ## textured floor still shows through the same silhouette.

proc pedestalDimmed(spr: Image): Image =
  ## Returns a copy of a pedestal sprite with its RGB scaled down (alpha kept), so
  ## the "cold" map shows the pedestal powered down. The broadcast glow-fade
  ## crossfades the lit pedestal toward this, so the disc dims when the heart is
  ## taken and re-lights when it comes home. Pixie stores premultiplied alpha;
  ## scaling RGB uniformly keeps the premultiplication valid.
  result = newImage(spr.width, spr.height)
  for y in 0 ..< spr.height:
    for x in 0 ..< spr.width:
      let p = spr[x, y]
      result[x, y] = rgbx(
        uint8(p.r.float * PedestalDimFactor),
        uint8(p.g.float * PedestalDimFactor),
        uint8(p.b.float * PedestalDimFactor),
        p.a)

proc blitCover(dst, spr: Image, cx, cy, size: int) =
  ## Alpha-composites a cover-object sprite onto the board, centered on its
  ## collision shape and scaled to the shape's footprint (plus a little for the
  ## baked contact shadow). The sprite's transparency lets the textured floor
  ## show through; the board stays fully opaque (opaque dst + src-over).
  if size <= 0 or spr.width == 0:
    return
  let scaled = spr.resize(size, size)
  dst.draw(scaled, translate(vec2((cx - size div 2).float32,
                                  (cy - size div 2).float32)))

## --- Rooftop wall material (top-down building look from the collision mask) ---
## Every wall pixel — border frame, rect stub, diamond, disc, or chevron — is
## rendered as one coherent LOW-DETAIL BUILDING seen from above: a light
## parapet rim around the perimeter, a shadow line where the parapet drops to
## the roof, and a dark flat roof membrane crossed by subtle diagonal seams.
## The shading comes from each pixel's distance to the nearest floor pixel, so
## — like the carved-stone material it replaces — the art matches every
## collider EXACTLY and is identical on both halves by construction (the mask
## is mirror-symmetric; the world-space roof seams are the one deliberate
## exception, same as the glass sheen). Light comes from the up-left, so the
## up-left parapet run catches a highlight and the down-right run falls into
## shadow — the Gungeon/Nuclear-Throne top-down convention (L98). The
## buildings keep the cover's warm-tan family (REPLAY_DESIGN §3 warm-stone
## cover) so they pop off the neutral-grey concrete floor, and the team
## colors stay the only saturated channels.
const
  WallBevel = 3                          ## px width of the parapet rim band.
  RoofFace = rgba(110, 92, 72, 255)      ## flat warm roof (the old cover tan,
                                         ## a step darker so the rim pops).
  RoofSeam = rgba(97, 80, 62, 255)       ## diagonal membrane seam lines.
  RoofLip = rgba(56, 45, 35, 255)        ## shadow line where parapet meets roof.
  ParapetFace = rgba(152, 130, 104, 255) ## flat parapet top.
  ParapetHi = rgba(192, 169, 139, 255)   ## up-left lit parapet (catches light).
  ParapetLo = rgba(88, 72, 56, 255)      ## down-right shaded parapet.
  StoneInk = rgba(32, 27, 22, 255)       ## warm near-black ground line (never #000).
  RoofSeamPeriod = 16                    ## px between diagonal roof seams.

proc floorDistDir(wall: seq[bool], w, h, x, y, dx, dy, cap: int): int =
  ## Steps from (x, y) along (dx, dy) until the first floor (non-wall) pixel,
  ## capped at `cap`. Off-map counts as wall (the border is solid), so a pixel
  ## with no floor within `cap` in that direction returns cap + 1.
  for step in 1 .. cap:
    let
      nx = x + dx * step
      ny = y + dy * step
    if nx < 0 or ny < 0 or nx >= w or ny >= h:
      continue
    if not wall[ny * w + nx]:
      return step
  cap + 1

proc rooftopColorAt(
  wall: seq[bool], w, h, x, y, scale: int
): ColorRGBA =
  ## Shades one wall pixel as a low-detail rooftop: an ink ground line where
  ## the building meets the floor, a parapet rim lit toward the up-left light
  ## and shaded toward the down-right, a shadow line where the parapet drops
  ## inside, and a dark seamed roof membrane deep in the interior. The mask
  ## may be a `scale`× render of the arena; every band (ink line, parapet,
  ## lip) widens by `scale` so the material keeps its 1× proportions.
  let
    bevel = WallBevel * scale
    cap = bevel + scale                  ## parapet + the inner lip line.
    up = floorDistDir(wall, w, h, x, y, 0, -1, cap)
    left = floorDistDir(wall, w, h, x, y, -1, 0, cap)
    down = floorDistDir(wall, w, h, x, y, 0, 1, cap)
    right = floorDistDir(wall, w, h, x, y, 1, 0, cap)
    edge = min(min(up, down), min(left, right))
  if edge <= scale:
    return StoneInk                      ## touches the floor → ground outline.
  let
    topDist = min(up, left)              ## nearer the up-left (lit) rim.
    botDist = min(down, right)           ## nearer the down-right (shaded) rim.
  if edge <= bevel:
    ## Graded parapet rim: brightest at the outer edge (just inside the ink
    ## line), easing toward the flat parapet top by the rim width so the
    ## building edge reads raised, not painted.
    if topDist <= botDist:
      let t = (topDist - 2 * scale).float / max(1, bevel - 2 * scale).float
      mix(ParapetHi, ParapetFace, clamp(t, 0.0, 1.0))
    else:
      let t = (botDist - 2 * scale).float / max(1, bevel - 2 * scale).float
      mix(ParapetLo, ParapetFace, clamp(t, 0.0, 1.0))
  elif edge <= bevel + scale:
    RoofLip                              ## parapet drops to the roof.
  else:
    ## Roof membrane: flat dark field with subtle diagonal seams running
    ## down-left (perpendicular to the glass sheen streaks, so the two
    ## materials never read as one pattern).
    let
      period = RoofSeamPeriod * scale
      phase = ((x + y) mod period + period) mod period
    if phase < scale: RoofSeam else: RoofFace

proc rooftopColor(wall: seq[bool], w, h, x, y: int): ColorRGBA =
  ## 1× rooftop material (the baked collision-resolution map and spun diamonds).
  rooftopColorAt(wall, w, h, x, y, 1)

const
  ## Glass window material: a pale pane set in the same parapet frame language
  ## as the rooftop walls — a skylight in the building's face. The face targets
  ## palette index 1 (light gray) and the
  ## sheen streaks index 2 (near-white), so windows stay legible after the
  ## player-view palette quantization — glass must READ as see-through cover.
  GlassFace = rgba(198, 198, 196, 255)   ## flat pane; quantizes to palette 1.
  GlassSheen = rgba(240, 236, 226, 255)  ## diagonal streaks; quantizes to 2.

proc windowGlassColorAt(
  wall: seq[bool], w, h, x, y, scale: int
): ColorRGBA =
  ## Shades one glass window pixel: the same ink ground line and a thin
  ## parapet frame where the pane meets the floor (so windows sit in the
  ## rooftop wall language), then a pale pane crossed by 45-degree sheen
  ## streaks running down-right, perpendicular to the up-left light the
  ## parapet bevels use.
  ## Like rooftopColorAt, every band widens by `scale` so the material
  ## keeps its 1× screen proportions on the render-scale board.
  let
    frameCap = 2 * scale
    edge = min(
      min(
        floorDistDir(wall, w, h, x, y, 0, -1, frameCap),
        floorDistDir(wall, w, h, x, y, 0, 1, frameCap)
      ),
      min(
        floorDistDir(wall, w, h, x, y, -1, 0, frameCap),
        floorDistDir(wall, w, h, x, y, 1, 0, frameCap)
      )
    )
  if edge <= scale:
    return StoneInk                      ## touches the floor → carve outline.
  if edge <= frameCap:
    return ParapetFace                   ## thin parapet frame around the pane.
  let
    period = 24 * scale
    phase = ((x - y) mod period + period) mod period
  if phase < 3 * scale or phase in 7 * scale .. 9 * scale - 1:
    GlassSheen
  else:
    GlassFace

proc windowGlassColor(wall: seq[bool], w, h, x, y: int): ColorRGBA =
  ## 1× glass (the baked collision-resolution map the players observe).
  windowGlassColorAt(wall, w, h, x, y, 1)

var diamondFrameCache: array[DiamondSpinFrames, seq[tuple[
  scale: int, pixels: seq[uint8]]]]

proc rotatingDiamondSize*(radius: int): int =
  ## The LOGICAL (map-pixel) footprint of a spinning diamond sprite — the
  ## same value rotatingDiamondPixels returns, without building any pixels.
  2 * radius + 8

proc rotatingDiamondPixels*(
  radius, frame: int,
  scale = 1
): tuple[size: int, pixels: seq[uint8]] =
  ## One pre-rotated frame of a spinning center diamond, shaded with the same
  ## rooftop material as the baked walls: the mask is rotated, then the
  ## parapet bevel is re-derived from it, so the light stays up-left at every
  ## angle.
  ## The mask comes from rotatedDiamondCovers — the SAME predicate the
  ## collision, bullet, and vision masks stamp — so what a player sees is
  ## exactly what blocks them. `size` is the LOGICAL (map-pixel) footprint;
  ## `pixels` are rasterized at scale× that footprint — the analytic mask is
  ## evaluated per output pixel, so a scaled frame has genuinely smoother
  ## edges, not upscaled blocks.
  let size = 2 * radius + 8
  let index = diamondFrameIndex(frame)
  for cached in diamondFrameCache[index]:
    if cached.scale == scale:
      return (size, cached.pixels)
  let outSize = size * scale
  var mask = newSeq[bool](outSize * outSize)
  for y in 0 ..< outSize:
    for x in 0 ..< outSize:
      ## dx = x/scale - size/2, scaled by the shared denominator. The sprite
      ## blits at cx - size div 2, so this reduces to exactly (X - cx) in map
      ## pixels — the same offsets animatedDiamondCovers samples, at scale×
      ## resolution.
      mask[y * outSize + x] = rotatedDiamondCovers(
        radius, index,
        2 * x - size * scale,
        2 * y - size * scale,
        2 * scale)
  var pixels = newSeq[uint8](outSize * outSize * 4)
  for y in 0 ..< outSize:
    for x in 0 ..< outSize:
      if mask[y * outSize + x]:
        let
          color = rooftopColorAt(mask, outSize, outSize, x, y, scale)
          offset = (y * outSize + x) * 4
        pixels[offset] = color.r
        pixels[offset + 1] = color.g
        pixels[offset + 2] = color.b
        pixels[offset + 3] = 255
  diamondFrameCache[index].add((scale: scale, pixels: pixels))
  (size, pixels)

## --- Capture endzones (the floor a carrier must reach to score) ---
## The win condition is a full-height vertical column at each home edge: a live
## carrier scores the instant its center-x crosses the inner threshold, at ANY
## height (captureZoneXRange / checkWinConditions). We make that legible by
## painting the endzone INTO the floor — an in-world "painted endzone", not HUD
## chrome — so it rides the board sprite and scales with the locked composition.
## The old broad half-board territory wash was removed for muddying the flagstone
## into "gradient columns" (L98 #4); this is the opposite: a CONFINED tint inside
## the narrow scoring column only, anchored by a crisp bright threshold line at
## the exact x a carrier must cross. Cosmetic over mapImage → hash-safe.
const
  EndzoneCrackGlow = 165         ## ember alpha on the darkest crack pixels (kept
                                 ## below the pedestal glow so the flag home
                                 ## stays the brightest thing in the endzone).
  EndzoneLineAlpha = 220         ## solid threshold line at the exact score-x.
  EndzoneLineW = 3               ## px width of that threshold line.
  # The concrete floor texture (scripts/art/build_floor.py) is baked to a
  # luminance CONTRACT with these gates: the polished surface — including its
  # light panel-seam bevels — stays at lum 72..112 (at/above FaceLevel → NO
  # glow); only the hairline crack bottoms dip to ~32..34 (at/below CrackLevel
  # → full glow), with the crack tapers crossing the band and glowing partially.
  EndzoneFaceLevel = 66          ## polished-surface floor luminance (glow = 0).
  EndzoneCrackLevel = 34         ## joint/crack-bottom luminance (glow = full).
  EndzoneGlowFloor = 0.82        ## min home-falloff so the far end still glows.
  # The four *EndzoneColor team display colors moved to sim_types (they are
  # shared with the paint FX in sim_state, and hosting them here dragged the
  # whole art bake into the hash module's import DAG).

proc emberThroughCracks(base, ember: ColorRGBA, strength: float): ColorRGBA =
  ## Lets a team ember glow seep UP ONLY through the DARK joint/crack pixels of
  ## the concrete TEXTURE — the polished faces stay completely clean (no base
  ## wash), so team color is confined to the actual fissures/seams, not a flat
  ## tint over the tiles (L98 #4). Distinct from the solid capture LINE, which is
  ## a painted stripe. A two-point luminance gate anchored to the measured floor
  ## split does the confining; `strength` is a gentle pedestal-side falloff.
  let l = (base.r.int * 30 + base.g.int * 59 + base.b.int * 11) div 100
  # 0 at/above a polished face, 1 at/below a crack bottom — cracks only.
  let crack = clamp((EndzoneFaceLevel - l).float /
    (EndzoneFaceLevel - EndzoneCrackLevel).float, 0.0, 1.0)
  let a = strength * crack * crack * EndzoneCrackGlow.float
  overTint(base, rgba(ember.r, ember.g, ember.b, uint8(clamp(a, 0.0, 255.0))))

proc teamEndzoneColor(team: Team): ColorRGBA =
  ## Returns the floor-glow ember color for one team's endzone.
  case team
  of Red: RedEndzoneColor
  of Blue: BlueEndzoneColor
  of Green: GreenEndzoneColor
  of Yellow: YellowEndzoneColor

type EndzoneTint = object
  ## One team's precomputed endzone paint job: its capture-zone box, ember
  ## color, and which box edges are inner THRESHOLD edges (the map-border
  ## edges of the box are not thresholds and draw no line).
  zone: CaptureZone
  color: ColorRGBA
  boundLoX, boundHiX, boundLoY, boundHiY: bool

proc endzoneTints(gameMap: CtfMap): seq[EndzoneTint] =
  ## The active teams' endzone paint jobs, computed once per bake.
  for team in gameMap.teams():
    let zone = gameMap.captureZone(team)
    result.add EndzoneTint(
      zone: zone,
      color: teamEndzoneColor(team),
      boundLoX: zone.xLo > 0,
      boundHiX: zone.xHi < gameMap.width - 1,
      boundLoY: zone.yLo > 0,
      boundHiY: zone.yHi < gameMap.height - 1
    )

proc endzoneColorAt(
  tints: seq[EndzoneTint], base: ColorRGBA, x, y, playLo, playHi,
  playLoY, playHiY: int
): ColorRGBA =
  ## Tints one floor pixel if it sits inside a capture endzone. Team ember
  ## seeps up through the tile cracks, brightest at the pedestal (the inner
  ## threshold edge) and floored so the whole zone still glows; the exact
  ## threshold a carrier must cross gets a crisp solid line. Sides maps
  ## reproduce the classic two-column paint exactly; corner boxes fade on
  ## both axes and line both inner edges.
  for tint in tints:
    if not tint.zone.inCaptureZone(x, y):
      continue
    var
      onLine = false
      near = 1.0
    if tint.zone.diag:
      ## Diagonal corner zone: the threshold edge is the 45-degree L1
      ## shell; the ember is brightest at the line and eases toward the
      ## corner. The line band is one pixel wider in L1 so its diagonal
      ## stripe carries the same optical weight as the axis lines.
      let d = abs(x - tint.zone.cornerX) + abs(y - tint.zone.cornerY)
      if d > tint.zone.diagLimit - EndzoneLineW - 1:
        return overTint(base, rgba(tint.color.r, tint.color.g,
          tint.color.b, EndzoneLineAlpha))
      return emberThroughCracks(base, tint.color,
        EndzoneGlowFloor + (1.0 - EndzoneGlowFloor) *
          clamp(d.float / max(1, tint.zone.diagLimit).float, 0.0, 1.0))
    if tint.zone.disc:
      ## Compact ROUND endzone: the threshold is the painted ring, so the
      ## ember is brightest against it and eases in toward the pedestal —
      ## the same language as the diagonal corner zones.
      let d = sqrt(float(
        (x - tint.zone.anchorX) * (x - tint.zone.anchorX) +
        (y - tint.zone.anchorY) * (y - tint.zone.anchorY)))
      if d > float(tint.zone.radius - EndzoneLineW):
        return overTint(base, rgba(tint.color.r, tint.color.g,
          tint.color.b, EndzoneLineAlpha))
      return emberThroughCracks(base, tint.color,
        EndzoneGlowFloor + (1.0 - EndzoneGlowFloor) *
          clamp(d / max(1, tint.zone.radius).float, 0.0, 1.0))
    if tint.boundHiX:
      if x > tint.zone.xHi - EndzoneLineW:
        onLine = true
      near = min(near, clamp(
        (x - playLo).float / max(1, tint.zone.xHi - playLo).float, 0.0, 1.0))
    if tint.boundLoX:
      if x < tint.zone.xLo + EndzoneLineW:
        onLine = true
      near = min(near, clamp(
        (playHi - x).float / max(1, playHi - tint.zone.xLo).float, 0.0, 1.0))
    if tint.boundHiY:
      if y > tint.zone.yHi - EndzoneLineW:
        onLine = true
      near = min(near, clamp(
        (y - playLoY).float / max(1, tint.zone.yHi - playLoY).float, 0.0, 1.0))
    if tint.boundLoY:
      if y < tint.zone.yLo + EndzoneLineW:
        onLine = true
      near = min(near, clamp(
        (playHiY - y).float / max(1, playHiY - tint.zone.yLo).float, 0.0, 1.0))
    if onLine:
      return overTint(base, rgba(tint.color.r, tint.color.g,
        tint.color.b, EndzoneLineAlpha))
    return emberThroughCracks(base, tint.color,
      EndzoneGlowFloor + (1.0 - EndzoneGlowFloor) * near)
  base

proc shapeLogicalBounds(shape: ArenaShape): tuple[x0, y0, x1, y1: int] =
  ## A conservative logical-pixel bounding box around one obstacle shape (the
  ## scale× rasterizer only evaluates the float geometry inside it).
  case shape.kind
  of shapeRect:
    (shape.rect.x - 1, shape.rect.y - 1,
     shape.rect.x + shape.rect.w + 1, shape.rect.y + shape.rect.h + 1)
  of shapeDisc, shapeDiamond:
    (shape.cx - shape.radius - 1, shape.cy - shape.radius - 1,
     shape.cx + shape.radius + 1, shape.cy + shape.radius + 1)
  of shapeDiagonal:
    (min(shape.x0, shape.x1) - shape.thickness - 1,
     min(shape.y0, shape.y1) - shape.thickness - 1,
     max(shape.x0, shape.x1) + shape.thickness + 1,
     max(shape.y0, shape.y1) + shape.thickness + 1)
  of shapePolygon:
    if shape.points.len == 0:
      (0, 0, -1, -1)
    else:
      var
        x0 = shape.points[0].x
        y0 = shape.points[0].y
        x1 = shape.points[0].x
        y1 = shape.points[0].y
      for p in shape.points:
        x0 = min(x0, p.x); y0 = min(y0, p.y)
        x1 = max(x1, p.x); y1 = max(y1, p.y)
      (x0 - 1, y0 - 1, x1 + 1, y1 + 1)

proc renderArenaRgbaPair*(
  gameMap: CtfMap,
  scale: int,
  withCtfPresentation = true
): tuple[hot, cold: seq[uint8]] =
  ## The arena VISUAL rasterized natively at `scale`× map resolution for the
  ## spectator/replay renderer — real detail, not an upscale: wall shapes are
  ## re-evaluated from their float geometry per output pixel (crisp diagonal
  ## chevron/diamond edges), the rooftop parapet bevel grades over scale× more
  ## steps, the concrete floor resolves bilinearly between texels, and the
  ## pedestal art (600px masters) rasterizes at scale× its footprint. The
  ## endzone tint gates stay LOGICAL-column based, so the capture line and
  ## glow columns land exactly where the 1× map puts them. Collision masks are
  ## untouched — they come from loadMapLayers at 1× and stay byte-identical.
  ##
  ## Renders BOTH variants in one pass — `hot` (baked endzone glow, lit
  ## pedestals) and `cold` (glow + capture line omitted, pedestals dimmed, for
  ## the glow-fade overlay) — because they share the two expensive stages: the
  ## geometry mask (rasterized per obstacle bounding box, not by testing every
  ## shape at every output pixel) and the bilinear floor bake. The certifier
  ## boots this on a small CI runner, so the bake must stay a startup blip,
  ## not a first-viewer stall.
  let
    w = gameMap.width
    h = gameMap.height
    ow = w * scale
    oh = h * scale
    cx = gameMap.center.x
    cy = gameMap.center.y
    dir = gameDir()
    floorTex = readImage(dir / "data/arena_floor.png")
  var pedSprs: array[Team, Image]
  if withCtfPresentation:
    for team in gameMap.teams():
      pedSprs[team] = readImage(dir / "data/ped_" & teamText(team) & ".png")
  # The art mask at output resolution: border + obstacle shapes from float
  # geometry, minus the spinning center diamonds (drawn live as objects).
  # Window pixels (glass) get their own mask in the same per-shape pass: wall
  # points inside a window shape draw as the pale pane, not the rooftop
  # material.
  var
    artMask = newSeq[bool](ow * oh)
    windowMask = newSeq[bool](ow * oh)
  let
    bTop = ArenaBorder * scale
    bBottom = (h - ArenaBorder) * scale
    bLeft = ArenaBorder * scale
    bRight = (w - ArenaBorder) * scale
  for y in 0 ..< oh:
    if y < bTop or y >= bBottom:
      for x in 0 ..< ow:
        artMask[y * ow + x] = true
    else:
      for x in 0 ..< bLeft:
        artMask[y * ow + x] = true
      for x in bRight ..< ow:
        artMask[y * ow + x] = true
  for shape in ArenaObstacles:
    if gameMap.isSpinningDiamond(shape):
      continue
    let
      (sx0, sy0, sx1, sy1) = shapeLogicalBounds(shape)
      ox0 = max(0, sx0 * scale)
      oy0 = max(0, sy0 * scale)
      ox1 = min(ow, sx1 * scale)
      oy1 = min(oh, sy1 * scale)
    for y in oy0 ..< oy1:
      let fy = (float(y) + 0.5) / float(scale)
      for x in ox0 ..< ox1:
        let fx = (float(x) + 0.5) / float(scale)
        if shapeWallAtF(fx, fy, shape, cx, cy):
          artMask[y * ow + x] = true
          if shape.window:
            windowMask[y * ow + x] = true
  # The floor texture tiles the board with a period of exactly texW×texH LOGICAL
  # pixels, so the bilinear floor repeats every texW·scale × texH·scale output
  # pixels — bake ONE tile block and index it, instead of bilinear-sampling
  # 3.3M board pixels (this bake runs at container boot on a small contended
  # CI runner; every pass here is on the certifier's clock).
  let
    tileW = floorTex.width * scale
    tileH = floorTex.height * scale
  var tileBlock = newSeq[ColorRGBA](tileW * tileH)
  for y in 0 ..< tileH:
    let fy = (float(y) + 0.5) / float(scale)
    for x in 0 ..< tileW:
      tileBlock[y * tileW + x] =
        tileSampleF(floorTex, (float(x) + 0.5) / float(scale), fy)
  let
    tints = if withCtfPresentation: endzoneTints(gameMap) else: @[]
    ffaTints = if withCtfPresentation: @[] else: ffaFloorTintMap(gameMap)
    playLo = ArenaBorder
    playHi = w - 1 - ArenaBorder
    playLoY = ArenaBorder
    playHiY = h - 1 - ArenaBorder
  # Paint straight into the output byte buffers — the pixie Image round trip
  # (premultiply on write, un-premultiply on pack) was pure overhead for an
  # opaque board.
  result.hot = newSeq[uint8](ow * oh * 4)
  result.cold = newSeq[uint8](ow * oh * 4)
  template put(buf: seq[uint8], offset: int, c: ColorRGBA) =
    buf[offset] = c.r
    buf[offset + 1] = c.g
    buf[offset + 2] = c.b
    buf[offset + 3] = 255
  for y in 0 ..< oh:
    let
      ly = y div scale
      rowBorder = ly < ArenaBorder or ly >= h - ArenaBorder
      tileRow = (y mod tileH) * tileW
    for x in 0 ..< ow:
      let
        i = y * ow + x
        lx = x div scale
        onBorder = rowBorder or lx < ArenaBorder or lx >= w - ArenaBorder
      var hotColor, coldColor: ColorRGBA
      if artMask[i]:
        hotColor =
          if windowMask[i]:
            windowGlassColorAt(artMask, ow, oh, x, y, scale)
          else:
            rooftopColorAt(artMask, ow, oh, x, y, scale)
        coldColor = hotColor
      else:
        coldColor = tileBlock[tileRow + x mod tileW]
        # The FFA floor wash (ground zones, loot plaza, edge vignette) tints
        # the concrete before any pit/puddle art lands on it.
        if not withCtfPresentation:
          let wash = ffaTints[ly * w + lx]
          if wash.a > 0:
            coldColor = overTint(coldColor, wash)
        hotColor =
          if withCtfPresentation:
            endzoneColorAt(
              tints, coldColor, lx, ly, playLo, playHi, playLoY, playHiY)
          else:
            coldColor
        # The trench pit (config-gated trenches) paints over the finished floor on both
        # variants; it sits at the center, well clear of the endzone glow.
        coldColor = trenchArtColorAt(coldColor, lx, ly)
        hotColor = trenchArtColorAt(hotColor, lx, ly)
        # Paint puddles (config-gated hazards) spill over the floor the same
        # way, on top of any trench art they abut.
        coldColor = puddleArtColorAt(coldColor, lx, ly)
        hotColor = puddleArtColorAt(hotColor, lx, ly)
      if onBorder:
        hotColor = overTint(hotColor, ArenaBorderColor)
        coldColor = overTint(coldColor, ArenaBorderColor)
      put(result.hot, i * 4, hotColor)
      put(result.cold, i * 4, coldColor)
  # Pedestals: pixie still resizes the painted masters, but the composite onto
  # the board is a manual straight-alpha src-over into the byte buffers.
  if withCtfPresentation:
    for team in gameMap.teams():
      let
        home = gameMap.flagHome(team)
        full = pedSprs[team]
        size = PedestalCoverSize * scale
        scaled = full.resize(size, size)
        dimmed = scaled.pedestalDimmed()
        px0 = home.x * scale - size div 2
        py0 = home.y * scale - size div 2
      for sy in 0 ..< size:
        let dy = py0 + sy
        if dy < 0 or dy >= oh:
          continue
        for sx in 0 ..< size:
          let dx = px0 + sx
          if dx < 0 or dx >= ow:
            continue
          let
            litPx = scaled.data[sy * size + sx].rgba
            dimPx = dimmed.data[sy * size + sx].rgba
            offset = (dy * ow + dx) * 4
          template blend(buf: seq[uint8], src: ColorRGBA) =
            if src.a == 255'u8:
              buf[offset] = src.r
              buf[offset + 1] = src.g
              buf[offset + 2] = src.b
            elif src.a > 0'u8:
              let a = src.a.int
              buf[offset] =
                uint8((src.r.int * a + buf[offset].int * (255 - a)) div 255)
              buf[offset + 1] =
                uint8((src.g.int * a + buf[offset + 1].int * (255 - a)) div 255)
              buf[offset + 2] =
                uint8((src.b.int * a + buf[offset + 2].int * (255 - a)) div 255)
          blend(result.hot, litPx)
          blend(result.cold, dimPx)

proc loadMapLayers*(
  gameMap: CtfMap,
  withEndzoneGlow = true,
  withCtfPresentation = true
):
    tuple[mapImage, walkImage, wallImage: Image] =
  ## Builds the visual map plus the walk and wall masks for the arena. The
  ## visuals: a tiled top-down polished-concrete floor, and ONE coherent
  ## rooftop material for every wall pixel — border frame, rect stub, diamond,
  ## disc, and chevron alike — beveled from the collision mask itself so the
  ## art matches each collider EXACTLY and is identical on both halves by
  ## construction. The
  ## old side-view brick texture (sliced mid-course into the shapes → "torn
  ## ribbon" chevrons) and the three clashing prop sprites (wood crate /
  ## steampunk pipe / barrel scaled to a square over diamond/disc footprints)
  ## are gone (L98 #4: one baked material; let flags + pedestals carry team
  ## identity). Team pedestals stay. The walk/wall COLLISION masks are
  ## byte-identical to before — the art is cosmetic over the exact geometry.
  let
    w = gameMap.width
    h = gameMap.height
    cx = gameMap.center.x
    cy = gameMap.center.y
  result.mapImage = newImage(w, h)
  result.walkImage = newImage(w, h)
  result.wallImage = newImage(w, h)
  let
    clear = rgba(0, 0, 0, 0)
    opaque = rgba(255, 255, 255, 255)
    dir = gameDir()
    floorTex = readImage(dir / "data/arena_floor.png")
  var pedSprs: array[Team, Image]
  if withCtfPresentation:
    for team in gameMap.teams():
      pedSprs[team] = readImage(dir / "data/ped_" & teamText(team) & ".png")
  ## Pass 1: the boolean wall mask (border + obstacles), shared by the shading
  ## bevel and the collision masks so art and geometry can never disagree.
  ## Rasterized per shape (isArenaWall per pixel scans the whole obstacle
  ## list, which is minutes of shape tests on an oversize board).
  let installedProtected = proc (px, py: int): bool =
    isProtectedFloor(px, py, cx, cy)
  var wallMask = rasterizeRestWallMask(gameMap, ArenaObstacles,
    installedProtected)
  ## The static mask drops only the spinning shapes themselves. Any overlapping
  ## wall from another obstacle remains baked under the live sprite.
  let noSpinMask = rasterizeRestWallMask(gameMap, ArenaObstacles,
    installedProtected, includeSpinning = false)
  var artMask = wallMask
  for y in 0 ..< h:
    for x in 0 ..< w:
      if artMask[y * w + x] and isAnimatedDiamondPixel(x, y):
        artMask[y * w + x] = noSpinMask[y * w + x]
  ## Where glass CAN be: the union of the window shapes' footprints, painted
  ## once so the per-pixel glass test below is a mask read instead of an
  ## isArenaWindowPixel obstacle scan (same identity: glass = wall pixel
  ## covered by a window shape).
  var windowCover = newSeq[bool](w * h)
  for shape in ArenaObstacles:
    if not shape.window:
      continue
    let
      bounds = shapeBounds(shape)
      wx0 = max(bounds.x0, 0)
      wy0 = max(bounds.y0, 0)
      wx1 = min(bounds.x1, w - 1)
      wy1 = min(bounds.y1, h - 1)
    for y in wy0 .. wy1:
      for x in wx0 .. wx1:
        if inShape(x, y, shape):
          windowCover[y * w + x] = true
  ## Where trench art CAN reach: each pit's padded box. Outside these,
  ## trenchArtColorAt provably returns its input, so the floor loop skips the
  ## per-pixel trench scan.
  var trenchNear = newSeq[bool](w * h)
  for trench in ArenaTrenches:
    let tr = shapeAsRect(trench)
    for y in max(0, tr.y - TrenchArtPadPx) ..<
        min(h, tr.y + tr.h + TrenchArtPadPx):
      for x in max(0, tr.x - TrenchArtPadPx) ..<
          min(w, tr.x + tr.w + TrenchArtPadPx):
        trenchNear[y * w + x] = true
  ## Same fast-skip mask for the puddle spills.
  var puddleNear = newSeq[bool](w * h)
  for puddle in ArenaPuddles:
    let pr = puddleBounds(puddle)
    for y in max(0, pr.y - 1) ..< min(h, pr.y + pr.h + 1):
      for x in max(0, pr.x - 1) ..< min(w, pr.x + pr.w + 1):
        puddleNear[y * w + x] = true
  ## The capture endzones: the exact score-columns from checkWinConditions'
  ## captureZoneXRange (Red's inclusive right threshold, Blue's inclusive left),
  ## painted into the FLOOR below so a carrier can read where to run.
  let
    tints = if withCtfPresentation: endzoneTints(gameMap) else: @[]
    ffaTints = if withCtfPresentation: @[] else: ffaFloorTintMap(gameMap)
    playLo = ArenaBorder                     # inner playfield edges: the glow
    playHi = w - 1 - ArenaBorder             # anchors home, fades to the line.
    playLoY = ArenaBorder
    playHiY = h - 1 - ArenaBorder
  ## Pass 2: paint. Floor pixels sample the concrete tile; wall pixels are the
  ## rooftop material shaded from the mask. The perimeter frame is overlaid
  ## with the solid border color so the play space reads as a lit pit. Floor
  ## pixels inside a
  ## capture column get a CONFINED team endzone tint + a bright threshold line
  ## (endzoneColorAt) — not the removed broad half-board wash (L98 #4).
  for y in 0 ..< h:
    for x in 0 ..< w:
      let
        onBorder = x < ArenaBorder or y < ArenaBorder or
          x >= w - ArenaBorder or y >= h - ArenaBorder
        wall = wallMask[y * w + x]
        artWall = artMask[y * w + x]
        windowPixel = wall and windowCover[y * w + x]
      var color =
        if windowPixel: windowGlassColor(artMask, w, h, x, y)
        elif artWall: rooftopColor(artMask, w, h, x, y)
        elif withEndzoneGlow and withCtfPresentation: endzoneColorAt(tints,
          tileSample(floorTex, x, y), x, y, playLo, playHi, playLoY, playHiY)
        else: tileSample(floorTex, x, y)
      if not artWall and not windowPixel and not withCtfPresentation:
        # The FFA floor wash tints the concrete before pit/puddle art.
        let wash = ffaTints[y * w + x]
        if wash.a > 0:
          color = overTint(color, wash)
      if not wall and trenchNear[y * w + x]:
        # The trench pit (config-gated trenches) paints over the finished floor; it never
        # overlaps a wall (it sits inside the open center ring).
        color = trenchArtColorAt(color, x, y)
      if not wall and puddleNear[y * w + x]:
        # Paint puddles spill over the floor the same way.
        color = puddleArtColorAt(color, x, y)
      if onBorder:
        color = overTint(color, ArenaBorderColor)
      result.mapImage[x, y] = color
      ## The collision layers drop the spinning diamonds for the same reason
      ## the art does: their footprint is not static. initSimServer keeps this
      ## diamond-free bake as the BASE and stamps the live rotated footprint
      ## over it every time the spin frame advances (applyDiamondGeometry).
      let collisionWall = artWall
      result.walkImage[x, y] = if collisionWall: clear else: opaque
      result.wallImage[x, y] = if collisionWall: opaque else: clear
  ## Carved team pedestal under each flag home (walkable — sits inside the
  ## protected spawn pocket; cosmetic only, collision masks untouched). With the
  ## glow OFF this is the "cold" map: the pedestal art is dimmed to a powered-down
  ## disc (see pedestalDimmed) so the broadcast crossfade dims the disc along with
  ## the floor glow when the heart is gone — otherwise a hot==cold pedestal never
  ## fades. The RGB/hot map (withEndzoneGlow) keeps the pedestal at full light.
  if withCtfPresentation:
    for team in gameMap.teams():
      let
        home = gameMap.flagHome(team)
        full = pedSprs[team]
        spr = if withEndzoneGlow: full else: full.pedestalDimmed()
      blitCover(result.mapImage, spr, home.x, home.y, PedestalCoverSize)

proc coldEndzoneMapRgba*(gameMap: CtfMap): seq[uint8] =
  ## Builds the map RGBA with the endzone crack-glow and capture line OMITTED —
  ## the "power source is gone" cold floor. Same layout/format as `sim.mapRgba`
  ## (walls, border, pedestals identical), so a broadcast overlay can crossfade
  ## the baked-glow map toward this and only the glow + line visibly change.
  ## Cosmetic, spectator-only: it is NOT the map the player POV / RL agents see.
  let (mapImage, _, _) = loadMapLayers(gameMap, withEndzoneGlow = false)
  result = newSeq[uint8](MapWidth * MapHeight * 4)
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      let
        pixel = mapImage[x, y]
        offset = (y * MapWidth + x) * 4
      result[offset] = pixel.r
      result[offset + 1] = pixel.g
      result[offset + 2] = pixel.b
      result[offset + 3] = pixel.a

proc loadDarkBgPixels*(): seq[uint8] =
  ## Loads the dark interstitial background as palette pixels.
  let image = readAsepriteImage(gameDir() / DarkBgPath)
  if image.width != ScreenWidth or image.height != ScreenHeight:
    raise newException(
      CtfError,
      DarkBgPath & " must be " & $ScreenWidth & "x" & $ScreenHeight & "."
    )
  result = newSeq[uint8](ScreenWidth * ScreenHeight)
  for y in 0 ..< ScreenHeight:
    for x in 0 ..< ScreenWidth:
      let color = nearestPaletteIndex(image[x, y])
      result[y * ScreenWidth + x] =
        if color == TransparentColorIndex: SpaceColor else: color
