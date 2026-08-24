#!/usr/bin/env python3
"""Per-match anti-passivity statistics for one recorded FFA episode.

Reads the artifacts tools/run_ffa_demo.sh writes for a single match and emits
one JSON object of the measures the anti-passivity matrix is judged on. Every
recorder in the matrix runs THIS script, so a cell recorded on one machine is
comparable to a cell recorded on another.

Usage:
  tools/ffa_matrix_stats.py --events events-*.jsonl --results results-*.json \
      --config config-*.json --cell C1a --seed 42 \
      --doctrines legacy,passive,rush,shade,legacy,passive,rush,shade,legacy,passive,rush,shade

Definitions (fixed here so no cell re-interprets them):
  combat damage   a `damage` row with source >= 0 and a weapon that is not a
                  hazard token (ring / isolation / puddle).
  first contact   the first combat-damage tick, measured from the tick the
                  match entered `playing`, in seconds at 24 ticks/sec.
  encounter       a run of combat-damage rows between one UNORDERED pair of
                  seats; a gap longer than --encounter-gap ticks starts a new
                  encounter. Rate is encounters per minute of playing time.
  death cause     `ring` / `isolation` from the death row's weapon token,
                  `combat` when the death row names a killer (target >= 0),
                  `other` otherwise (self-inflicted or environmental).
  placement       1-based rank from results.placementSlots (best first).
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict

TICKS_PER_SEC = 24
HAZARD_WEAPONS = {"ring", "isolation", "puddle"}


def load_events(path: str) -> tuple[list[dict], dict]:
    events: list[dict] = []
    summary: dict = {}
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("type") == "summary":
                summary = row
            else:
                events.append(row)
    return events, summary


def playing_tick(events: list[dict]) -> int:
    for event in events:
        if event.get("kind") == "phase" and event.get("weapon") == "playing":
            return int(event["tick"])
    return 0


def is_combat_damage(event: dict) -> bool:
    return (
        event.get("kind") == "damage"
        and int(event.get("source", -1)) >= 0
        and event.get("weapon", "") not in HAZARD_WEAPONS
    )


def encounters(events: list[dict], gap: int) -> int:
    by_pair: dict[tuple[int, int], list[int]] = defaultdict(list)
    for event in events:
        if not is_combat_damage(event):
            continue
        a, b = int(event["source"]), int(event["target"])
        if b < 0 or a == b:
            continue
        by_pair[(min(a, b), max(a, b))].append(int(event["tick"]))
    total = 0
    for ticks in by_pair.values():
        ticks.sort()
        total += 1
        for previous, current in zip(ticks, ticks[1:]):
            if current - previous > gap:
                total += 1
    return total


def death_causes(events: list[dict]) -> dict[str, int]:
    causes = {"combat": 0, "ring": 0, "isolation": 0, "other": 0}
    for event in events:
        if event.get("kind") != "death":
            continue
        weapon = event.get("weapon", "")
        if weapon == "ring":
            causes["ring"] += 1
        elif weapon == "isolation":
            causes["isolation"] += 1
        elif int(event.get("target", -1)) >= 0:
            causes["combat"] += 1
        else:
            causes["other"] += 1
    return causes


def orphan_kills(events: list[dict]) -> int:
    """GV45 invariant: every kill row pairs with a same-tick death row."""
    deaths = {(int(e["tick"]), int(e["source"])) for e in events
              if e.get("kind") == "death"}
    orphans = 0
    for event in events:
        if event.get("kind") != "kill":
            continue
        if (int(event["tick"]), int(event["target"])) not in deaths:
            orphans += 1
    return orphans


def mean(values: list[float]) -> float | None:
    return round(sum(values) / len(values), 3) if values else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--cell", required=True)
    parser.add_argument("--seed", required=True, type=int)
    parser.add_argument(
        "--doctrines", required=True,
        help="comma-separated doctrine per seat, seat 0 first")
    parser.add_argument("--encounter-gap", type=int, default=240)
    args = parser.parse_args()

    events, summary = load_events(args.events)
    results = json.load(open(args.results))
    config = json.load(open(args.config))
    doctrines = args.doctrines.split(",")

    start = playing_tick(events)
    ticks = int(summary.get("ticks", 0))
    playing_ticks = max(1, ticks - start)
    minutes = playing_ticks / (TICKS_PER_SEC * 60)

    contact_ticks = [int(e["tick"]) for e in events if is_combat_damage(e)]
    first_contact = (
        round((min(contact_ticks) - start) / TICKS_PER_SEC, 2)
        if contact_ticks else None
    )

    # Per-seat first contact: the seat's first combat damage dealt OR taken.
    seat_contact: dict[int, int] = {}
    for event in events:
        if not is_combat_damage(event):
            continue
        for seat in (int(event["source"]), int(event["target"])):
            if seat >= 0 and seat not in seat_contact:
                seat_contact[seat] = int(event["tick"])

    placement = results.get("placementSlots", [])
    rank = {slot: index + 1 for index, slot in enumerate(placement)}
    by_doctrine: dict[str, list[int]] = defaultdict(list)
    for seat, doctrine in enumerate(doctrines):
        if seat in rank:
            by_doctrine[doctrine].append(rank[seat])

    damage_by_source = {"combat": 0, "ring": 0, "isolation": 0, "other": 0}
    for event in events:
        if event.get("kind") != "damage":
            continue
        weapon = event.get("weapon", "")
        amount = int(event.get("amount", 0))
        if weapon in ("ring", "isolation"):
            damage_by_source[weapon] += amount
        elif int(event.get("source", -1)) >= 0:
            damage_by_source["combat"] += amount
        else:
            damage_by_source["other"] += amount

    causes = death_causes(events)
    zone_deaths = causes["ring"] + causes["isolation"]
    resolved = causes["combat"] + zone_deaths + causes["other"]
    survival = results.get("survivalTicks", [])

    out = {
        "cell": args.cell,
        "seed": args.seed,
        "config": {
            key: config.get(key)
            for key in (
                "numPlayers", "mapSize", "maxTicks",
                "ringShrinkSec", "ringFloorAreaPct", "ringDamageTicks",
                "ringRecoveryTicks", "ringDamageRampTicks", "ringDamageMax",
                "passivityRadius", "passivityGraceTicks",
                "passivityDamageTicks", "passivityRecoveryTicks",
            )
        },
        "doctrines": doctrines,
        "match": {
            "ticks": ticks,
            "duration_sec": round(ticks / TICKS_PER_SEC, 2),
            "playing_sec": round(playing_ticks / TICKS_PER_SEC, 2),
            "hit_time_cap": bool(
                config.get("maxTicks") and ticks >= int(config["maxTicks"])),
            "winner_slot": results.get("winnerSlot"),
        },
        "contact": {
            "first_contact_sec": first_contact,
            "seats_never_in_contact": sorted(
                seat for seat in range(len(doctrines))
                if seat not in seat_contact),
            "mean_seat_first_contact_sec": mean([
                (tick - start) / TICKS_PER_SEC
                for tick in seat_contact.values()]),
            "encounters": encounters(events, args.encounter_gap),
            "encounters_per_min": round(
                encounters(events, args.encounter_gap) / minutes, 3),
        },
        "deaths": {
            **causes,
            "zone_share": (
                round(zone_deaths / resolved, 3) if resolved else None),
            "combat_share": (
                round(causes["combat"] / resolved, 3) if resolved else None),
        },
        "damage": damage_by_source,
        "placement_rank_by_doctrine": {
            doctrine: {"ranks": ranks, "mean": mean([float(r) for r in ranks])}
            for doctrine, ranks in sorted(by_doctrine.items())
        },
        "survival_sec": {
            "mean": mean([t / TICKS_PER_SEC for t in survival]),
            "max": (round(max(survival) / TICKS_PER_SEC, 2)
                    if survival else None),
        },
        "taint": {
            "missing_summary": not summary,
            "game_version": summary.get("gameVersion"),
            "orphan_kill_rows": orphan_kills(events),
            "seats_without_placement": sorted(
                seat for seat in range(len(doctrines)) if seat not in rank),
        },
    }
    print(json.dumps(out, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
