## Turns one episode's LEDGER (`tools/extract_events.nim` JSON lines) into a
## CUT LIST: the four beats a battle-royale highlight reel is made of, each as
## a tick range, plus the exact renderer invocations that export those ranges
## as clips.
##
##   first blood     the first death of the episode
##   lead change     the kill that hands the kill lead to a new seat
##   final 2         the elimination that leaves two seats standing
##   winning kill    the elimination that ended the episode
##
## Why a cut LIST and not a movie: the export is `tools/render_replay_movie`,
## which already takes `fromTick`/`toTick`, so a clip needs no new rendering
## code — only the ranges, which is the part that has to come out of the
## ledger. The recipe is emitted verbatim so a reviewer can paste it, and so
## the tool never has to shell out (a cut list stays useful on a machine that
## has no replay next to the ledger).
##
## Ranges are anchored, not centered: an anchor is the tick the beat HAPPENS,
## and the window is `--pre` ticks before it to `--post` after (24 ticks = 1
## second), clamped to the episode. Every range carries its anchor, so a
## consumer that wants a still instead of a clip has the frame to render.
##
## Usage:
##   nim r tools/highlight_cuts.nim <ledger.jsonl> [--replay <path>]
##                                  [--out <path>] [--recipe <path>]
##                                  [--pre <ticks>] [--post <ticks>]
##                                  [--every <ticks>] [--fps <n>]
##
## `--replay` only names the file the recipe should render; the cut list is
## computed from the ledger either way.

import std/[algorithm, json, os, strformat, strutils]

import ledger

const
  UsageText = """
Usage: nim r tools/highlight_cuts.nim <ledger.jsonl> [--replay <path>]
                                      [--out <path>] [--recipe <path>]
                                      [--pre <ticks>] [--post <ticks>]
                                      [--every <ticks>] [--fps <n>]"""
  TicksPerSecond = 24     ## the sim's tick rate; only used for readable text.

type
  Options = object
    ledgerPath: string
    replayPath: string
    outPath: string
    recipePath: string
    preTicks: int
    postTicks: int
    everyTicks: int
    fps: int

  Cut = object
    beat: string          ## machine key: first_blood / lead_change / final_2 /
                          ## winning_kill.
    label: string         ## one human-readable line.
    anchorTick: int
    startTick: int
    endTick: int
    seats: seq[int]       ## seats the beat is about, actor first.
    weapon: string
    x, y: float

proc parseOptions(): Options =
  result.preTicks = 72        ## 3 s of run-up: enough to see the approach.
  result.postTicks = 48       ## 2 s of aftermath.
  result.everyTicks = 1       ## every tick; a highlight is short.
  result.fps = 24
  var
    params = commandLineParams()
    positional: seq[string]
    i = 0
  while i < params.len:
    let arg = params[i]
    if arg in ["-h", "--help"]:
      echo UsageText
      quit(0)
    elif arg.startsWith("--"):
      if i + 1 >= params.len:
        fail(arg & " requires a value.\n" & UsageText)
      inc i
      let value = params[i]
      case arg
      of "--replay": result.replayPath = value
      of "--out": result.outPath = value
      of "--recipe": result.recipePath = value
      of "--pre": result.preTicks = parseInt(value)
      of "--post": result.postTicks = parseInt(value)
      of "--every": result.everyTicks = max(1, parseInt(value))
      of "--fps": result.fps = max(1, parseInt(value))
      else: fail("Unknown option: " & arg & "\n" & UsageText)
    else:
      positional.add(arg)
    inc i
  if positional.len != 1:
    fail("Expected exactly one ledger path.\n" & UsageText)
  result.ledgerPath = positional[0]
  if result.preTicks < 0 or result.postTicks < 0:
    fail("--pre and --post must not be negative.")

proc seconds(ticks: int): string =
  &"{ticks / TicksPerSecond:.1f}s"

proc window(options: Options, anchor, lastTick: int): (int, int) =
  ## The clip range around one anchor tick, clamped to the episode.
  (max(0, anchor - options.preTicks), min(lastTick, anchor + options.postTicks))

proc addCut(
    cuts: var seq[Cut], options: Options, lastTick: int, beat, label: string,
    anchor: int, seats: seq[int], weapon = "", x = 0.0, y = 0.0
) =
  let (startTick, endTick) = options.window(anchor, lastTick)
  cuts.add(Cut(
    beat: beat, label: label, anchorTick: anchor, startTick: startTick,
    endTick: endTick, seats: seats, weapon: weapon, x: x, y: y
  ))

proc leadChangeCuts(
    log: Ledger, options: Options, lastTick: int, cuts: var seq[Cut]
) =
  ## One cut per change of the kill LEADER, including the first seat to lead.
  ## Ties do not hand over the lead: the incumbent keeps it until somebody is
  ## strictly ahead, because a tie is not a moment — the kill that breaks it
  ## is, and that is the tick worth watching.
  var
    tally = newSeq[int](log.seatCount())
    leader = -1
  for kill in log.matchedKills():
    if kill.source < 0 or kill.source >= tally.len:
      continue
    inc tally[kill.source]
    if leader == kill.source:
      continue
    if leader >= 0 and tally[kill.source] <= tally[leader]:
      continue
    let previous = leader
    leader = kill.source
    var label = &"{log.seatName(leader)} takes the kill lead at " &
      &"{tally[leader]} with a {kill.weapon} kill on {log.seatName(kill.target)}"
    var seats = @[leader, kill.target]
    if previous >= 0:
      label.add(&", passing {log.seatName(previous)} ({tally[previous]})")
      seats.add(previous)
    cuts.addCut(options, lastTick, "lead_change", label, kill.tick, seats,
      kill.weapon, kill.x, kill.y)

proc buildCuts(log: Ledger, options: Options): seq[Cut] =
  let
    lastTick = log.lastTick()
    seats = log.seatCount()
    blood = log.firstBlood()
  if blood.tick >= 0:
    var weapon = blood.weapon
    for kill in log.matchedKills():
      if kill.tick == blood.tick and kill.target == blood.source:
        weapon = kill.weapon
        break
    let killer =
      if blood.target >= 0: log.seatName(blood.target) else: "the ring"
    result.addCut(options, lastTick, "first_blood",
      &"first blood: {killer} kills {log.seatName(blood.source)}" &
        (if weapon.len > 0: &" with {weapon}" else: ""),
      blood.tick, @[blood.target, blood.source], weapon, blood.x, blood.y)
  leadChangeCuts(log, options, lastTick, result)
  let eliminations = log.eliminations()
  for index, elimination in eliminations:
    if seats - index - 1 != 2:
      continue
    result.addCut(options, lastTick, "final_2",
      &"FINAL 2 begins: {log.seatName(elimination.seat)} is out" &
        (if elimination.killer >= 0: &" to {log.seatName(elimination.killer)}"
         else: " (no killer credited)") &
        &", leaving 2 seats standing",
      elimination.tick, @[elimination.killer, elimination.seat],
      elimination.weapon, elimination.x, elimination.y)
  # The winning kill is the LAST elimination of the recording — not simply the
  # last credited kill row, which in a ring-decided episode lands long before
  # the end and would cut a highlight reel on the wrong moment. When the last
  # seat out fell to the ring there is no winning kill, and the beat says so
  # rather than promoting an earlier kill into a decider it was not.
  if eliminations.len > 0:
    let final = eliminations[^1]
    var
      label = ""
      seats2 = @[final.killer, final.seat]
    if final.killer >= 0:
      label = &"winning kill: {log.seatName(final.killer)} kills " &
        &"{log.seatName(final.seat)} with {final.weapon}"
    else:
      label = &"winning elimination: {log.seatName(final.seat)} is out with " &
        "no killer credited (ring / environment), so this episode has no " &
        "winning kill"
      seats2 = @[final.seat]
    if log.summary.winner.len > 0:
      label.add(&" — {log.summary.winner} wins")
    elif not log.summary.finished:
      label.add(" — the recording ended before gameover")
    result.addCut(options, lastTick, "winning_kill", label, final.tick,
      seats2, final.weapon, final.x, final.y)
  result.sort(proc (a, b: Cut): int = cmp(a.anchorTick, b.anchorTick))

proc renderCommands(cuts: seq[Cut], options: Options): seq[string] =
  ## The clip export, one command per cut plus its ffmpeg assemble. Existing
  ## tooling only: `render_replay_movie` writes `frame-NNNNN.png` for every
  ## `--every`th tick in `[from, to]`, which is exactly an ffmpeg image
  ## sequence. No existing file needs to change for this to work.
  let replay =
    if options.replayPath.len > 0: options.replayPath
    else: "<episode>.bitreplay"
  # Compiled once, up front, and `-d:release`: the renderer re-simulates from
  # tick 0 to reach the cut, and a debug build of the per-pixel map code is
  # 10-50x slower (AGENTS.md), which turns a 5-second clip into minutes.
  result.add("nim c -d:release -o:/tmp/render_replay_movie " &
    "tools/render_replay_movie.nim")
  for index, cut in cuts:
    let dir = &"clips/{index:02}-{cut.beat}"
    result.add(
      &"/tmp/render_replay_movie {replay} {dir} " &
      &"{options.everyTicks} {cut.startTick} {cut.endTick}")
    result.add(
      &"ffmpeg -y -framerate {options.fps} -i {dir}/frame-%05d.png " &
      &"-pix_fmt yuv420p {dir}.mp4")

proc cutsJson(log: Ledger, options: Options, cuts: seq[Cut]): JsonNode =
  result = newJObject()
  result["ledger"] = %log.path
  result["replay"] = %options.replayPath
  result["game_version"] = %log.summary.gameVersion
  result["ticks"] = %log.lastTick()
  result["seats"] = %log.seatCount()
  result["winner"] = %log.summary.winner
  result["finished"] = %log.summary.finished
  result["draw"] = %log.summary.draw
  result["pre_ticks"] = %options.preTicks
  result["post_ticks"] = %options.postTicks
  result["cuts"] = newJArray()
  for cut in cuts:
    var seats = newJArray()
    for seat in cut.seats:
      if seat >= 0:
        seats.add(%*{"seat": seat, "name": log.seatName(seat)})
    result["cuts"].add(%*{
      "beat": cut.beat,
      "label": cut.label,
      "anchor_tick": cut.anchorTick,
      "start_tick": cut.startTick,
      "end_tick": cut.endTick,
      "duration_ticks": cut.endTick - cut.startTick,
      "duration": seconds(cut.endTick - cut.startTick),
      "at": seconds(cut.anchorTick),
      "weapon": cut.weapon,
      "x": cut.x,
      "y": cut.y,
      "seats": seats
    })
  var unmatched = newJArray()
  for row in log.unmatchedKills():
    unmatched.add(%*{
      "tick": row.tick,
      "killer": row.source,
      "victim": row.target,
      "weapon": row.weapon
    })
  # Surfaced, not hidden: kill rows without a death row are a known sim-side
  # artefact (see tools/ledger.nim's header), and a cut list that quietly
  # dropped them would make an episode look cleaner than its ledger is.
  result["diagnostics"] = %*{
    "kill_rows": log.rowsOf("kill").len,
    "death_rows": log.rowsOf("death").len,
    "matched_kills": log.matchedKills().len,
    "unmatched_kill_rows": unmatched,
    "summary_row_present": log.summary.present
  }
  result["render"] = %*{
    "tool": "tools/render_replay_movie.nim",
    "every_ticks": options.everyTicks,
    "fps": options.fps,
    "commands": %renderCommands(cuts, options)
  }

proc run(options: Options) =
  let log = loadLedger(options.ledgerPath)
  if log.rows.len == 0 and not log.summary.present:
    # An empty file is a truncated extraction, not an episode with no beats:
    # emitting an empty cut list would read as "nothing happened here".
    fail("ledger holds neither events nor a summary row: " & options.ledgerPath)
  let
    cuts = buildCuts(log, options)
    document = cutsJson(log, options, cuts)
  if options.outPath.len > 0:
    writeFile(options.outPath, document.pretty & "\n")
    echo &"wrote {cuts.len} cuts to {options.outPath}"
    for cut in cuts:
      echo &"  {cut.beat:<13} tick {cut.startTick}..{cut.endTick} " &
        &"(anchor {cut.anchorTick}) {cut.label}"
  else:
    echo document.pretty
  if options.recipePath.len > 0:
    var script = "#!/bin/bash\n# Generated by tools/highlight_cuts.nim.\n" &
      "# Run from the REPOSITORY ROOT: the renderer resolves its art through\n" &
      "# `data/`, and fails on a missing `data/ascii.png` from anywhere else.\n" &
      "set -euo pipefail\n"
    for command in renderCommands(cuts, options):
      script.add(command & "\n")
    writeFile(options.recipePath, script)
    echo &"wrote the render recipe to {options.recipePath}"

when isMainModule:
  try:
    run(parseOptions())
  except LedgerError as e:
    stderr.writeLine("highlight_cuts failed: " & e.msg)
    quit(1)
  except ValueError as e:
    stderr.writeLine("highlight_cuts failed: " & e.msg)
    quit(1)
