#!/bin/bash
# Run one headless baseline-bot FFA and save its replay and reports.
# Usage: tools/run_ffa_demo.sh [numPlayers] [seed]
set -euo pipefail
cd "$(dirname "$0")/.."

N="${1:-12}"
SEED="${2:-42}"
PORT="${PORT:-21500}"
STAMP="$(date +%Y%m%d-%H%M%S)-${SEED}-${N}"
OUT_DIR="${DEMO_DIR:-$PWD/demo-artifacts}"
CFG="$OUT_DIR/config-$STAMP.json"
REPLAY="$OUT_DIR/ffa-$STAMP.bitreplay"
RESULTS="$OUT_DIR/results-$STAMP.json"
EVENTS="$OUT_DIR/events-$STAMP.jsonl"
SERVER_LOG="$OUT_DIR/server-$STAMP.log"
BOT_LOG="$OUT_DIR/bots-$STAMP.log"

mkdir -p "$OUT_DIR"
python3 - "$CFG" "$N" "$SEED" <<'PY'
import json, sys
path, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
cfg = json.load(open("config.br.json"))
cfg["numPlayers"] = n
cfg["minPlayers"] = n
cfg["seed"] = seed
cfg["mapSeed"] = seed
cfg["maxGames"] = 1
cfg["speed"] = 16
cfg["fastMode"] = True
json.dump(cfg, open(path, "w"))
PY

nim c -d:release --out:"$PWD/bin/ctf-server" src/ctf.nim >/dev/null
nim c -d:release --out:"$PWD/players/baseline/baseline.out" \
  players/baseline/baseline.nim >/dev/null

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

python3 - "$RESULTS" "$EVENTS" "$BOT_LOG" "$CFG" "$REPLAY" <<'PY'
import json, re, sys
results_path, events_path, bots_path, cfg_path, replay_path = sys.argv[1:]
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
    events = [json.loads(line) for line in open(events_path)
              if json.loads(line).get("kind") != "summary"]
kills = sum(e.get("kind") == "kill" for e in events)
ring_deaths = sum(e.get("kind") == "death" and
                  e.get("weapon") == "ring" for e in events)
shouts = sum(e.get("kind") == "shout" for e in events)
trace = []
for line in open(bots_path, errors="replace"):
    m = re.search(r"TRACE slot=(\d+) tick=(\d+) x=([0-9.]+) y=([0-9.]+)", line)
    if m:
        trace.append(tuple([int(m.group(1)), int(m.group(2)),
                            float(m.group(3)), float(m.group(4))]))
xs = [p[2] for p in trace]
ys = [p[3] for p in trace]
area = (cfg.get("mapWidth") or 3211) * (cfg.get("mapHeight") or 1713)
if xs and ys:
    used = max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))
    utilization = 100.0 * used / area
    utilization_text = f"{utilization:.1f}% trace bounding-box / board area"
else:
    utilization_text = "unmeasured (no bot position trace)"
print(f"winner slot: {results.get('winnerSlot', -1)}")
print(f"ticks: {events[-1].get('ticks', '?') if events else '?'}")
print(f"kills: {kills}; ring deaths: {ring_deaths}; shout events: {shouts}")
print(f"map use: {utilization_text}")
print("placement  slot  survival_s  kills  damage  score  name")
for rank, row in enumerate(rows, 1):
    print(f"{rank:9d}  {row['slot']:4d}  {row['survivalTicks']/24:10.1f}  "
          f"{row['kills']:5d}  {row['damage']:6d}  {row['score']:5d}  {row['name']}")
print(f"replay: {replay_path}")
PY
echo "server log: $SERVER_LOG"
echo "events: $EVENTS"
