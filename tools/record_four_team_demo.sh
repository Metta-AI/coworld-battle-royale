#!/bin/bash
# Records one 4-team CTF episode on a generated corner or plus map: 16 seats
# dealt round the four teams (red, blue, green, yellow — slot mod 4), each
# seat a baseline bot. Demo fixture for the multi-team replay viewer.
# Usage: tools/record_four_team_demo.sh <corners|plus> <out.bitreplay RELATIVE to repo root> <seed> [maxTicks]
set -euo pipefail
cd "$(dirname "$0")/.."
LAYOUT="$1"; OUT="$2"; SEED="$3"; MAXTICKS="${4:-5000}"; PORT="${PORT:-21200}"
CFG=$(mktemp /tmp/ctf-four-team-demo-cfg-$$-XXXXXX)
python3 - "$CFG" "$LAYOUT" "$SEED" "$MAXTICKS" <<'PY'
import json, sys
cfg = json.load(open("config.json"))
cfg["seed"] = int(sys.argv[3])
cfg["maxTicks"] = int(sys.argv[4])
cfg["speed"] = 16
cfg["maxGames"] = 1
cfg["teams"] = 4
cfg["mapPath"] = "gen"
cfg["mapLayout"] = sys.argv[2]
cfg["mapSeed"] = int(sys.argv[3])
# Drop the classic config's explicit red/blue slot assignments so the seats
# deal round all four teams (slot mod 4). Seat names are hosted-style — one
# POLICY per team, each seated four times with the "_(N)" per-connection
# suffix — so the viewer headlines policy names instead of falling back to
# the team colors.
cfg.pop("slots", None)
pols = ["redshift:v1", "bluesteel:v1", "greenhorn:v1", "goldrush:v1"]
counts = [0, 0, 0, 0]
players = []
for slot in range(16):
    team = slot % 4
    counts[team] += 1
    players.append({"name": f"{pols[team]}_({counts[team]})"})
cfg["players"] = players
json.dump(cfg, open(sys.argv[1], "w"))
PY
LOG="${LOG:-/tmp/ctf-four-team-demo-server.log}"
COGAME_HOST=127.0.0.1 COGAME_PORT=$PORT \
COGAME_CONFIG_URI="file://$CFG" \
COGAME_SAVE_REPLAY_URI="file://$PWD/$OUT" \
./bin/ctf-server > "$LOG" 2>&1 &
SERVER_PID=$!
sleep 1.5

BOT_PIDS=()
for i in $(seq 0 15); do
  CTF_BOT_FAST_READY=1 \
  COWORLD_PLAYER_WS_URL="ws://127.0.0.1:$PORT/player?slot=$i&token=0xBADA55_$i" \
    ./players/baseline/baseline.out >/dev/null 2>&1 &
  BOT_PIDS+=($!)
done
wait $SERVER_PID || true
for p in "${BOT_PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
rm -f "$CFG"
ls -la "$OUT"
