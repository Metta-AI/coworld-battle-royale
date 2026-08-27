import
  std/[algorithm, json, math, os, strutils, tables, unittest],
  "../tools/ledger",
  "../tools/loot_economy"

## The loot-economy report is the number an anti-passivity change will be judged
## on, so what is tested here is not that it prints: it is that it REFUSES —
## refuses a correlation below the n floor, refuses a tainted episode before the
## mean, and refuses to collapse a hit rate to a tier without its range bucket.

proc writeLedger(name: string, rows: seq[string]): string =
  result = getTempDir() / (name & "-" & $getCurrentProcessId() & ".jsonl")
  writeFile(result, rows.join("\n") & "\n")

proc shotRow(tick, seat: int, weapon: string, distance: float): string =
  ("""{"tick":$1,"kind":"shot_impact","source":$2,"target":-1,"weapon":"$3",""" &
    """"distance":$4,"x":0.0,"y":0.0}""") % [
      $tick, $seat, weapon, $distance]

proc resultsNode(
    names: seq[string], kills, survival, placement: seq[int]
): JsonNode =
  result = newJObject()
  result["names"] = %names
  result["kills"] = %kills
  result["survivalTicks"] = %survival
  result["placementSlots"] = %placement

suite "FFA loot economy":
  test "placement score, kill rate and the seat that has no name":
    var reason: string
    let rows = seatRows(
      "e1",
      resultsNode(
        @["a", "b", "", "d"],
        @[3, 0, 0, 1],
        @[1000, 500, 250, 2000],
        @[3, 0, 1, 2]        # placement order: seat 3, seat 0, seat 1, seat 2
      ),
      true, reason)
    check reason == ""
    check rows.len == 3                      # the nameless seat is dropped
    for row in rows:
      check row.name.len > 0
    var byIndex = initTable[int, SeatRow]()
    for row in rows:
      byIndex[row.seat] = row
    # n - 1 - rank: first place scores n-1 over the FULL seat count, so
    # dropping an unnamed seat cannot silently rescale everyone's placement.
    check byIndex[3].placement == 3.0    # rank 0 of 4 seats
    check byIndex[0].placement == 2.0    # rank 1
    check byIndex[1].placement == 1.0    # rank 2
    # kills per 1000 survival ticks, not kills.
    check abs(byIndex[3].killRate - 0.5) < 1e-9
    check abs(byIndex[0].killRate - 3.0) < 1e-9

  test "taint is refused before any mean, with the reason named":
    var reason: string
    let clean = resultsNode(
      @["a", "b"], @[1, 0], @[100, 200], @[1, 0])

    discard seatRows("e", clean, false, reason)
    check reason == "notFinished"

    # placementSlots must be a permutation of the seats: a repeat, an
    # out-of-range slot and a short list are all the same defect.
    for broken in [@[1, 1], @[0, 5], @[0]]:
      var node = copy(clean)
      node["placementSlots"] = %broken
      discard seatRows("e", node, true, reason)
      check reason == "badPlacement"

    var zeroed = copy(clean)
    zeroed["survivalTicks"] = %[100, 0]
    discard seatRows("e", zeroed, true, reason)
    check reason == "zeroSurvival"

    var noResults = newJObject()
    noResults["names"] = %(@["a"])
    discard seatRows("e", noResults, true, reason)
    check reason == "noResults"

    discard seatRows("e", clean, true, reason)
    check reason == ""

  test "correlations carry a Fisher band and suppress under the floor":
    var xs, ys: seq[float]
    for i in 0 ..< 10:
      xs.add(float(i))
      ys.add(float(i) * 2.0 - 1.0)
    check pearson(xs, ys) > 0.999             # perfectly linear
    check pearson(xs, xs.reversed()) < -0.999
    # A constant column has no correlation to report; 0.0 would read as a
    # measurement of "no relationship" instead of "not measurable".
    check pearson(xs, @[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]).isNaN

    let (lo, hi) = fisherBand(0.5, 100)
    check lo < 0.5 and 0.5 < hi
    check fisherBand(0.5, 4)[0].isNaN         # se is undefined at n <= 4

    let suppressed = correlationLine("corr(x, y)", xs, ys, MinSeatEpisodes)
    check "suppressed" in suppressed
    check "below floor 200" in suppressed
    check "n=10" in suppressed

    var big, big2: seq[float]
    for i in 0 ..< MinSeatEpisodes:
      big.add(float(i mod 7))
      big2.add(float((i * 3) mod 11))
    let printed = correlationLine(
      "corr(x, y)", big, big2, MinSeatEpisodes, "CONFOUNDED by time alive")
    check printed.startsWith("corr(x, y) = ")
    check ("n=" & $MinSeatEpisodes) in printed
    # The caveat must sit on the SAME line as the number it belongs to.
    check "CONFOUNDED by time alive" in printed
    check "\n" notin printed

  test "range buckets are the cell key, so a tier cannot be read alone":
    check bucketOf(0.0) == 0
    check bucketOf(349.9) == 0
    check bucketOf(350.0) == 1
    check bucketOf(699.9) == 1
    check bucketOf(700.0) == 2
    check bucketOf(1049.9) == 2
    check bucketOf(1050.0) == 3
    check bucketOf(9999.0) == 3

    # Two heavy shots at different ranges, one of them a hit, plus a punch kill.
    let path = writeLedger("loot-economy-cells", @[
      shotRow(10, 1, "heavy gun", 100.0),
      shotRow(20, 1, "heavy gun", 900.0),
      """{"tick":20,"kind":"hit","source":1,"target":2,"weapon":"heavy gun"}""",
      """{"tick":20,"kind":"damage","source":1,"target":2,""" &
        """"weapon":"heavy gun","amount":5}""",
      """{"tick":20,"kind":"kill","source":1,"target":2,""" &
        """"weapon":"heavy gun"}""",
      """{"tick":20,"kind":"death","source":2,"target":1}""",
      """{"tick":40,"kind":"kill","source":1,"target":3,"weapon":"fist"}""",
      """{"tick":40,"kind":"death","source":3,"target":1}""",
      """{"type":"summary","ticks":50,"events":8,"gameVersion":"45"}"""
    ])
    defer: removeFile(path)
    var
      cells = initTable[(int, Bucket), Cell]()
      unbucketed = 0
      melee = 0
    loadLedger(path).addCells(cells, unbucketed, melee)
    # Same tier, two buckets: the near shot missed and the far shot killed, so
    # a tier-only rate would report 50% for "heavy" and hide both facts.
    check cells[(3, Bucket(0))].shots == 1
    check cells[(3, Bucket(0))].hits == 0
    check cells[(3, Bucket(0))].kills == 0
    check cells[(3, Bucket(2))].shots == 1
    check cells[(3, Bucket(2))].hits == 1
    check cells[(3, Bucket(2))].kills == 1
    check cells[(3, Bucket(2))].damage == 5
    # A punch has no shot and no range: it is melee, not an unplaceable gun kill.
    check melee == 1
    check unbucketed == 0
