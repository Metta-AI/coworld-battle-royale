## ⭐⭐⭐ RAID-FRAME PROBE — the three claims the lever rests on, asserted against
## the REAL procs in players/baseline/baseline.nim, on REAL generated boards.
##
## This is a gate, not a report: every block prints PASS/FAIL and the binary
## exits non-zero on any failure, so "the reduction holds" is a thing that was
## run rather than a thing that was argued. It sits beside grabprobe (same
## eval/config.nims, same `include "../baseline.nim"`) so it links the SHIPPED
## `raidStagePoint` / `raidFwd` / `homeSign` — not a re-derivation of them.
##
##   1. REDUCTION — on a 2-team board the raid frame IS the shipped expression.
##      Checked to the last float bit against every mirrored geometry the
##      generator draws, plus the stock arena, over both lanes and a depth sweep.
##      ⚠️ It also reports the ONE case where the equality is not bit-exact and
##      why, instead of hiding it: an ODD map width makes CenterX = W div 2 floor
##      by 0.5px while the true base midpoint does not, so a board whose bases
##      are symmetric about the true centre is 0.5px off the floored one. That is
##      exactly why BOTH call sites are ALSO gated on GameTeams > 2.
##   2. CELLS — the primary instrument, in closed form. Whose Voronoi cell does
##      the flank staging point land in, before vs after, on real 4-team corners
##      boards. Legacy is expected in a THIRD PARTY's cell; the raid frame is
##      expected in ours or the raid target's.
##   3. PARK — the coupling. A flanker walking to the staging point must have its
##      `behindLines` release fire. Wired legacy/legacy or frame/frame it fires;
##      wired frame-staging + legacy-release (the failure mode this lever is one
##      edit away from) it NEVER fires and the seat parks for the whole round.

import std/strformat
from ctf/sim import nil

include "../baseline.nim"

var failures = 0

proc gate(name: string, ok: bool, detail = "") =
  if ok:
    echo &"PASS  {name}  {detail}"
  else:
    inc failures
    echo &"FAIL  {name}  {detail}"

proc legacyStage(team: Team, depth, laneY: float): Vec =
  ## The SHIPPED expression, verbatim from the call site this lever replaces.
  vec(float(CenterX) - homeSign(team) * depth, laneY)

proc legacyFwd(team: Team, me: Vec): float =
  ## The SHIPPED behindLines quantity, verbatim from its call site.
  -homeSign(team) * (me.x - float(CenterX))

proc setBoard(w, h: int) =
  MapW = w
  MapH = h
  CenterX = MapW div 2
  CenterY = MapH div 2
  LaneMid = float(CenterY)
  LaneBottom = float(MapH) - LaneTop

proc anchorsOf(gm: sim.CtfMap, teams: int): seq[Vec] =
  for i in 0 ..< teams:
    let a = sim.teamAnchor(gm, sim.Team(i))
    result.add vec(float(a.x), float(a.y))

proc nearestOther(pts: seq[Vec], i: int): int =
  var best = -1
  var bestD = 1e18
  for j in 0 ..< pts.len:
    if j == i: continue
    let d = dist(pts[i], pts[j])
    if d < bestD:
      bestD = d
      best = j
  best

proc cellOf(pts: seq[Vec], p: Vec): int =
  ## Voronoi cell by nearest base — the same rule hsClassifyCell uses on the
  ## engine-stated endzone centres.
  var best = -1
  var bestD = 1e18
  for j in 0 ..< pts.len:
    let d = dist(p, pts[j])
    if d < bestD:
      bestD = d
      best = j
  best

# ── 1. REDUCTION ─────────────────────────────────────────────────────────────
block reduction:
  var
    n, exact, sym, symExact = 0
    maxDev = 0.0
    maxDevSym = 0.0
    fwdN, fwdExact = 0
    maxFwdDev = 0.0
  for seed in 1 .. 60:
    let gm = sim.generateCtfMap(seed, sim.MapGenOverrides(windows: -1), teams = 2)
    setBoard(gm.width, gm.height)
    let a = anchorsOf(gm, 2)
    for ti in 0 .. 1:
      let
        team = (if ti == 0: Red else: Blue)
        ownHome = a[ti]
        steal = a[1 - ti]
        # A board is MIRROR-SYMMETRIC for this purpose when the two bases'
        # midpoint is the board centre. That is the precondition of the
        # algebra, so it is measured rather than assumed.
        mid = (ownHome + steal) * 0.5
        isSym = abs(mid.x - float(CenterX)) < 1e-9 and
                abs(mid.y - float(CenterY)) < 1e-9
      for laneY in [LaneTop, LaneBottom, LaneMid]:
        for depth in [FlankDepth, FlankDepth * 0.5, 120.0, 200.0]:
          let
            oldP = legacyStage(team, depth, laneY)
            newP = raidStagePoint(ownHome, steal, depth, laneY)
            dev = dist(oldP, newP)
          inc n
          if oldP.x == newP.x and oldP.y == newP.y: inc exact
          maxDev = max(maxDev, dev)
          if isSym:
            inc sym
            if oldP.x == newP.x and oldP.y == newP.y: inc symExact
            maxDevSym = max(maxDevSym, dev)
      for mx in [40.0, 200.0, float(CenterX), float(CenterX) + 100.0,
                 float(MapW) - 40.0]:
        for my in [40.0, float(CenterY), float(MapH) - 40.0]:
          let me = vec(mx, my)
          inc fwdN
          if legacyFwd(team, me) == raidFwd(me, ownHome, steal): inc fwdExact
          maxFwdDev = max(maxFwdDev, abs(legacyFwd(team, me) - raidFwd(me, ownHome, steal)))
  gate("REDUCTION.stage.symmetric", sym > 0 and symExact == sym,
    &"{symExact}/{sym} bit-exact, maxDev {maxDevSym:.9f}px")
  # ⭐ THE HONEST FORM OF THE SECOND HALF. Bit-exactness is only CLAIMABLE where
  # the algebra's precondition holds (bases mirrored about the board centre),
  # and it is asserted there above. Everywhere else the ONLY thing that may
  # differ is the half-pixel `CenterX = MapW div 2` floors off an odd width — so
  # the gate is that the deviation NEVER EXCEEDS THAT HALF PIXEL on any 2-team
  # board, i.e. there is no axis error hiding among the rounding. (Before the
  # perp canonicalisation this same gate read maxDev 1633px: a mirrored lane, not
  # a rounding story. It is the reason that bug was caught at all.)
  gate("REDUCTION.stage.all2team", maxDev <= 0.5,
    &"{exact}/{n} bit-exact; maxDev over ALL generated 2-team boards {maxDev:.3f}px " &
    "(<=0.5px == the odd-width floor and nothing else)")
  gate("REDUCTION.fwd", maxFwdDev <= 0.5,
    &"{fwdExact}/{fwdN} bit-exact; maxDev {maxFwdDev:.3f}px")

  # The stock 1235x659 arena with the CLASSIC pedestals, called out on its own
  # because it is the board every 2-team league episode is played on.
  setBoard(1235, 659)
  let
    ownHome = vec(186, 329)
    steal = vec(1049, 329)
    mid = (ownHome + steal) * 0.5
  var stockExact, stockN = 0
  var stockDev = 0.0
  for laneY in [LaneTop, LaneBottom]:
    let
      oldP = legacyStage(Red, FlankDepth, laneY)
      newP = raidStagePoint(ownHome, steal, FlankDepth, laneY)
    inc stockN
    if oldP.x == newP.x and oldP.y == newP.y: inc stockExact
    stockDev = max(stockDev, dist(oldP, newP))
  echo &"NOTE  stock arena 1235x659: base midpoint x={mid.x} vs CenterX={CenterX} " &
    &"(W div 2 floors an ODD width) -> {stockExact}/{stockN} bit-exact, dev {stockDev:.3f}px. " &
    "This is the 0.5px floor, not an axis error, and the GameTeams>2 gate means it never runs."

# ── 2. CELLS (the primary instrument, closed form) ────────────────────────────
proc cellSweep(name: string, boards: seq[tuple[w, h: int, a: seq[Vec]]]):
    tuple[n, oldThird, newThird, oldOff, newOff: int] =
  ## Legacy vs raid frame, scored the way the hosted census scores it: whose
  ## Voronoi cell does the emitted staging point fall in. Both flank lanes, all
  ## four colours.
  var n, oldOwn, oldRaid, oldThird, newOwn, newRaid, newThird, oldOff, newOff = 0
  for b in boards:
    setBoard(b.w, b.h)
    let a = b.a
    for ci in 0 .. 3:
      let
        team = (if ci mod 2 == 0: Red else: Blue)   # runBot's slot-parity seed
        ownHome = a[ci]
        ri = nearestOther(a, ci)                    # enemyColorFor: NEAREST rival
        steal = a[ri]
      for laneY in [LaneTop, LaneBottom]:
        let
          oldP = legacyStage(team, FlankDepth, laneY)
          newP = raidStagePoint(ownHome, steal, FlankDepth, laneY)
        inc n
        if oldP.x < 0 or oldP.x > float(MapW) or oldP.y < 0 or oldP.y > float(MapH):
          inc oldOff
        if newP.x < 0 or newP.x > float(MapW) or newP.y < 0 or newP.y > float(MapH):
          inc newOff
        let oc = cellOf(a, oldP)
        if oc == ci: inc oldOwn elif oc == ri: inc oldRaid else: inc oldThird
        let nc = cellOf(a, newP)
        if nc == ci: inc newOwn elif nc == ri: inc newRaid else: inc newThird
  echo &"CELLS[{name}] n={n} over {boards.len} boards"
  echo &"  legacy  own={oldOwn} raid={oldRaid} THIRD={oldThird} " &
    &"({100.0*float(oldThird)/float(n):.1f}%)  offboard={oldOff}"
  echo &"  raidfrm own={newOwn} raid={newRaid} THIRD={newThird} " &
    &"({100.0*float(newThird)/float(n):.1f}%)  offboard={newOff}"
  (n, oldThird, newThird, oldOff, newOff)

block cells:
  ## ⭐ THE HOSTED BOARD IS THE ONE THAT COUNTS. The local generator's 4-team
  ## draw is a 1728 SQUARE with four EQUIDISTANT bases; the hosted ffa4 board has
  ## been a 1235x659 RECTANGLE, layout pinned to `corners`, on 2352 of 2352
  ## episodes since coworld 0.7.202 — and on the rectangle the nearest rival is
  ## always the VERTICAL neighbour (460px vs 862px), which is the entire defect.
  ## Scoring the fix on a square board is the "mirror rig lacks the disease"
  ## trap in its exact shape, so the square is reported as a CONTROL, never as
  ## the verdict.
  let hosted = @[
    (w: 1235, h: 659, a: @[vec(186, 99), vec(1048, 99), vec(186, 559), vec(1048, 559)])
  ]
  let r = cellSweep("hosted corners 1235x659", hosted)
  gate("CELLS.legacy_is_broken", 100.0 * float(r.oldThird) / float(r.n) > 50.0,
    &"legacy lands in a THIRD party's cell {100.0*float(r.oldThird)/float(r.n):.1f}% of the time")
  gate("CELLS.raidframe_fixes_it", 100.0 * float(r.newThird) / float(r.n) < 15.0,
    &"raid frame: {100.0*float(r.newThird)/float(r.n):.1f}% (baseline for a BODY position is 6.8-10.1%)")
  gate("CELLS.onboard", r.newOff == 0,
    &"raid-frame staging points off the board: {r.newOff} (the perp clamp)")

  # CONTROL, reported and NOT gated: the generated square, a different map family.
  var gen: seq[tuple[w, h: int, a: seq[Vec]]]
  for seed in 1 .. 40:
    let gm = sim.generateCtfMap(seed, sim.MapGenOverrides(windows: -1, layout: "corners"),
                                teams = 4)
    if gm.layout != sim.layoutCorners: continue
    gen.add (w: gm.width, h: gm.height, a: anchorsOf(gm, 4))
  discard cellSweep("generated corners (CONTROL - equidistant square, NOT the hosted family)", gen)

# ── 3. PARK (the coupling) ───────────────────────────────────────────────────
block park:
  ## The flanker walks straight at whatever staging point its wiring produces,
  ## one step per tick, and we ask the ONE question the release gate asks:
  ## does `fwd` ever reach FlankDepth - 50? Three wirings, on the byte-exact
  ## hosted corners board (Red 186,99 / Blue 1048,99 / Green 186,559 /
  ## Yellow 1048,559), for every colour and both flank lanes.
  setBoard(1235, 659)
  let a = @[vec(186, 99), vec(1048, 99), vec(186, 559), vec(1048, 559)]
  const Step = 4.0
  const MaxTicks = 4000
  proc walk(start, dest: Vec, fwdFn: proc(p: Vec): float): bool =
    ## true = the release fired before the clock ran out.
    var p = start
    for t in 0 ..< MaxTicks:
      if fwdFn(p) >= FlankDepth - 50.0: return true
      let d = dest - p
      if d.len() <= Step: p = dest
      else: p = p + norm(d) * Step
    fwdFn(p) >= FlankDepth - 50.0
  var legacyReleased, frameReleased, mixedReleased, cases = 0
  for ci in 0 .. 3:
    let
      team = (if ci mod 2 == 0: Red else: Blue)
      ownHome = a[ci]
      ri = nearestOther(a, ci)
      steal = a[ri]
    for laneY in [LaneTop, LaneBottom]:
      inc cases
      let
        oldP = legacyStage(team, FlankDepth, laneY)
        newP = raidStagePoint(ownHome, steal, FlankDepth, laneY)
      # (a) shipped today: legacy anchor + legacy release.
      if walk(ownHome, oldP, proc(p: Vec): float = legacyFwd(team, p)):
        inc legacyReleased
      # (b) the lever, wired as ONE UNIT: frame anchor + frame release.
      if walk(ownHome, newP, proc(p: Vec): float = raidFwd(p, ownHome, steal)):
        inc frameReleased
      # (c) THE FAILURE MODE: frame anchor, release left on the x axis.
      if walk(ownHome, newP, proc(p: Vec): float = legacyFwd(team, p)):
        inc mixedReleased
  gate("PARK.coupled_releases", frameReleased == cases,
    &"{frameReleased}/{cases} flank seats reach the behindLines release")
  gate("PARK.mixed_wiring_PARKS", mixedReleased == 0,
    &"{mixedReleased}/{cases} released with a frame anchor + an x-axis gate " &
    "(0 is the point: this is the failure mode, and it is why the two sites move together)")
  echo &"NOTE  legacy anchor + legacy gate released {legacyReleased}/{cases} " &
    "(the shipped baseline does release — it just releases toward the wrong place)"

echo ""
if failures == 0:
  echo "RAIDPROBE: ALL GATES PASS"
else:
  echo &"RAIDPROBE: {failures} GATE(S) FAILED"
  quit(1)
