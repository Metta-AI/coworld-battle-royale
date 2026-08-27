#!/usr/bin/env python3
"""Regenerate the FFA pre-drop BEFORE ARM from its pinned episode list.

The arm is a PINNED SAMPLE, not a window: `tools/baselines/ffa_before_arm_gv45.json`
holds the exact episode ids, their round ids, and the replay job id behind each
one, so this script needs no league listing and no credential -- rounds keep
advancing, and "the most recent N" would name a different sample every day.

Nothing bulk is committed: the replays are public and `extract_events`
re-simulates each one and fails on a hash mismatch, so the pinned list plus the
two tools ARE the artifact. Regenerating reproduces the ledgers byte for byte.

    nim c -d:release -o:bin/extract_events tools/extract_events.nim
    nim c -d:release -o:bin/loot_economy tools/loot_economy.nim
    python3 tools/ffa_before_arm.py --work /tmp/ffa-before-arm
    bin/loot_economy /tmp/ffa-before-arm/ledgers --label "pinned GV45 before-arm"

Reads are public and unauthenticated by construction: the only host touched is
the public replay bucket. Do not add an API token to this script.
"""
import argparse
import concurrent.futures as cf
import json
import pathlib
import subprocess
import sys
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = REPO / "tools" / "baselines" / "ffa_before_arm_gv45.json"
REPLAY_URL = "https://softmax-public.s3.amazonaws.com/replays/{job}.replay"
EXPECTED_GAME_VERSION = "45"


def fetch(url: str, dest: pathlib.Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return
    with urllib.request.urlopen(url, timeout=120) as response:
        dest.write_bytes(response.read())


def one(row: dict, work: pathlib.Path, extractor: pathlib.Path) -> dict:
    """Fetch and re-extract one pinned episode; report what it re-simulated to."""
    eid = row["episode_id"]
    replay = work / "replays" / f"{eid}.replay"
    ledger = work / "ledgers" / f"{eid}.jsonl"
    results = work / "ledgers" / f"{eid}.results.json"
    out = {"episode_id": eid, "round_id": row["round_id"], "status": "ok",
           "game_version": None}
    try:
        fetch(REPLAY_URL.format(job=row["replay_job_id"]), replay)
    except Exception as error:                      # network, 404, truncation
        out["status"] = f"fetch failed: {error}"
        return out
    if not (ledger.exists() and results.exists()):
        proc = subprocess.run(
            [str(extractor), str(replay), "--out", str(ledger),
             "--results", str(results)],
            capture_output=True, text=True)
        if proc.returncode != 0:
            ledger.unlink(missing_ok=True)
            results.unlink(missing_ok=True)
            out["status"] = "extract failed: " + (
                (proc.stderr or proc.stdout).strip().splitlines()[-1][:160])
            return out
    summary = json.loads(ledger.read_text().splitlines()[-1])
    out["game_version"] = summary.get("gameVersion")
    out["ticks"] = summary.get("ticks")
    if out["game_version"] != EXPECTED_GAME_VERSION:
        # The gate is the re-simulated version, not the coworld version the
        # episode was recorded under: a rules change moves an episode OUT of
        # this arm, and it must be visible rather than averaged in.
        out["status"] = f"not GV{EXPECTED_GAME_VERSION}"
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", default="/tmp/ffa-before-arm",
                        help="scratch dir for replays and ledgers")
    parser.add_argument("--extractor", default=str(REPO / "bin" / "extract_events"))
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--limit", type=int, default=0,
                        help="regenerate only the first N pinned episodes")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    rows = manifest["gv45_arm"]
    if args.limit:
        rows = rows[:args.limit]
    work = pathlib.Path(args.work)
    (work / "replays").mkdir(parents=True, exist_ok=True)
    (work / "ledgers").mkdir(parents=True, exist_ok=True)
    extractor = pathlib.Path(args.extractor)
    if not extractor.exists():
        print(f"no extractor at {extractor}; build it first:", file=sys.stderr)
        print("  nim c -d:release -o:bin/extract_events tools/extract_events.nim",
              file=sys.stderr)
        return 2

    done, bad = [], []
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for i, out in enumerate(
                pool.map(lambda r: one(r, work, extractor), rows), 1):
            done.append(out)
            if out["status"] != "ok":
                bad.append(out)
            if i % 25 == 0 or i == len(rows):
                print(f"  {i}/{len(rows)} ok={len(done) - len(bad)}", flush=True)

    pinned = {r["episode_id"]: r for r in rows}
    drift = [d for d in done
             if d["status"] == "ok" and d["ticks"] != pinned[d["episode_id"]]["ticks"]]
    print(json.dumps({
        "pinned": len(rows),
        "regenerated": len(done) - len(bad),
        "failed_or_off_version": len(bad),
        "tick_count_drift_vs_manifest": len(drift),
    }, indent=2))
    for entry in bad[:10]:
        print(f"  {entry['episode_id']}: {entry['status']}")
    for entry in drift[:10]:
        print(f"  DRIFT {entry['episode_id']}: ticks {entry['ticks']} vs "
              f"{pinned[entry['episode_id']]['ticks']} pinned")
    print(f"ledgers in {work / 'ledgers'} -- feed that dir to bin/loot_economy")
    return 1 if bad or drift else 0


if __name__ == "__main__":
    sys.exit(main())
