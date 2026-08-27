## Reports the FFA LOOT ECONOMY over a pinned sample of ledgers: what a kill
## costs in shots and damage, what it returns in weapon tier, and the
## correlation between placement and killing that any anti-passivity change is
## judged on.
##
## The metric of record is the DE-CONFOUNDED correlation, `corr(placement,
## kills per 1k survival ticks)`. The raw `corr(placement, kills)` is emitted
## too, but never without the confounded label on the same line: placement is
## bought with clock today, so the raw number rises from time alive alone and
## can manufacture a win for a change that did nothing.
##
## Deliberately structural, not display choices:
##
## - Hit rate exists ONLY per `(tier, range bucket)` cell. `aimJitterSigma` is
##   calibrated against `config.gunRange` and is not per-tier, so a tier-only
##   rate reports range composition and invites "heavy shoots straighter".
##   There is no procedure here that returns hit rate by tier alone.
## - Every statistic has an n floor and prints its suppression instead of a
##   number below it. A single-episode smoke run must not be able to state a
##   rate.
## - Taint is filtered BEFORE any mean, and the excluded count and reasons are
##   printed above the statistics.
##
## Inputs per episode: the JSONL ledger from `tools/extract_events.nim --out`
## and the results payload from the same tool's `--results` (looked up as the
## ledger path with `.jsonl` replaced by `.results.json`). The results payload
## is where placement, kills and survival ticks live; the ledger's summary row
## does not carry them.
##
## Usage: nim r tools/loot_economy.nim <ledger.jsonl | dir> ...
##                                     [--window <ticks>] [--radius <px>]
##                                     [--label <text>]

import
  std/[algorithm, json, math, os, sets, strformat, strutils, tables],
  ledger

const
  MinSeatEpisodes* = 200  ## pooled correlations
  MinGroupSeats* = 20     ## a policy group enters the between-policy set
  MinCellShots* = 20      ## a (tier, bucket) cell prints a rate
  DefaultWindowTicks = 600
  DefaultRadiusPx = 96.0
  BucketEdges = [350.0, 700.0, 1050.0]
  TierNames = ["unarmed", "low", "mid", "heavy"]

type
  LootEconomyError = object of CatchableError

  Bucket* = range[0 .. 3]

  Cell* = object
    shots*, hits*, damage*, kills*: int

  SeatRow* = object
    ## One clean seat-episode: the unit every pooled statistic averages over.
    episode*: string
    seat*: int
    name*: string
    placement*: float     ## n - 1 - rank, so the winner scores n-1.
    kills*: float
    survival*: float
    killRate*: float      ## kills per 1000 survival ticks

  Access* = object
    firstArmTicks*: seq[float]  ## ticks from the playing phase to tier > 0
    neverArmed*: int
    dwell*: array[4, float]     ## seat-ticks spent at each tier

proc fail(message: string) =
  raise newException(LootEconomyError, message)

proc bucketOf*(distancePx: float): Bucket =
  ## Range bucket of one shot, from the distance its impact travelled.
  if distancePx < BucketEdges[0]: 0
  elif distancePx < BucketEdges[1]: 1
  elif distancePx < BucketEdges[2]: 2
  else: 3

proc bucketName(bucket: Bucket): string =
  case bucket
  of 0: "[0,350)"
  of 1: "[350,700)"
  of 2: "[700,1050)"
  else: "[1050,inf)"

# ---------------------------------------------------------------- statistics

proc mean(values: openArray[float]): float =
  if values.len == 0:
    return 0.0
  for value in values:
    result += value
  result /= float(values.len)

proc median(values: seq[float]): float =
  if values.len == 0:
    return 0.0
  var sorted = values
  sorted.sort(cmp)
  if sorted.len mod 2 == 1:
    sorted[sorted.len div 2]
  else:
    0.5 * (sorted[sorted.len div 2 - 1] + sorted[sorted.len div 2])

proc pearson*(xs, ys: openArray[float]): float =
  ## Pearson r, or NaN when either side has no variance (a constant column
  ## has no correlation to report, and 0.0 would read as "measured zero").
  let n = xs.len
  if n < 2 or ys.len != n:
    return NaN
  let
    mx = mean(xs)
    my = mean(ys)
  var sxx, syy, sxy: float
  for i in 0 ..< n:
    let
      dx = xs[i] - mx
      dy = ys[i] - my
    sxx += dx * dx
    syy += dy * dy
    sxy += dx * dy
  if sxx <= 0.0 or syy <= 0.0:
    return NaN
  sxy / sqrt(sxx * syy)

proc fisherBand*(r: float, n: int): (float, float) =
  ## 95% interval on r via the Fisher z transform. Needs n > 3 for a finite
  ## standard error, which is why the floors below never go under 5.
  if n <= 4 or r.isNaN or abs(r) >= 1.0:
    return (NaN, NaN)
  let
    z = arctanh(r)
    se = 1.0 / sqrt(float(n - 3))
  (tanh(z - 1.96 * se), tanh(z + 1.96 * se))

proc f3(value: float): string =
  if value.isNaN: "n/a" else: formatFloat(value, ffDecimal, 3)

proc correlationLine*(
    label: string, xs, ys: seq[float], floor: int, suffix = ""
): string =
  ## One correlation, or its suppression. The suffix rides on the SAME line as
  ## the number so a figure cannot be copied out of the report without the
  ## caveat that belongs to it.
  let n = xs.len
  if n < floor:
    return &"{label} = n={n} below floor {floor} — suppressed"
  let
    r = pearson(xs, ys)
    (lo, hi) = fisherBand(r, n)
  result = &"{label} = {f3(r)} [{f3(lo)}, {f3(hi)}] n={n}"
  if suffix.len > 0:
    result.add("  " & suffix)

# ------------------------------------------------------------------- reading

proc resultsPathFor(ledgerPath: string): string =
  if ledgerPath.endsWith(".jsonl"):
    ledgerPath[0 ..< ledgerPath.len - 6] & ".results.json"
  else:
    ledgerPath & ".results.json"

proc collectLedgers(paths: seq[string]): seq[string] =
  for path in paths:
    if dirExists(path):
      var found: seq[string]
      for kind, entry in walkDir(path):
        if kind == pcFile and entry.endsWith(".jsonl"):
          found.add(entry)
      found.sort(cmp)
      result.add(found)
    elif fileExists(path):
      result.add(path)
    else:
      fail("no such ledger or directory: " & path)

proc intsOf(node: JsonNode, key: string): seq[int] =
  if node.hasKey(key) and node[key].kind == JArray:
    for entry in node[key]:
      result.add(if entry.kind == JInt: entry.getInt else: -1)

proc seatRows*(
    episode: string, results: JsonNode, finished: bool, reason: var string
): seq[SeatRow] =
  ## The clean seat-episodes of one episode, or an empty seq with `reason` set.
  ## Taint is decided here, before any caller can average anything.
  reason = ""
  if not finished:
    reason = "notFinished"
    return
  if not results.hasKey("names") or results["names"].kind != JArray:
    reason = "noResults"
    return
  let
    names = results["names"]
    seats = names.len
    placement = intsOf(results, "placementSlots")
    kills = intsOf(results, "kills")
    survival = intsOf(results, "survivalTicks")
  if seats == 0 or kills.len < seats or survival.len < seats:
    reason = "noResults"
    return
  if placement.len != seats:
    reason = "badPlacement"
    return
  var seen = initHashSet[int]()
  for slot in placement:
    if slot < 0 or slot >= seats or slot in seen:
      reason = "badPlacement"
      return
    seen.incl(slot)
  for seat in 0 ..< seats:
    if survival[seat] <= 0:
      reason = "zeroSurvival"
      return
  var rank = newSeq[int](seats)
  for index, slot in placement:
    rank[slot] = index
  for seat in 0 ..< seats:
    let name = if names[seat].kind == JString: names[seat].getStr else: ""
    if name.len == 0:
      continue          # an unfilled seat is excluded, the episode is not
    result.add(SeatRow(
      episode: episode,
      seat: seat,
      name: name,
      placement: float(seats - 1 - rank[seat]),
      kills: float(kills[seat]),
      survival: float(survival[seat]),
      killRate: 1000.0 * float(kills[seat]) / float(max(1, survival[seat]))
    ))

# ------------------------------------------------------------- per-ledger work

proc addCells*(
    led: Ledger, cells: var Table[(int, Bucket), Cell],
    unbucketedKills, meleeKills: var int
) =
  ## Attributes shots, hits, damage and credited kills to (tier, bucket).
  ##
  ## A shot's range comes from its own `shot_impact` row (`distance` — the
  ## pixels the shot travelled), which exists for MISSES too; that is what
  ## makes a hit RATE per bucket possible at all. Hits, damage and kills carry
  ## no distance, so they are joined to the shots of the same
  ## (tick, source, weapon) and consumed in emission order. Two shots by one
  ## seat on one tick at different ranges is the ambiguous case; it is rare
  ## (per-weapon cooldowns) and the join is stated rather than hidden.
  ##
  ## `fist` is a TIER but not a gun: a punch emits no shot and has no range, so
  ## melee is counted separately instead of appearing as a gun kill nothing can
  ## place in a bucket.
  var
    shotBuckets = initTable[(int, int, string), seq[Bucket]]()
    hitCounts = initTable[(int, int, string), int]()
    damageAmounts = initTable[(int, int, string), int]()
    killCounts = initTable[(int, int, string), int]()
  for row in led.rows:
    if not TierByToken.hasKey(row.weapon) or TierByToken[row.weapon] == 0:
      continue            # CTF's flat "gun", the ring, a punch, or a non-weapon row
    let key = (row.tick, row.source, row.weapon)
    case row.kind
    of "shot_impact":
      shotBuckets.mgetOrPut(key, @[]).add(bucketOf(row.distance))
    of "hit":
      hitCounts[key] = hitCounts.getOrDefault(key) + 1
    of "damage":
      damageAmounts[key] = damageAmounts.getOrDefault(key) + row.amount
    else: discard
  for kill in led.matchedKills():
    if not TierByToken.hasKey(kill.weapon):
      continue
    if TierByToken[kill.weapon] == 0:
      inc meleeKills
      continue
    let key = (kill.tick, kill.source, kill.weapon)
    killCounts[key] = killCounts.getOrDefault(key) + 1
  for key, buckets in shotBuckets:
    let
      tier = TierByToken[key[2]]
      hits = hitCounts.getOrDefault(key)
      damage = damageAmounts.getOrDefault(key)
      kills = killCounts.getOrDefault(key)
    for index, bucket in buckets:
      var cell = cells.getOrDefault((tier, bucket))
      inc cell.shots
      if index < hits:
        inc cell.hits
      if index == 0:
        cell.damage += damage
        cell.kills += kills
      cells[(tier, bucket)] = cell
  for key, count in killCounts:
    if not shotBuckets.hasKey(key):
      unbucketedKills += count

proc addAccess*(led: Ledger, access: var Access, dwellSeats: var int) =
  ## Tier dwell and time-to-first-arm, measured from the PLAYING phase: every
  ## seat reads a default tier before the match starts, so counting from tick 0
  ## would credit warmup as time spent armed.
  let
    playing = max(0, led.phaseTick("playing"))
    last = led.lastTick()
    timeline = led.tierTimeline()
  for seat in 0 ..< led.seatCount():
    if led.seatName(seat) == "seat " & $seat:
      continue
    inc dwellSeats
    var
      armedAt = -1
      previousTick = playing
      previousTier = timeline.tierAt(seat, playing)
    for transition in timeline.getOrDefault(seat, @[]):
      if transition.tick <= playing:
        continue
      if transition.tick > last:
        break
      access.dwell[previousTier] += float(transition.tick - previousTick)
      if armedAt < 0 and transition.tier > 0:
        armedAt = transition.tick
      previousTick = transition.tick
      previousTier = transition.tier
    access.dwell[previousTier] += float(max(0, last - previousTick))
    if armedAt < 0:
      inc access.neverArmed
    else:
      access.firstArmTicks.add(float(armedAt - playing))

# -------------------------------------------------------------------- report

type
  Totals = object
    episodes, clean: int
    reasons: Table[string, int]
    rows: seq[SeatRow]
    cells: Table[(int, Bucket), Cell]
    unbucketedKills: int
    meleeKills: int
    access: Access
    dwellSeats: int
    kills, gains, gainsAtCorpse: int
    gainsByOrigin: Table[string, int]
    gainDistances: seq[float]
    tierStepsGained: int
    nonFfa: int

proc report(totals: Totals, windowTicks: int, radiusPx: float, label: string) =
  if label.len > 0:
    echo "sample: ", label
  var excluded: seq[string]
  for reason, count in totals.reasons:
    excluded.add(&"{reason} {count}")
  excluded.sort(cmp)
  let reasonText = if excluded.len == 0: "none" else: excluded.join(", ")
  echo &"episodes: clean {totals.clean} / total {totals.episodes} " &
    &"(excluded {totals.episodes - totals.clean}: {reasonText})"
  echo &"seat-episodes: {totals.rows.len}   " &
    &"non-FFA ledgers skipped for tier reads: {totals.nonFfa}"
  echo ""

  var placement, kills, killRate, survival: seq[float]
  for row in totals.rows:
    placement.add(row.placement)
    kills.add(row.kills)
    killRate.add(row.killRate)
    survival.add(row.survival)

  echo "CORRELATIONS"
  echo "  metric of record (de-confounded): ",
    correlationLine(
      "corr(placement, kills per 1k ticks)", placement, killRate,
      MinSeatEpisodes)
  echo "  raw within-episode: ",
    correlationLine(
      "corr(placement, kills)", placement, kills, MinSeatEpisodes,
      "CONFOUNDED by time alive — not the metric of record")
  echo "  context: ",
    correlationLine(
      "corr(placement, survivalTicks)", placement, survival, MinSeatEpisodes)

  var groups = initTable[string, seq[SeatRow]]()
  for row in totals.rows:
    groups.mgetOrPut(row.name, @[]).add(row)
  var
    groupPlacement, groupKills, groupSurvival: seq[float]
    groupsUnderFloor = 0
  for name, rows in groups:
    if rows.len < MinGroupSeats:
      inc groupsUnderFloor
      continue
    var p, k, s: seq[float]
    for row in rows:
      p.add(row.placement)
      k.add(row.kills)
      s.add(row.survival)
    groupPlacement.add(mean(p))
    groupKills.add(mean(k))
    groupSurvival.add(mean(s))
  echo &"  between-policy (groups with >= {MinGroupSeats} seat-episodes; " &
    &"{groupsUnderFloor} groups below floor):"
  echo "    ",
    correlationLine(
      "corr(mean placement, mean kills)", groupPlacement, groupKills, 5)
  echo "    ",
    correlationLine(
      "corr(mean placement, mean survival)", groupPlacement, groupSurvival, 5)
  echo ""

  echo &"COST — per (tier, range bucket); a cell needs {MinCellShots} shots"
  echo "  tier    bucket        shots  hits  hitRate  damage  kills  " &
    "shots/kill  damage/kill"
  for tier in 1 .. 3:
    for bucket in Bucket.low .. Bucket.high:
      let cell = totals.cells.getOrDefault((tier, bucket))
      if cell.shots == 0:
        continue
      var
        rate = "suppressed"
        perKill = "suppressed"
        damagePerKill = "suppressed"
      if cell.shots >= MinCellShots:
        rate = f3(float(cell.hits) / float(cell.shots))
        if cell.kills > 0:
          perKill = f3(float(cell.shots) / float(cell.kills))
          damagePerKill = f3(float(cell.damage) / float(cell.kills))
        else:
          perKill = "no kills"
          damagePerKill = "no kills"
      echo &"  {TierNames[tier]:<7} {bucketName(bucket):<12} " &
        &"{cell.shots:>6} {cell.hits:>5} {rate:>8} {cell.damage:>7} " &
        &"{cell.kills:>6} {perKill:>11} {damagePerKill:>12}"
  echo "  no tier-only hit rate is computed or printed: aim jitter is keyed " &
    "to gun range,"
  echo "  not to tier, so a tier row would report range composition."
  echo &"  melee (fist) credited kills, excluded from the gun cells above: " &
    &"{totals.meleeKills}"
  if totals.unbucketedKills > 0:
    echo &"  GUN kills with no same-tick shot_impact to place them: " &
      &"{totals.unbucketedKills}"
  echo ""

  echo &"RETURN — tier gains on credited kills (window {windowTicks} ticks, " &
    &"corpse radius {f3(radiusPx)} px)"
  if totals.kills < MinCellShots:
    echo &"  credited kills n={totals.kills} below floor {MinCellShots} — " &
      "suppressed"
  else:
    echo &"  credited kills {totals.kills}   with a tier gain in window " &
      &"{totals.gains} ({f3(float(totals.gains) / float(totals.kills))} " &
      "per kill)"
    var origins: seq[string]
    for origin, count in totals.gainsByOrigin:
      origins.add(&"{origin} {count}")
    origins.sort(cmp)
    echo "  gains by origin: ", (if origins.len == 0: "none" else: origins.join(", "))
    echo &"  gains within the corpse radius: {totals.gainsAtCorpse}   " &
      &"median gain distance {f3(median(totals.gainDistances))} px"
    echo "  radius is PROXIMITY, origin is PROVENANCE — a spawn gain near a " &
      "corpse is still a spawn gain."
    if totals.gainsByOrigin.getOrDefault("corpse") == 0:
      echo "  no corpse-origin gains in this arm: dropWeaponOnDeath was off, " &
        "so every gain"
      echo "  above is a map spawn and the return side is zero by construction."
  echo ""

  echo "NET — return minus cost, per kill"
  if totals.kills < MinCellShots:
    echo &"  n={totals.kills} below floor {MinCellShots} — suppressed"
  else:
    echo &"  tier steps gained per credited kill: " &
      &"{f3(float(totals.tierStepsGained) / float(totals.kills))}"
    echo "  tier steps SPENT per kill: 0 — nothing consumes a tier at GV45, " &
      "so the cost side"
    echo "  is measured in shots above. This is the number the drop arm moves."
  echo ""

  echo "ACCESS — measured from the playing phase, not tick 0"
  if totals.dwellSeats < MinGroupSeats:
    echo &"  seats n={totals.dwellSeats} below floor {MinGroupSeats} — " &
      "suppressed"
  else:
    var total = 0.0
    for tier in 0 .. 3:
      total += totals.access.dwell[tier]
    for tier in 0 .. 3:
      let share =
        if total > 0.0: f3(totals.access.dwell[tier] / total) else: "n/a"
      echo &"  dwell {TierNames[tier]:<8} {totals.access.dwell[tier]:>12.0f} " &
        &"seat-ticks  share {share}"
    if totals.access.firstArmTicks.len < MinGroupSeats:
      echo &"  time-to-first-arm: n={totals.access.firstArmTicks.len} " &
        &"below floor {MinGroupSeats} — suppressed"
    else:
      echo &"  time-to-first-arm: mean " &
        &"{f3(mean(totals.access.firstArmTicks))} ticks, median " &
        &"{f3(median(totals.access.firstArmTicks))} ticks " &
        &"(n={totals.access.firstArmTicks.len})"
    echo &"  seats that never armed: {totals.access.neverArmed} of " &
      &"{totals.dwellSeats}"
  echo ""

  echo "PER-SEAT SPLIT — seat is the known confound, so it is never pooled away"
  echo "  seat  episodes  meanPlacement  meanKills  meanKillRate  meanSurvival"
  var bySeat = initTable[int, seq[SeatRow]]()
  for row in totals.rows:
    bySeat.mgetOrPut(row.seat, @[]).add(row)
  var seats: seq[int]
  for seat in bySeat.keys:
    seats.add(seat)
  seats.sort(cmp)
  for seat in seats:
    let rows = bySeat[seat]
    var p, k, kr, s: seq[float]
    for row in rows:
      p.add(row.placement)
      k.add(row.kills)
      kr.add(row.killRate)
      s.add(row.survival)
    if rows.len < MinGroupSeats:
      echo &"  {seat:>4} {rows.len:>9}  n below floor {MinGroupSeats} — " &
        "suppressed"
      continue
    echo &"  {seat:>4} {rows.len:>9} {mean(p):>14.3f} {mean(k):>10.3f} " &
      &"{mean(kr):>13.3f} {mean(s):>13.1f}"

# ---------------------------------------------------------------------- main

proc run(paths: seq[string], windowTicks: int, radiusPx: float, label: string) =
  var totals = Totals(reasons: initTable[string, int]())
  for ledgerPath in collectLedgers(paths):
    inc totals.episodes
    let led = loadLedger(ledgerPath)
    if not led.summary.present:
      totals.reasons["truncated"] = totals.reasons.getOrDefault("truncated") + 1
      continue
    let resultsPath = resultsPathFor(ledgerPath)
    if not fileExists(resultsPath):
      totals.reasons["noResults"] = totals.reasons.getOrDefault("noResults") + 1
      continue
    var reason: string
    let rows = seatRows(
      ledgerPath.extractFilename, parseJson(readFile(resultsPath)),
      led.summary.finished, reason)
    if reason.len > 0:
      totals.reasons[reason] = totals.reasons.getOrDefault(reason) + 1
      continue
    inc totals.clean
    totals.rows.add(rows)
    if not led.isFfaLedger():
      inc totals.nonFfa
      continue
    addCells(led, totals.cells, totals.unbucketedKills, totals.meleeKills)
    addAccess(led, totals.access, totals.dwellSeats)
    for outcome in led.lootOutcomes(windowTicks, radiusPx):
      inc totals.kills
      if not outcome.tierGain:
        continue
      inc totals.gains
      totals.tierStepsGained += outcome.killerTierAfter - outcome.killerTierBefore
      let origin = if outcome.gainOrigin.len > 0: outcome.gainOrigin else: "unknown"
      totals.gainsByOrigin[origin] = totals.gainsByOrigin.getOrDefault(origin) + 1
      if outcome.gainAtCorpse:
        inc totals.gainsAtCorpse
      if outcome.gainDistPx >= 0.0:
        totals.gainDistances.add(outcome.gainDistPx)
  if totals.episodes == 0:
    fail("no ledgers to read")
  report(totals, windowTicks, radiusPx, label)

when isMainModule:
  const UsageText =
    "Usage: nim r tools/loot_economy.nim <ledger.jsonl | dir> ... " &
      "[--window <ticks>] [--radius <px>] [--label <text>]"
  try:
    var
      paths: seq[string]
      windowTicks = DefaultWindowTicks
      radiusPx = DefaultRadiusPx
      label = ""
      params = commandLineParams()
      i = 0
    while i < params.len:
      let arg = params[i]
      if arg in ["--help", "-h"]:
        echo UsageText
        quit(0)
      elif arg in ["--window", "--radius", "--label"]:
        if i + 1 >= params.len:
          fail(arg & " requires a value.\n" & UsageText)
        inc i
        case arg
        of "--window": windowTicks = parseInt(params[i])
        of "--radius": radiusPx = parseFloat(params[i])
        else: label = params[i]
      elif arg.startsWith("--"):
        fail("Unknown option: " & arg & "\n" & UsageText)
      else:
        paths.add(arg)
      inc i
    if paths.len == 0:
      fail("Expected at least one ledger or directory.\n" & UsageText)
    run(paths, windowTicks, radiusPx, label)
  except LootEconomyError as e:
    stderr.writeLine("loot_economy failed: " & e.msg)
    quit(1)
  except LedgerError as e:
    stderr.writeLine("loot_economy ledger error: " & e.msg)
    quit(1)
