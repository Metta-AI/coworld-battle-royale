import
  std/[algorithm, json, os, sequtils, strformat, strutils, tables],
  ../src/ctf/replays,
  ../src/ctf/sim,
  extract_events

const
  ResponseTicks = 3 * 24

type
  BattleRoyaleError = object of CatchableError
  ShoutStats = object
    episodes: int
    shouts: int
    gaps: int
    gapTicks: int
    exactCooldownGaps: int
    replied: int
    dealtAfter: int
    receivedAfter: int
    diedAfter: int
    texts: CountTable[string]
    replies: CountTable[string]

proc mean(total, count: int): float =
  ## Returns an integer-total mean or zero for no samples.
  if count == 0:
    return 0.0
  total.float / count.float

proc percent(part, whole: int): float =
  ## Returns a percentage or zero for no samples.
  100.0 * mean(part, whole)

proc playerNames(extraction: ExtractResult): seq[string] =
  ## Returns stable replay player names with results as a fallback.
  result = extraction.slotAddress
  let results = parseJson(extraction.resultsJson)
  for slot in 0 ..< result.len:
    if result[slot].len == 0:
      result[slot] = results["names"][slot].getStr()

proc addReplay(
  stats: var Table[string, ShoutStats],
  replayPath: string
) =
  ## Adds shout cadence, replies, and immediate combat from one replay.
  let
    data = loadReplay(replayPath)
    extraction = extractEvents(data)
    names = extraction.playerNames()
  if not extraction.finished:
    raise newException(
      BattleRoyaleError,
      "hosted replay did not finish: " & replayPath
    )
  for name in names:
    inc stats.mgetOrPut(name, ShoutStats()).episodes
  var lastTicks = newSeqWith(names.len, -1)
  for i, event in extraction.events:
    if event.kind != ShoutEvent or
        event.source < 0 or
        event.source >= names.len:
      continue
    let
      source = event.source
      name = names[source]
    inc stats[name].shouts
    stats[name].texts.inc(event.content)
    if lastTicks[source] >= 0:
      let gap = event.tick - lastTicks[source]
      inc stats[name].gaps
      stats[name].gapTicks += gap
      if gap == 24:
        inc stats[name].exactCooldownGaps
    lastTicks[source] = event.tick
    var
      replied = false
      dealt = false
      received = false
      died = false
    for j in i + 1 ..< extraction.events.len:
      let later = extraction.events[j]
      if later.tick > event.tick + ResponseTicks:
        break
      if later.kind == ShoutEvent and
          later.source >= 0 and
          later.source < names.len and
          later.source != source and
          not replied:
        replied = true
        stats[name].replies.inc(
          names[later.source] & ":" & later.content
        )
      elif later.kind == Damage:
        if later.source == source:
          dealt = true
        if later.target == source:
          received = true
      elif later.kind == Death and later.source == source:
        died = true
    if replied:
      inc stats[name].replied
    if dealt:
      inc stats[name].dealtAfter
    if received:
      inc stats[name].receivedAfter
    if died:
      inc stats[name].diedAfter

proc printCounts(
  kind,
  player: string,
  counts: CountTable[string]
) =
  ## Prints one count table in frequency then lexical order.
  var keys: seq[string]
  for key in counts.keys:
    keys.add(key)
  keys.sort(proc (a, b: string): int =
    result = cmp(counts[b], counts[a])
    if result == 0:
      result = cmp(a, b)
  )
  for key in keys:
    echo &"{kind}\t{player}\t{key}\tcount={counts[key]}"

proc printStats(stats: Table[string, ShoutStats]) =
  ## Prints deterministic per-player shout behavior.
  var names: seq[string]
  for name in stats.keys:
    if stats[name].shouts > 0:
      names.add(name)
  names.sort()
  for name in names:
    let player = stats[name]
    echo &"SHOUTER\t{name}\tepisodes={player.episodes}" &
      &"\tshouts={player.shouts}" &
      &"\tperEpisode={mean(player.shouts, player.episodes):.2f}" &
      &"\tmeanGapSec={mean(player.gapTicks, player.gaps) / 24.0:.3f}" &
      &"\texactCooldownPct=" &
      &"{percent(player.exactCooldownGaps, player.gaps):.2f}" &
      &"\trepliedPct={percent(player.replied, player.shouts):.2f}" &
      &"\tdealtAfterPct={percent(player.dealtAfter, player.shouts):.2f}" &
      &"\treceivedAfterPct=" &
      &"{percent(player.receivedAfter, player.shouts):.2f}" &
      &"\tdiedAfterPct={percent(player.diedAfter, player.shouts):.2f}"
    printCounts("TEXT", name, player.texts)
    printCounts("REPLY", name, player.replies)

proc summarize(replayDir: string) =
  ## Summarizes shout logic across one hosted replay corpus.
  var paths: seq[string]
  for kind, path in walkDir(replayDir):
    if kind == pcFile and path.toLowerAscii().endsWith(".replay"):
      paths.add(path)
  paths.sort()
  if paths.len == 0:
    raise newException(
      BattleRoyaleError,
      "no replay files found in " & replayDir
    )
  var stats: Table[string, ShoutStats]
  for i, path in paths:
    stats.addReplay(path)
    if (i + 1) mod 20 == 0:
      stderr.writeLine("processed=", i + 1, "/", paths.len)
  echo "replays=", paths.len
  stats.printStats()

if paramCount() != 1:
  raise newException(
    BattleRoyaleError,
    "usage: summarize_shouts REPLAY_DIR"
  )

summarize(absolutePath(paramStr(1)))
