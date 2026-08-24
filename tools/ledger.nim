## Shared reader for one episode's LEDGER — the JSON-lines stream
## `tools/extract_events.nim` writes (and the live server's `COGAME_EVENTS_URI`
## file, which is the same serializer: `src/ctf/events.nim`).
##
## The two ledger tools (`tools/highlight_cuts.nim`,
## `tools/report_card.nim`) both need the same derived facts — who is in the
## episode, which kill rows are real, when each seat left for good — so those
## derivations live here once. A second copy would drift, and the two outputs
## disagreeing about an episode is worse than either being wrong alone.
##
## Nothing here imports the sim: a ledger is text, and reading it must not
## require the map assets or a re-simulation. Re-simulating is
## `extract_events`' job, and it validates the recorded hashes while it does
## it — by the time a ledger exists, the episode is already proven.
##
## Deliberately NOT trusted:
##
## - `kind == "kill"` rows as an elimination count. A kill row is emitted at
##   each weapon's damage site only after `killPlayer` applies a real death.
##   GV45 fixed the sim-side duplicate-credit path; an unmatched kill row now
##   indicates a replay recorded under <= GV44 (or a malformed ledger), not
##   current behavior. Death rows remain the elimination record; unmatched
##   kill rows are reported, never counted.
## - a seat's `lives` budget. It is not in the ledger, so "gone for good" is
##   derived from a `death` row with no later `respawn` row for that seat,
##   which is true for any lives count.
## - a derived tier is only as good as the assumption that `item_pickup` is the
##   SOLE tier transition. That is true at GV45, and false once drop-on-death
##   ships unless drops and pickups of drops are ledger rows; this derivation is
##   written now against GV45 data precisely because its correctness is
##   checkable there.

import std/[algorithm, json, math, os, sets, strutils, tables]

type
  LedgerError* = object of CatchableError

  TierTransition* = object
    tick*: int
    tier*: int
    origin*: string
    ## "corpse" is reserved for drop-on-death transitions.

  LootOutcome* = object
    tick*: int
    killer*: int
    victim*: int
    weapon*: string
    killerTierBefore*: int
    killerTierAfter*: int
    victimTier*: int
    tierGain*: bool
    gainTick*: int
    gainDistPx*: float
    gainAtCorpse*: bool
    gainOrigin*: string

  LedgerRow* = object
    ## One event row, in the emission order the file carries.
    tick*: int
    kind*: string
    source*: int               ## acting seat (stable join slot), -1 = n/a.
    target*: int               ## affected seat, -1 = n/a.
    weapon*: string
    amount*: int
    hp*: int
    blocked*: int
    x*, y*: float
    item*: string
    content*: string

  LedgerSummary* = object
    ## The trailing summary row. `present` is false for a ledger that was
    ## truncated mid-write — the reason the summary row exists at all.
    present*: bool
    ticks*: int
    events*: int
    gameVersion*: string
    finished*: bool
    draw*: bool
    winner*: string
    slotAddress*: seq[string]
    slotTeam*: seq[string]
    slotShotsFired*: seq[int]
    slotShotsHit*: seq[int]

  Ledger* = object
    path*: string
    rows*: seq[LedgerRow]
    summary*: LedgerSummary

  Elimination* = object
    ## A seat's last death — the one it never came back from.
    seat*: int
    tick*: int
    killer*: int               ## crediting seat, -1 for the environment.
    weapon*: string            ## "ring" or "isolation" for zone pressure,
                               ## "" when unknown.
    x*, y*: float              ## where the seat fell.

  KillRow* = object
    ## One `kill` row plus whether a `death` row corroborates it.
    row*: LedgerRow
    matched*: bool

let TierByToken* = {
  "fist": 0,
  "low gun": 1,
  "mid gun": 2,
  "heavy gun": 3
}.toTable

proc fail*(message: string) =
  raise newException(LedgerError, message)

proc readRow(node: JsonNode): LedgerRow =
  proc num(key: string, fallback = 0): int =
    if node.hasKey(key) and node[key].kind == JInt: node[key].getInt else: fallback
  proc text(key: string): string =
    if node.hasKey(key) and node[key].kind == JString: node[key].getStr else: ""
  proc real(key: string): float =
    if not node.hasKey(key): return 0.0
    case node[key].kind
    of JFloat: node[key].getFloat
    of JInt: float(node[key].getInt)
    else: 0.0
  LedgerRow(
    tick: num("tick"),
    kind: text("kind"),
    source: num("source", -1),
    target: num("target", -1),
    weapon: text("weapon"),
    amount: num("amount"),
    hp: num("hp", -1),
    blocked: num("blocked"),
    x: real("x"),
    y: real("y"),
    item: text("item"),
    content: text("content")
  )

proc readSummary(node: JsonNode): LedgerSummary =
  result.present = true
  if node.hasKey("ticks"): result.ticks = node["ticks"].getInt
  if node.hasKey("events"): result.events = node["events"].getInt
  if node.hasKey("gameVersion"): result.gameVersion = node["gameVersion"].getStr
  if node.hasKey("finished"): result.finished = node["finished"].getBool
  if node.hasKey("draw"): result.draw = node["draw"].getBool
  if node.hasKey("winner"): result.winner = node["winner"].getStr
  template readStrings(key: string, field: untyped) =
    if node.hasKey(key):
      for entry in node[key]:
        field.add(entry.getStr)
  template readInts(key: string, field: untyped) =
    if node.hasKey(key):
      for entry in node[key]:
        field.add(entry.getInt)
  readStrings("slot_address", result.slotAddress)
  readStrings("slot_team", result.slotTeam)
  readInts("slot_shots_fired", result.slotShotsFired)
  readInts("slot_shots_hit", result.slotShotsHit)

proc loadLedger*(path: string): Ledger =
  ## Parses one ledger file. A row that is neither an event nor the summary is
  ## a hard failure: silently skipping it would turn a format change into
  ## quietly missing highlights.
  if not fileExists(path):
    fail("ledger does not exist: " & path)
  result.path = path
  var lineNumber = 0
  for line in lines(path):
    inc lineNumber
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    var node: JsonNode
    try:
      node = parseJson(trimmed)
    except JsonParsingError as e:
      fail(path & ":" & $lineNumber & ": not JSON: " & e.msg)
    if node.kind != JObject:
      fail(path & ":" & $lineNumber & ": expected a JSON object.")
    if node.hasKey("type") and node["type"].getStr == "summary":
      if result.summary.present:
        fail(path & ":" & $lineNumber & ": a second summary row.")
      result.summary = readSummary(node)
      continue
    if not node.hasKey("kind"):
      fail(path & ":" & $lineNumber & ": row has neither `kind` nor `type`.")
    if result.summary.present:
      fail(path & ":" & $lineNumber & ": event row after the summary row.")
    result.rows.add(readRow(node))

proc rowsOf*(ledger: Ledger, kind: string): seq[LedgerRow] =
  for row in ledger.rows:
    if row.kind == kind:
      result.add(row)

proc seatCount*(ledger: Ledger): int =
  ## Seats the episode dealt. Use the larger of the summary roster and the
  ## highest seat any row mentions because live summaries may omit the roster.
  result = ledger.summary.slotAddress.len
  for row in ledger.rows:
    result = max(result, max(row.source, row.target) + 1)

proc seatName*(ledger: Ledger, seat: int): string =
  ## The seat's recorded join name — the league entrant on a hosted replay —
  ## or a `seat N` placeholder when the ledger carries no roster.
  if seat < 0:
    return "the environment"
  if seat < ledger.summary.slotAddress.len and
      ledger.summary.slotAddress[seat].len > 0:
    return ledger.summary.slotAddress[seat]
  "seat " & $seat

proc seatTeam*(ledger: Ledger, seat: int): string =
  if seat >= 0 and seat < ledger.summary.slotTeam.len:
    return ledger.summary.slotTeam[seat]
  ""

proc seatLabel*(ledger: Ledger, seat: int): string =
  ## "Bot_3 (seat 3, red)" — every human-facing mention of a seat, one shape.
  ## A ledger with no roster degrades to plain "seat 3" instead of the useless
  ## "seat 3 (seat 3)".
  if seat < 0:
    return "the environment"
  let
    name = ledger.seatName(seat)
    team = ledger.seatTeam(seat)
    placeholder = name == "seat " & $seat
  result = name
  if placeholder and team.len == 0:
    return
  result.add(if placeholder: " (" & team else: " (seat " & $seat)
  if not placeholder and team.len > 0:
    result.add(", " & team)
  result.add(")")

proc killRows*(ledger: Ledger): seq[KillRow] =
  ## Every `kill` row, each tagged with whether a `death` row for the same
  ## victim on the same tick corroborates it (see this module's header).
  var deaths = initHashSet[(int, int)]()
  for row in ledger.rows:
    if row.kind == "death":
      deaths.incl((row.tick, row.source))
  for row in ledger.rows:
    if row.kind == "kill":
      result.add(KillRow(row: row, matched: (row.tick, row.target) in deaths))

proc matchedKills*(ledger: Ledger): seq[LedgerRow] =
  ## Kill rows a death row corroborates, in tick order — the only kill set
  ## anything derived (leaderboards, lead changes, the winning kill) uses.
  for entry in ledger.killRows():
    if entry.matched:
      result.add(entry.row)

proc unmatchedKills*(ledger: Ledger): seq[LedgerRow] =
  ## Kill rows with no death row behind them. Reported, never counted.
  for entry in ledger.killRows():
    if not entry.matched:
      result.add(entry.row)

proc phaseTick*(ledger: Ledger, phase: string): int =
  ## The tick the episode entered `phase` ("playing" / "gameover"), or -1.
  result = -1
  for row in ledger.rows:
    if row.kind == "phase" and row.weapon == phase:
      return row.tick

proc lastTick*(ledger: Ledger): int =
  ## The episode's final tick: the summary's count, else the last row's tick.
  if ledger.summary.present and ledger.summary.ticks > 0:
    return ledger.summary.ticks
  for row in ledger.rows:
    result = max(result, row.tick)

proc eliminations*(ledger: Ledger): seq[Elimination] =
  ## Each seat's terminal death, earliest first: a `death` row with no later
  ## `respawn` row for that seat. A seat that respawned after its last death
  ## (or never died) is absent — it survived the recording.
  var
    lastDeath = initTable[int, LedgerRow]()
    lastRespawn = initTable[int, int]()
  for row in ledger.rows:
    case row.kind
    of "death": lastDeath[row.source] = row
    of "respawn": lastRespawn[row.source] = row.tick
    else: discard
  for seat, death in lastDeath:
    if lastRespawn.getOrDefault(seat, -1) > death.tick:
      continue
    var weapon = death.weapon
    if weapon.len == 0:
      # The victim-side death row carries no weapon for a combat death; the
      # co-tick kill row is where the weapon is known first-hand.
      for kill in ledger.rows:
        if kill.kind == "kill" and kill.tick == death.tick and
            kill.target == seat:
          weapon = kill.weapon
          break
    result.add(Elimination(
      seat: seat, tick: death.tick, killer: death.target, weapon: weapon,
      x: death.x, y: death.y
    ))
  result.sort(proc (a, b: Elimination): int = cmp(a.tick, b.tick))

proc survivorsAfter*(ledger: Ledger, seats: int, tick: int): int =
  ## Seats still in the episode immediately after `tick`.
  result = seats
  for elimination in ledger.eliminations():
    if elimination.tick <= tick:
      dec result

proc firstBlood*(ledger: Ledger): LedgerRow =
  ## The episode's first death row, or a zeroed row when nobody died.
  for row in ledger.rows:
    if row.kind == "death":
      return row
  LedgerRow(tick: -1, source: -1, target: -1, hp: -1)

proc tierPickups*(ledger: Ledger, seat: int): seq[LedgerRow] =
  ## One seat's WEAPON-TIER pickups ("low gun" / "mid gun" / "heavy gun"),
  ## which are the FFA loot ladder; other pickups (med kit, shield, grenade,
  ## spray can, barrier) are not tiers and stay out.
  for row in ledger.rows:
    if row.kind == "item_pickup" and row.source == seat and
        TierByToken.hasKey(row.item):
      result.add(row)

proc isFfaLedger*(ledger: Ledger): bool =
  ## Whether the ledger carries FFA identity weapon tiers. CTF ledgers use a
  ## flat "gun" token and have no gun pickups, so tier derivations are
  ## meaningless there; callers should gate on this instead of reading an
  ## all-zero timeline.
  for row in ledger.rows:
    if TierByToken.hasKey(row.weapon):
      return true
    if row.kind == "item_pickup" and TierByToken.hasKey(row.item):
      return true

proc tierTimeline*(ledger: Ledger): Table[int, seq[TierTransition]] =
  ## Returns each seat's FFA weapon-tier history, seeded unarmed at tick 0.
  ## `start` is the seeded state and `spawn` is a gun pickup.
  result = initTable[int, seq[TierTransition]]()
  let seats = ledger.seatCount()
  for seat in 0 ..< seats:
    result[seat] = @[
      TierTransition(tick: 0, tier: 0, origin: "start")
    ]
  for row in ledger.rows:
    if row.kind != "item_pickup" or not TierByToken.hasKey(row.item):
      continue
    if not result.hasKey(row.source):
      continue
    result[row.source].add(TierTransition(
      tick: row.tick,
      tier: TierByToken[row.item],
      origin: "spawn"
    ))
  for seat in result.keys:
    result[seat].sort(proc (a, b: TierTransition): int = cmp(a.tick, b.tick))

proc tierAt*(
    timeline: Table[int, seq[TierTransition]], seat, tick: int
): int =
  ## Returns the last known tier at or before `tick`, or unarmed.
  if not timeline.hasKey(seat):
    return
  for transition in timeline[seat]:
    if transition.tick > tick:
      break
    result = transition.tier

proc lootOutcomes*(
    ledger: Ledger, windowTicks: int, radiusPx: float
): seq[LootOutcome] =
  ## Derives one outcome per credited kill. At GV45 any tier gain can only
  ## originate from a `spawn` pickup because nothing drops. `radiusPx` is
  ## annotation-only: it lets callers ask whether the gain happened at the
  ## corpse, without filtering gains that happened farther away.
  let timeline = ledger.tierTimeline()
  for kill in ledger.matchedKills():
    let
      windowEnd = kill.tick + max(0, windowTicks)
      before = timeline.tierAt(kill.source, kill.tick)
      after = timeline.tierAt(kill.source, windowEnd)
      victimTier = timeline.tierAt(kill.target, kill.tick)
    var
      gainTick = -1
      gainDist = -1.0
      gainOrigin = ""
    if after > before:
      for transition in timeline.getOrDefault(kill.source, @[]):
        if transition.tick <= kill.tick:
          continue
        if transition.tick > windowEnd:
          break
        if transition.tier <= before:
          continue
        gainTick = transition.tick
        gainOrigin = transition.origin
        for pickup in ledger.rows:
          if pickup.kind == "item_pickup" and
              pickup.source == kill.source and
              pickup.tick == gainTick and
              TierByToken.hasKey(pickup.item) and
              TierByToken[pickup.item] == transition.tier:
            let
              dx = pickup.x - kill.x
              dy = pickup.y - kill.y
            gainDist = hypot(dx, dy)
            break
        break
    result.add(LootOutcome(
      tick: kill.tick,
      killer: kill.source,
      victim: kill.target,
      weapon: kill.weapon,
      killerTierBefore: before,
      killerTierAfter: after,
      victimTier: victimTier,
      tierGain: after > before,
      gainTick: gainTick,
      gainDistPx: gainDist,
      gainAtCorpse: gainDist >= 0.0 and gainDist <= radiusPx,
      gainOrigin: gainOrigin
    ))
