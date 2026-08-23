## Overlays the DRAWN spray mist on the DAMAGE ENVELOPE, on the real FFA board,
## so containment is judged in pixels rather than argued in prose.
##
## Two outlines are stroked over a real rendered burst:
##   - the CENTERLINE cone (PlasmaArcReach / PlasmaArcMaxWidth), the wedge the
##     damage geometry is written against;
##   - the ENVELOPE, that cone widened by PlasmaArcBodyRadius — the region where
##     a cog CENTERED on a painted pixel loses hp, because selectArcVictims
##     tests a body DISC and not a bare point.
## The envelope is the honest bound on the art: paint inside it can never cover
## a body that walks away clean. `SprayPuffMinRadius` exists because near the
## nozzle the centerline wedge is ~4px wide while the envelope is ~20px, and it
## is bounded by this picture.
##
## Victim cogs are posed at point-blank / mid / max reach and their outline is
## keyed to the hp the REAL sim takes off (a separate probe fire, so the drawn
## burst is never perturbed): green = damaged, red = unhurt. A red disc under
## paint is the bug this probe exists to catch.
##
## Usage (from the repo root): nim c -d:release -r tools/spray_envelope_probe.nim [outDir]
import
  std/[os, strformat],
  pixie,
  ../src/ctf/[global, sim],
  toolutil

const
  ConeStroke = rgba(255, 214, 64, 255)      ## centerline cone: amber
  EnvelopeStroke = rgba(64, 232, 128, 255)  ## cone + body radius: green
  HurtStroke = rgba(96, 255, 128, 255)
  CleanStroke = rgba(255, 72, 72, 255)

proc ffaConfig(): GameConfig =
  result = defaultGameConfig()
  result.update(readFile("config.br.json"))

proc placeAtCenter(player: var Player, x, y: int) =
  player.x = x - CollisionW div 2
  player.y = y - CollisionH div 2

proc strokeCone(
  img: Image, ax, ay, reach, halfWidthAtReach, pad, scale: int, color: ColorRGBA
) =
  ## Strokes one east-aiming wedge, apex at (ax, ay), widened by `pad` on every
  ## side (pad = 0 draws the bare centerline cone).
  let
    slope = float(halfWidthAtReach) / float(reach)
    norm = sqrt(1.0 + slope * slope)
    off = float(pad)             ## selectArcVictims adds the body radius to the
                                 ## perpendicular COORDINATE, so the edge shifts
                                 ## by exactly `pad` there — not by pad * norm,
                                 ## which would draw the (wider) Minkowski sum.
    a = vec2(float32(ax * scale), float32(ay * scale))
    tipTop = vec2(
      float32((ax + reach + pad) * scale),
      float32((float(ay) - slope * float(reach) - off) * float(scale))
    )
    tipBottom = vec2(
      float32((ax + reach + pad) * scale),
      float32((float(ay) + slope * float(reach) + off) * float(scale))
    )
    apexTop = vec2(a.x, float32((float(ay) - off) * float(scale)))
    apexBottom = vec2(a.x, float32((float(ay) + off) * float(scale)))
  var path = newPath()
  path.moveTo(apexTop)
  path.lineTo(tipTop)
  path.moveTo(apexBottom)
  path.lineTo(tipBottom)
  path.moveTo(tipTop)
  path.lineTo(tipBottom)
  if pad > 0:
    path.moveTo(apexTop)
    path.lineTo(apexBottom)
  img.strokePath(path, color, strokeWidth = float32(scale))

proc strokeDisc(img: Image, cx, cy, r, scale: int, color: ColorRGBA) =
  var path = newPath()
  path.ellipse(
    vec2(float32(cx * scale), float32(cy * scale)),
    float32(r * scale), float32(r * scale)
  )
  img.strokePath(path, color, strokeWidth = float32(scale))

proc main() =
  let outDir = if paramCount() >= 1: paramStr(1) else: "/tmp"
  chdirGameDir()

  # Does the real sim take hp off a cog at this offset from the sprayer? Fired
  # in a throwaway sim so the pose the probe RENDERS stays untouched.
  proc damages(dx, dy: int): bool =
    var probe = initSimServer(ffaConfig())
    probe.gameEventLoggingEnabled = false
    discard probe.addPlayer("a")
    discard probe.addPlayer("b")
    probe.startGame()
    probe.players[0].placeAtCenter(400, 400)
    probe.players[0].aimBrads = 0
    probe.players[0].hasPlasmaArc = true
    probe.players[0].fireCooldown = 0
    probe.players[0].arcTicksLeft = 0
    probe.players[1].alive = true
    probe.players[1].respawnTimer = 0
    probe.players[1].hp = 99
    probe.players[1].placeAtCenter(400 + dx, 400 + dy)
    probe.tryFireArc(0)
    probe.players[1].hp < 99

  var sim = initSimServer(ffaConfig())
  sim.gameEventLoggingEnabled = false
  for i in 0 ..< 4:
    discard sim.addPlayer("p" & $i)
  sim.startGame()

  # Open floor with a clear ray east for the whole reach, swept rather than
  # guessed: a generated FFA board puts terrain wherever it likes.
  var sx, sy = -1
  block search:
    for y in countup(60, MapHeight - 60, 6):
      for x in countup(60, MapWidth - PlasmaArcReach - 80, 6):
        if not sim.canOccupy(x, y):
          continue
        if sim.lineOfSightClear(x, y, x + PlasmaArcReach + 40, y):
          sx = x
          sy = y
          break search
  doAssert sx >= 0, "no clear east-facing lane on this board"

  # Victims at the three distances the containment claim has to hold at: at the
  # nozzle (where the floor radius binds), mid reach, and the reach cap.
  const Ranges = [
    ("point-blank", 40, 0),
    ("mid", 100, 0),
    ("max", PlasmaArcReach + PlasmaArcBodyRadius - 4, 0)
  ]
  var victims: seq[tuple[name: string, dx, dy: int, hurt: bool]]
  for (name, dx, dy) in Ranges:
    victims.add((name, dx, dy, damages(dx, dy)))

  sim.players[0].placeAtCenter(sx, sy)
  sim.players[0].aimBrads = 0
  sim.players[0].hasPlasmaArc = true
  sim.players[0].fireCooldown = 0
  for i, v in victims:
    let p = i + 1
    if p >= sim.players.len:
      continue
    sim.players[p].alive = true
    sim.players[p].respawnTimer = 0
    sim.players[p].hp = 99
    sim.players[p].placeAtCenter(sx + v.dx, sy + v.dy)
  sim.tryFireArc(0)

  var
    state = initGlobalViewerState()
    next: GlobalViewerState
    world = initSpriteWorld()
  let scale = RenderScale

  proc renderOverlay(): Image =
    world.apply(sim.buildSpriteProtocolUpdates(state, next).parseSpritePacket())
    state = next
    result = world.renderBoard()
    result.strokeCone(
      sx, sy, PlasmaArcReach, PlasmaArcMaxWidth div 2, 0, scale, ConeStroke)
    result.strokeCone(
      sx, sy, PlasmaArcReach, PlasmaArcMaxWidth div 2, PlasmaArcBodyRadius,
      scale, EnvelopeStroke)
    for v in victims:
      result.strokeDisc(
        sx + v.dx, sy + v.dy, PlasmaArcBodyRadius, scale,
        if v.hurt: HurtStroke else: CleanStroke)

  proc crop(img: Image, cx, cy, w, h, zoom: int): Image =
    let
      x0 = clamp(cx * scale - w div 2, 0, MapWidth * scale - w)
      y0 = clamp(cy * scale - h div 2, 0, MapHeight * scale - h)
    img.subImage(x0, y0, w, h).resize(w * zoom, h * zoom)

  echo &"sprayer at ({sx}, {sy}) aiming east on the FFA board " &
    &"({MapWidth}x{MapHeight}), scale {scale}"
  echo &"SprayPuffMinRadius = {plasmaPulseDiameter(0, 0) div 2}px at the " &
    &"nozzle ({SprayHeldGripPx + SprayHeldLengthPx}px forward)"
  echo "puff containment (forward, radius, centerline half-width, envelope):"
  let
    slope = float(PlasmaArcMaxWidth) / (2.0 * float(PlasmaArcReach))
    norm = sqrt(1.0 + slope * slope)
  var worst = -1.0e9
  for stage in 0 ..< PlasmaArcFxStages:
    for pulse in 0 ..< PlasmaArcFxPulses:
      let
        f = plasmaPulseForward(pulse, stage)
        r = plasmaPulseDiameter(pulse, stage) div 2
        cone = slope * float(f) / norm
        # Perpendicular clearance from the axis to the sim's own boundary line
        # (perp = slope * forward + PlasmaArcBodyRadius), which is what a disc
        # centered on the axis has to fit inside.
        envelope = (slope * float(f) + float(PlasmaArcBodyRadius)) / norm
      worst = max(worst, float(r) - envelope)
      doAssert float(r) <= envelope, "puff leaves the envelope"
      doAssert r <= f, "puff reaches behind the apex"
      echo &"  stage {stage} pulse {pulse}: f={f:3} r={r:2} " &
        &"cone={cone:5.1f} envelope={envelope:5.1f} " &
        &"tip={f + r:3} (reach {PlasmaArcReach})"
  echo &"worst clearance to the envelope: {-worst:.1f}px to spare"
  for v in victims:
    echo &"  victim {v.name:12} at +{v.dx}px: " &
      (if v.hurt: "DAMAGED by the real sim" else: "unhurt")

  for f in 0 .. PlasmaArcFxTicks:
    let board = renderOverlay()
    if f == 1:
      # A young fan is bunched at the nozzle: this is where the floor radius
      # binds and where the centerline wedge is far thinner than the envelope.
      crop(board, sx + 30, sy, 130, 130, 4)
        .writeFile(outDir / "spray-envelope-point-blank.png")
      crop(board, sx + 100, sy, 170, 170, 3)
        .writeFile(outDir / "spray-envelope-mid.png")
    if f == PlasmaArcFxTicks:
      # The oldest snapshot has jetted to the full FX reach: the plume's TIP,
      # the widest puff, and the reach cap all land in this frame.
      crop(board, sx + PlasmaArcReach div 2, sy, 420, 200, 2)
        .writeFile(outDir / "spray-envelope-plume.png")
      crop(board, sx + PlasmaArcFxReach, sy, 200, 200, 3)
        .writeFile(outDir / "spray-envelope-max.png")
    crop(board, sx + PlasmaArcReach div 2, sy, 420, 200, 1)
      .writeFile(outDir / ("spray-envelope-t" & $f & ".png"))
    inc sim.tickCount
  echo "wrote overlays to ", outDir

main()
