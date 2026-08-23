## Renders one MARKDOWN REPORT CARD per agent per episode from an episode's
## ledger (`tools/extract_events.nim` JSON lines).
##
## A report card answers, for one seat, the four questions a ledger can settle
## first-hand:
##
##   damage timeline   every hit dealt and taken, in tick order, with the
##                     post-hit hp so a trade reads as a trade
##   kills in context  who, when, with what, at what range and hp
##   death cause       what ended each life, and which one was terminal
##   tier ticks        when the seat climbed the FFA gun ladder
##
## The timeline is deliberately kept in TICK ORDER rather than aggregated:
## totals say a seat took 300 damage, an ordered timeline says it took 300
## damage from three seats in four seconds while holding a low gun, and only
## the second explains the episode. Aggregates are printed too, at the top,
## because "did this seat ever hit anything" should not require reading 90
## rows.
##
## Usage:
##   nim r tools/report_card.nim <ledger.jsonl> --out <dir>
##                               [--seat <n>] [--episode <name>] [--index]
##
## Writes `<dir>/<episode>/seat-NN-<name>.md`, one file per seat (or just
## `--seat`), plus `<dir>/<episode>/README.md` as an episode index with
## `--index`.

import std/[algorithm, math, os, strformat, strutils, tables]

import ledger

const
  UsageText = """
Usage: nim r tools/report_card.nim <ledger.jsonl> --out <dir>
                                   [--seat <n>] [--episode <name>] [--index]"""
  TicksPerSecond = 24

type
  Options = object
    ledgerPath: string
    outDir: string
    episode: string
    seat: int             ## -1 = every seat in the episode.
    writeIndex: bool

  SeatStats = object
    damageDealt, damageTaken, blockedDealt, blockedTaken: int
    hitsDealt, hitsTaken: int
    kills, unmatchedKillRows, deaths: int
    heals, healed: int
    shotsFired, shotsHit: int

proc parseOptions(): Options =
  result.seat = -1
  var
    params = commandLineParams()
    positional: seq[string]
    i = 0
  while i < params.len:
    let arg = params[i]
    if arg in ["-h", "--help"]:
      echo UsageText
      quit(0)
    elif arg == "--index":
      result.writeIndex = true
    elif arg.startsWith("--"):
      if i + 1 >= params.len:
        fail(arg & " requires a value.\n" & UsageText)
      inc i
      let value = params[i]
      case arg
      of "--out": result.outDir = value
      of "--episode": result.episode = value
      of "--seat":
        result.seat = parseInt(value)
        if result.seat < 0:
          fail("--seat must not be negative; omit it for every seat.")
      else: fail("Unknown option: " & arg & "\n" & UsageText)
    else:
      positional.add(arg)
    inc i
  if positional.len != 1:
    fail("Expected exactly one ledger path.\n" & UsageText)
  result.ledgerPath = positional[0]
  if result.outDir.len == 0:
    fail("--out <dir> is required.\n" & UsageText)
  if result.episode.len == 0:
    result.episode = result.ledgerPath.extractFilename.changeFileExt("")

proc clock(tick: int): string =
  ## `t641 (0:26.7)` — the tick is what the tooling needs, the clock is what a
  ## reviewer watching the replay needs.
  ## Both fields come off ONE rounded quantity: rounding the seconds
  ## independently prints `0:60.0` on the last tick of a minute.
  let tenths = (tick * 10 + TicksPerSecond div 2) div TicksPerSecond
  &"t{tick} ({tenths div 600}:" &
    &"{(tenths mod 600) div 10:02}.{tenths mod 10})"

proc at(x, y: float): string =
  ## Board coordinates are whole pixels in practice; print them that way.
  "(" & $int(x.round) & ", " & $int(y.round) & ")"

proc fileSafe(name: string): string =
  for c in name:
    result.add(if c.isAlphaNumeric or c in {'-', '_', '.'}: c else: '-')

proc statsFor(log: Ledger, seat: int): SeatStats =
  for row in log.rows:
    case row.kind
    of "damage":
      if row.source == seat:
        result.damageDealt += row.amount
        result.blockedDealt += row.blocked
        inc result.hitsDealt
      if row.target == seat:
        result.damageTaken += row.amount
        result.blockedTaken += row.blocked
        inc result.hitsTaken
    of "death":
      if row.source == seat: inc result.deaths
    of "heal":
      if row.source == seat: inc result.heals
      if row.target == seat: inc result.healed
    else: discard
  for entry in log.killRows():
    if entry.row.source != seat:
      continue
    if entry.matched: inc result.kills
    else: inc result.unmatchedKillRows
  if seat < log.summary.slotShotsFired.len:
    result.shotsFired = log.summary.slotShotsFired[seat]
  if seat < log.summary.slotShotsHit.len:
    result.shotsHit = log.summary.slotShotsHit[seat]

proc accuracy(stats: SeatStats): string =
  if stats.shotsFired <= 0:
    return "n/a (no shots)"
  &"{100.0 * stats.shotsHit.float / stats.shotsFired.float:.0f}% " &
    &"({stats.shotsHit}/{stats.shotsFired})"

proc weaponAt(log: Ledger, seat, tick: int): string =
  ## The last gun tier the seat picked up at or before `tick` — the context a
  ## damage row lacks, and usually the reason a trade went the way it did.
  result = "fists"
  for pickup in log.tierPickups(seat):
    if pickup.tick <= tick:
      result = pickup.item
    else:
      break

proc deathSection(log: Ledger, seat: int): string =
  let
    deaths = log.rowsOf("death")
    eliminations = log.eliminations()
  var terminal = -1
  for elimination in eliminations:
    if elimination.seat == seat:
      terminal = elimination.tick
  result = "## Death cause\n\n"
  var any = false
  for row in deaths:
    if row.source != seat:
      continue
    any = true
    var weapon = row.weapon
    if weapon.len == 0:
      for kill in log.matchedKills():
        if kill.tick == row.tick and kill.target == seat:
          weapon = kill.weapon
          break
    let
      cause =
        if row.target >= 0: &"killed by {log.seatLabel(row.target)}"
        else: "killed by the environment (ring / out of bounds)"
      withWeapon = if weapon.len > 0: &" with **{weapon}**" else: ""
      holding = log.weaponAt(seat, row.tick)
      note =
        if row.tick == terminal: " — **terminal**, no respawn followed"
        else: " (respawned afterwards)"
    result.add(&"- {clock(row.tick)}: {cause}{withWeapon} at " &
      &"{at(row.x, row.y)}, holding {holding}{note}\n")
  if not any:
    result.add("- never died: this seat was still standing when the recording " &
      "ended.\n")
  result.add("\n")

proc tierSection(log: Ledger, seat: int): string =
  result = "## Tier acquisition\n\n"
  let pickups = log.tierPickups(seat)
  if pickups.len == 0:
    result.add("- no gun tier ever picked up: this seat fought the whole " &
      "episode with fists.\n\n")
    return
  for pickup in pickups:
    result.add(&"- {clock(pickup.tick)}: **{pickup.item}** at " &
      &"{at(pickup.x, pickup.y)}\n")
  result.add("\n")

proc killSection(log: Ledger, seat: int): string =
  result = "## Kills, with context\n\n"
  var any = false
  for entry in log.killRows():
    if entry.row.source != seat:
      continue
    any = true
    let
      row = entry.row
      # An unmatched kill row is a sim-side artefact, not a kill: `recordKill`
      # sits outside `killPlayer`'s alive guard, so hitting a corpse credits
      # another kill row with no second death row behind it. Shown, flagged,
      # and excluded from the count.
      flag =
        if entry.matched: ""
        else: " — **UNMATCHED**: no `death` row for this victim on this tick, " &
          "so this is a duplicate credit, not a kill"
    result.add(&"- {clock(row.tick)}: killed {log.seatLabel(row.target)} " &
      &"with **{row.weapon}** at {at(row.x, row.y)}{flag}\n")
  if not any:
    result.add("- no kills.\n")
  result.add("\n")

proc damageSection(log: Ledger, seat: int): string =
  ## Ordered, both directions, with the seat's own hp after each row it was on
  ## the receiving end of — the sequence-preserving view. A per-seat total
  ## cannot show a seat losing a 1v1 it started ahead in; this can.
  result = "## Damage timeline\n\n" &
    "`>` dealt by this seat, `<` taken. `hp` is the victim's hp after the " &
    "hit; `blocked` is damage a shield or barrier ate.\n\n" &
    "| tick | dir | other seat | weapon | dmg | blocked | victim hp | holding |\n" &
    "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
  var rows = 0
  for row in log.rows:
    if row.kind != "damage":
      continue
    let dealt = row.source == seat
    if not dealt and row.target != seat:
      continue
    inc rows
    let
      other = if dealt: row.target else: row.source
      holding = log.weaponAt(if dealt: seat else: other, row.tick)
      hp = if row.hp >= 0: $row.hp else: "?"
    result.add(&"| {clock(row.tick)} | {(if dealt: \">\" else: \"<\")} | " &
      &"{log.seatLabel(other)} | {row.weapon} | {row.amount} | " &
      &"{row.blocked} | {hp} | {holding} |\n")
  if rows == 0:
    result = "## Damage timeline\n\nNo damage dealt or taken: this seat " &
      "never traded with anybody.\n"
  result.add("\n")

proc reportCard(log: Ledger, options: Options, seat: int): string =
  let
    stats = log.statsFor(seat)
    eliminations = log.eliminations()
    seats = log.seatCount()
  var
    placement = 0
    survived = true
  for index, elimination in eliminations:
    if elimination.seat == seat:
      # Eliminated Nth out of `seats` means placement `seats - N`.
      placement = seats - index
      survived = false
  result = &"# {log.seatLabel(seat)} — {options.episode}\n\n"
  result.add(&"Ledger: `{log.path}`  \n")
  result.add(&"Game version: `{log.summary.gameVersion}`  \n")
  result.add(&"Episode: {log.lastTick()} ticks " &
    &"({int((log.lastTick() / TicksPerSecond).round)}s), {seats} seats")
  if log.summary.winner.len > 0:
    result.add(&", winner `{log.summary.winner}`")
  if not log.summary.finished:
    result.add(", **recording ended before gameover**")
  result.add("\n\n")
  result.add("## Card\n\n")
  result.add(&"| | |\n| --- | --- |\n")
  result.add(&"| Placement | " &
    (if survived: &"survived to the end of the recording"
     else: &"{placement} of {seats}") & " |\n")
  result.add(&"| Kills (death-corroborated) | {stats.kills} |\n")
  if stats.unmatchedKillRows > 0:
    result.add(&"| Unmatched kill rows | {stats.unmatchedKillRows} " &
      "(sim-side duplicate credit, see below) |\n")
  result.add(&"| Deaths | {stats.deaths} |\n")
  result.add(&"| Damage dealt | {stats.damageDealt} over {stats.hitsDealt} " &
    &"hits ({stats.blockedDealt} blocked) |\n")
  result.add(&"| Damage taken | {stats.damageTaken} over {stats.hitsTaken} " &
    &"hits ({stats.blockedTaken} blocked) |\n")
  result.add(&"| Shot accuracy | {stats.accuracy()} |\n")
  if stats.heals > 0 or stats.healed > 0:
    result.add(&"| Heals | {stats.heals} used, {stats.healed} received |\n")
  result.add(&"| Gun tiers taken | {log.tierPickups(seat).len} |\n\n")
  result.add(log.killSection(seat))
  result.add(log.deathSection(seat))
  result.add(log.tierSection(seat))
  result.add(log.damageSection(seat))

proc episodeIndex(log: Ledger, options: Options, files: Table[int, string]): string =
  let seats = log.seatCount()
  result = &"# {options.episode} — report cards\n\n"
  result.add(&"Ledger: `{log.path}`  \n")
  result.add(&"{log.lastTick()} ticks, {seats} seats, " &
    &"game version `{log.summary.gameVersion}`")
  if log.summary.winner.len > 0:
    result.add(&", winner `{log.summary.winner}`")
  result.add("\n\n")
  result.add("| Placement | Seat | Kills | Deaths | Dmg dealt | Dmg taken | " &
    "Tiers | Card |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n")
  var order: seq[(int, int)]     ## (placement, seat); 0 = survived.
  let eliminations = log.eliminations()
  for seat in 0 ..< seats:
    var placement = 0
    for index, elimination in eliminations:
      if elimination.seat == seat:
        placement = seats - index
    order.add((placement, seat))
  order.sort(proc (a, b: (int, int)): int =
    let (pa, sa) = a
    let (pb, sb) = b
    if pa == pb: return cmp(sa, sb)
    if pa == 0: return -1
    if pb == 0: return 1
    cmp(pa, pb))
  for (placement, seat) in order:
    let stats = log.statsFor(seat)
    result.add(&"| " & (if placement == 0: "survivor" else: $placement) &
      &" | {log.seatLabel(seat)} | {stats.kills} | {stats.deaths} | " &
      &"{stats.damageDealt} | {stats.damageTaken} | " &
      &"{log.tierPickups(seat).len} | " &
      # A `--seat` run writes one card, so every other row has nothing to link
      # to; an empty `[card]()` would look like a broken link rather than a
      # seat this run did not render.
      (if seat in files: "[card](" & files[seat] & ")" else: "not rendered") &
      " |\n")
  result.add("\n")
  let unmatched = log.unmatchedKills()
  if unmatched.len > 0:
    result.add("## Ledger anomalies\n\n" &
      &"{log.rowsOf(\"kill\").len} `kill` rows against " &
      &"{log.rowsOf(\"death\").len} `death` rows. The excess rows below have " &
      "no same-tick `death` row for their victim, so they are duplicate " &
      "credit, not kills, and are excluded from every count above.\n\n")
    for row in unmatched:
      result.add(&"- {clock(row.tick)}: {log.seatLabel(row.source)} credited " &
        &"a {row.weapon} kill on {log.seatLabel(row.target)} at " &
        &"{at(row.x, row.y)}\n")
    result.add("\n")

proc run(options: Options) =
  let
    log = loadLedger(options.ledgerPath)
    seats = log.seatCount()
    dir = options.outDir / fileSafe(options.episode)
  if seats == 0:
    fail("ledger mentions no seats: " & options.ledgerPath)
  if options.seat >= seats:
    fail(&"seat {options.seat} is not in this episode ({seats} seats).")
  createDir(dir)
  var files: Table[int, string]
  for seat in 0 ..< seats:
    if options.seat >= 0 and seat != options.seat:
      continue
    let name = &"seat-{seat:02}-{fileSafe(log.seatName(seat))}.md"
    writeFile(dir / name, log.reportCard(options, seat))
    files[seat] = name
    echo "wrote " & (dir / name)
  if options.writeIndex:
    writeFile(dir / "README.md", log.episodeIndex(options, files))
    echo "wrote " & (dir / "README.md")

when isMainModule:
  try:
    run(parseOptions())
  except LedgerError as e:
    stderr.writeLine("report_card failed: " & e.msg)
    quit(1)
  except ValueError as e:
    stderr.writeLine("report_card failed: " & e.msg)
    quit(1)
