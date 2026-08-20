#!/bin/bash
# Run one headless baseline-bot FFA and save its replay and reports.
# Usage: tools/run_ffa_demo.sh [numPlayers] [seed] [arm]
# Arms: A/B/C are the prior matrix; D1=huge, D2=large, D3=small, D4=small.
set -euo pipefail
cd "$(dirname "$0")/.."

N="${1:-12}"
SEED="${2:-42}"
ARM="${3:-${DEMO_ARM:-C}}"
ARM="$(printf '%s' "$ARM" | tr '[:lower:]' '[:upper:]')"
PORT="${PORT:-21500}"
STAMP="$(date +%Y%m%d-%H%M%S)-${ARM}-${SEED}-${N}"
OUT_DIR="${DEMO_DIR:-$PWD/demo-artifacts}"
CFG="$OUT_DIR/config-$STAMP.json"
REPLAY="$OUT_DIR/ffa-$STAMP.bitreplay"
RESULTS="$OUT_DIR/results-$STAMP.json"
EVENTS="$OUT_DIR/events-$STAMP.jsonl"
SERVER_LOG="$OUT_DIR/server-$STAMP.log"
BOT_LOG="$OUT_DIR/bots-$STAMP.log"
METRICS="$OUT_DIR/metrics-$STAMP.json"

mkdir -p "$OUT_DIR"
python3 - "$CFG" "$N" "$SEED" "$ARM" <<'PY'
import json, sys
path, n, seed, arm = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
cfg = json.load(open("config.br.json"))
cfg["numPlayers"] = n
cfg["minPlayers"] = n
cfg["seed"] = seed
cfg["mapSeed"] = seed
cfg["maxGames"] = 1
cfg["speed"] = 16
cfg["fastMode"] = True
if arm == "A":
    cfg["mapSize"] = "giant"
    cfg["ringShrinkSec"] = 240
    cfg["ringFloorAreaPct"] = 40
    cfg["ringRecoveryTicks"] = 0
elif arm == "B":
    cfg["mapSize"] = "giant"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 35
    cfg["ringRecoveryTicks"] = 2
elif arm in ("C", "D1"):
    cfg["mapSize"] = "huge"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 35
    cfg["ringRecoveryTicks"] = 2
elif arm == "D2":
    cfg["mapSize"] = "large"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 35
    cfg["ringRecoveryTicks"] = 2
elif arm in ("D3", "D4"):
    cfg["mapSize"] = "small"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 35
    cfg["ringRecoveryTicks"] = 2
else:
    raise SystemExit("arm must be A, B, C, D1, D2, D3, or D4")
json.dump(cfg, open(path, "w"))
PY

if [[ "${DEMO_BUILD:-1}" != "0" ]]; then
  nim c -d:release --out:"$PWD/bin/ctf-server" src/ctf.nim >/dev/null
  nim c -d:release --out:"$PWD/players/baseline/baseline.out" \
    players/baseline/baseline.nim >/dev/null
fi

COGAME_HOST=127.0.0.1 COGAME_PORT="$PORT" \
COGAME_CONFIG_URI="file://$CFG" \
COGAME_SAVE_REPLAY_URI="file://$REPLAY" \
COGAME_RESULTS_URI="file://$RESULTS" \
COGAME_EVENTS_URI="file://$EVENTS" \
"$PWD/bin/ctf-server" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
BOT_PIDS=()
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  for pid in "${BOT_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT

for _ in $(seq 1 240); do
  if python3 - "$PORT" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.25)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
  then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    tail -40 "$SERVER_LOG" >&2
    exit 1
  fi
  sleep 0.25
done
python3 - "$PORT" <<'PY' || {
import socket, sys
s = socket.socket()
s.settimeout(0.25)
s.connect(("127.0.0.1", int(sys.argv[1])))
s.close()
PY
  tail -40 "$SERVER_LOG" >&2
  exit 1
}

for slot in $(seq 0 $((N - 1))); do
  CTF_BOT_FAST_READY=1 CTF_BOT_SHOUT=1 CTF_BOT_TRACE=1 \
    COWORLD_PLAYER_WS_URL="ws://127.0.0.1:$PORT/player?slot=$slot&token=0xBADA55_$slot" \
    "$PWD/players/baseline/baseline.out" >>"$BOT_LOG" 2>&1 &
  BOT_PIDS+=("$!")
done

deadline=$((SECONDS + 900))
while kill -0 "$SERVER_PID" 2>/dev/null; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "demo exceeded 15 minutes" >&2
    tail -40 "$SERVER_LOG" >&2
    exit 1
  fi
  sleep 1
done
wait "$SERVER_PID" || {
  tail -40 "$SERVER_LOG" >&2
  exit 1
}

python3 - "$RESULTS" "$EVENTS" "$BOT_LOG" "$CFG" "$REPLAY" "$METRICS" "$ARM" <<'PY'
import json, re, sys
from statistics import median
results_path, events_path, bots_path, cfg_path, replay_path, metrics_path, arm = sys.argv[1:]
results = json.load(open(results_path))
cfg = json.load(open(cfg_path))
rows = []
for i, name in enumerate(results["names"]):
    rows.append({
        "slot": i,
        "name": name,
        "survivalTicks": results.get("survivalTicks", [0] * len(results["names"]))[i],
        "kills": results["kills"][i],
        "damage": results.get("damage", [0] * len(results["names"]))[i],
        "score": results["scores"][i],
    })
rows.sort(key=lambda row: results.get("placementSlots", []).index(row["slot"])
          if row["slot"] in results.get("placementSlots", []) else row["slot"])
events = []
if open(events_path).read().strip():
    for line in open(events_path):
        event = json.loads(line)
        if event.get("kind") != "summary":
            events.append(event)
kills = sum(e.get("kind") == "kill" for e in events)
shots = sum(e.get("kind") == "shot" for e in events)
hits = sum(e.get("kind") == "hit" for e in events)
damage_events = sum(e.get("kind") == "damage" for e in events)
deaths = sum(e.get("kind") == "death" for e in events)
ring_deaths = sum(e.get("kind") == "death" and e.get("weapon") == "ring"
                  for e in events)
shouts = sum(e.get("kind") == "shout" for e in events)
first_kill_tick = min((e["tick"] for e in events if e.get("kind") == "kill"),
                      default=-1)
survival_ticks = results.get("survivalTicks", [])
max_ticks = cfg.get("maxTicks", 0)
alive_at_cap = sum(t >= max_ticks for t in survival_ticks)
match_ticks = max(survival_ticks, default=0)
end_condition = "cap" if alive_at_cap > 0 else "wipe"
median_survival_sec = median(survival_ticks) / 24 if survival_ticks else 0
trace = []
contact = {}
for line in open(bots_path, errors="replace"):
    m = re.search(r"TRACE slot=(\d+) tick=(\d+) x=([0-9.]+) y=([0-9.]+)", line)
    if m:
        trace.append(tuple([int(m.group(1)), int(m.group(2)),
                            float(m.group(3)), float(m.group(4))]))
    m = re.search(
        r"TRACE slot=(\d+).*contactTicks=(\d+) sightingEpisodes=(\d+)", line)
    if m:
        slot = int(m.group(1))
        contact[slot] = {
            "contactTicks": int(m.group(2)),
            "sightingEpisodes": int(m.group(3)),
        }
xs = [p[2] for p in trace]
ys = [p[3] for p in trace]
map_dimensions = {
    "small": (1050, 560),
    "standard": (1235, 659),
    "large": (1606, 857),
    "huge": (2223, 1186),
    "giant": (3211, 1713),
}
map_width, map_height = map_dimensions[cfg["mapSize"]]
area = map_width * map_height
if xs and ys:
    used = max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))
    utilization = 100.0 * used / area
    utilization_text = f"{utilization:.1f}% trace bounding-box / board area"
else:
    utilization_text = "unmeasured (no bot position trace)"
metrics = {
    "arm": arm,
    "seed": int(cfg["seed"]),
    "numPlayers": int(cfg["numPlayers"]),
    "mapSize": cfg.get("mapSize", ""),
    "mapWidth": map_width,
    "mapHeight": map_height,
    "mapArea": area,
    "areaPerAgent": area / int(cfg["numPlayers"]),
    "contactTicksByAgent": contact,
    "meanContactPct": (
        100.0 * sum(v["contactTicks"] for v in contact.values()) /
        (int(cfg["numPlayers"]) * match_ticks)
        if contact and match_ticks else 0.0
    ),
    "meanSightingEpisodes": (
        sum(v["sightingEpisodes"] for v in contact.values()) /
        len(contact) if contact else 0.0
    ),
    "killsPerSightingEpisode": (
        kills / sum(v["sightingEpisodes"] for v in contact.values())
        if sum(v["sightingEpisodes"] for v in contact.values()) > 0 else 0.0
    ),
    "shotEvents": shots,
    "damageEvents": damage_events,
    "hits": hits,
    "kills": kills,
    "deaths": deaths,
    "ringDeaths": ring_deaths,
    "firstKillTick": first_kill_tick,
    "playersAliveAtCap": alive_at_cap,
    "endCondition": end_condition,
    "matchTicks": match_ticks,
    "medianSurvivalSec": median_survival_sec,
    "shoutEvents": shouts,
    "ticks": events[-1].get("ticks", None) if events else None,
    "replay": replay_path,
}
json.dump(metrics, open(metrics_path, "w"), indent=2)
print(f"arm: {arm}; seed: {cfg['seed']}; map: {cfg.get('mapSize', '?')} "
      f"{map_width}x{map_height} ({area} px²; "
      f"{area / int(cfg['numPlayers']):.0f} px²/agent)")
print(f"winner slot: {results.get('winnerSlot', -1)}")
print(f"ticks: {events[-1].get('ticks', '?') if events else '?'}")
print(f"shots: {shots}; damage events: {damage_events}; hits: {hits}")
print(f"kills: {kills}; deaths: {deaths}; ring deaths: {ring_deaths}")
print(f"first kill tick: {first_kill_tick}; players alive at cap: {alive_at_cap}")
print(f"ending: {end_condition}")
print(f"median survival seconds: {median_survival_sec:.1f}; shout events: {shouts}")
print(f"mean contact ticks: {metrics['meanContactPct']:.2f}% of cap; "
      f"mean sighting episodes: {metrics['meanSightingEpisodes']:.2f}; "
      f"kills/sighting episode: {metrics['killsPerSightingEpisode']:.4f}")
print(f"map use: {utilization_text}")
print("placement  slot  survival_s  kills  damage  score  name")
for rank, row in enumerate(rows, 1):
    print(f"{rank:9d}  {row['slot']:4d}  {row['survivalTicks']/24:10.1f}  "
          f"{row['kills']:5d}  {row['damage']:6d}  {row['score']:5d}  {row['name']}")
print(f"replay: {replay_path}")
print(f"metrics: {metrics_path}")
PY
echo "server log: $SERVER_LOG"
echo "events: $EVENTS"
