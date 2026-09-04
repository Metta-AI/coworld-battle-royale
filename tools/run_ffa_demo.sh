#!/bin/bash
# Run one headless baseline-bot FFA and save its replay and reports.
# Usage: tools/run_ffa_demo.sh [numPlayers] [seed] [arm]
# Arms: A/B/C are the prior matrix; D1=huge, D2=large, D3=small, D4=small;
# E1=control, E2=damage, E3=persistent hurt fire, E4=combined economy;
# R35-150=ring control, R20-100=legacy comparison; DEFAULT uses shipped I.
set -euo pipefail
cd "$(dirname "$0")/.."

N="${1:-12}"
SEED="${2:-42}"
ARM="${3:-${DEMO_ARM:-I}}"
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
elif arm in ("E1", "E2", "E3", "E4"):
    cfg["mapSize"] = "huge"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 35
    cfg["ringRecoveryTicks"] = 2
elif arm == "DEFAULT":
    cfg["mapSize"] = "huge"
    cfg["ringFloorAreaPct"] = 3
    cfg["ringRecoveryTicks"] = 2
elif arm == "R35-150":
    cfg["mapSize"] = "huge"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 35
    cfg["ringRecoveryTicks"] = 2
elif arm == "R20-100":
    cfg["mapSize"] = "huge"
    cfg["ringShrinkSec"] = 100
    cfg["ringFloorAreaPct"] = 20
    cfg["ringRecoveryTicks"] = 2
elif arm in ("H", "I"):
    cfg["mapSize"] = "huge"
    cfg["ringShrinkSec"] = 150
    cfg["ringFloorAreaPct"] = 3
    cfg["ringRecoveryTicks"] = 2
else:
    raise SystemExit("arm must be A, B, C, D1, D2, D3, D4, E1, E2, E3, E4, H, I, R35-150, R20-100, or DEFAULT")
if arm in ("E2", "E4"):
    cfg["ffaGunDamage"] = 4
if arm == "E4":
    cfg["ffaMedKitSpawns"] = 1
json.dump(cfg, open(path, "w"))
PY

if [[ "${DEMO_BUILD:-1}" != "0" ]]; then
  nim c -d:release --out:"$PWD/bin/ctf-server" src/ctf.nim >/dev/null
  nim c -d:release --out:"$PWD/players/baseline/baseline.out" \
    players/baseline/baseline.nim >/dev/null
fi
VALIDATOR_BIN="${CTF_EXTRACT_EVENTS_BIN:-${TMPDIR:-/tmp}/coworld-extract-events-$$}"
if [[ ! -x "$VALIDATOR_BIN" ]]; then
  nim c -d:release --out:"$VALIDATOR_BIN" tools/extract_events.nim >/dev/null
fi

COGAME_HOST=127.0.0.1 COGAME_PORT="$PORT" \
COGAME_FFA_STARTUP_BARRIER=1 \
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

BOT_ENV=(
  CTF_BOT_FAST_READY=1
  CTF_BOT_SHOUT=1
  CTF_BOT_TRACE=1
  CTF_BOT_TRACE_TICK_SCALE=16
  CTF_BOT_TRACE_MAX_TICKS=8640
  CTF_BOT_FFA_DOCTRINE="${CTF_BOT_FFA_DOCTRINE:-legacy}"
)
PLAYER_BIN="${DEMO_PLAYER_BIN:-$PWD/players/baseline/baseline.out}"
case "$ARM" in
  E1|E2)
    BOT_ENV+=(CTF_BOT_FFA_RETREAT_HP=12 CTF_BOT_FFA_FIRE_WHILE_HURT=0)
    ;;
  E3|E4)
    BOT_ENV+=(CTF_BOT_FFA_RETREAT_HP=6 CTF_BOT_FFA_FIRE_WHILE_HURT=1)
    ;;
  I)
    BOT_ENV+=(CTF_BOT_FFA_LATE_CLOSE=1)
    ;;
esac

for slot in $(seq 0 $((N - 1))); do
  env "${BOT_ENV[@]}" \
    "COWORLD_PLAYER_WS_URL=ws://127.0.0.1:$PORT/player?name=Bot_$slot&slot=$slot&token=0xBADA55_$slot" \
    "$PLAYER_BIN" >>"$BOT_LOG" 2>&1 &
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

if ! "$VALIDATOR_BIN" "$REPLAY" >/dev/null; then
  echo "replay validation failed: $REPLAY" >&2
  exit 1
fi

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
min_survival_sec = min(survival_ticks, default=0) / 24
trace = []
contact = {}
fire_decisions = []
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
    m = re.search(
        r"FFA_TRACE slot=(\d+) tick=(\d+) x=([0-9.]+) y=([0-9.]+) "
        r"objective=(\S+) action=(\S+) target=(\d+) visibleActors=(\d+) "
        r"contactTicks=(\d+) sightingEpisodes=(\d+) "
        r"targetDist=(-?[0-9.]+) aimError=(-?\d+) rayClear=(\d+) "
        r"wantFire=(\d+) trigger=(\d+) reason=(\S+) gateFailed=(\S+) "
        r"healthy=(\d+) targetCritical=(\d+) localAdvantage=(\d+) "
        r"duplicatePairs=(\d+) selfLikeActors=(\d+)", line)
    if m:
        fire_decisions.append({
            "slot": int(m.group(1)),
            "tick": int(m.group(2)),
            "x": float(m.group(3)),
            "y": float(m.group(4)),
            "objective": m.group(5),
            "action": m.group(6),
            "target": int(m.group(7)),
            "visibleActors": int(m.group(8)),
            "contactTicks": int(m.group(9)),
            "sightingEpisodes": int(m.group(10)),
            "targetDist": float(m.group(11)),
            "aimError": int(m.group(12)),
            "rayClear": int(m.group(13)),
            "wantFire": int(m.group(14)),
            "trigger": int(m.group(15)),
            "reason": m.group(16),
            "gateFailed": m.group(17),
            "healthy": int(m.group(18)),
            "targetCritical": int(m.group(19)),
            "localAdvantage": int(m.group(20)),
            "duplicatePairs": int(m.group(21)),
            "selfLikeActors": int(m.group(22)),
        })
xs = [p[2] for p in trace]
ys = [p[3] for p in trace]
last_trace_tick = max((p[1] for p in trace), default=-1)
visible_decisions = [d for d in fire_decisions if d["visibleActors"] > 0]
reason_counts = {}
gate_failed_counts = {}
for decision in visible_decisions:
    reason = decision["reason"]
    reason_counts[reason] = reason_counts.get(reason, 0) + 1
    if reason == "engage-gate-false":
        for failed in decision["gateFailed"].split(","):
            if failed:
                gate_failed_counts[failed] = gate_failed_counts.get(failed, 0) + 1
aim_errors = [
    d["aimError"] for d in visible_decisions
    if d["reason"] == "aim-outside-deadband"
]
reason_total = len(visible_decisions)
reason_pct = {
    reason: 100.0 * count / reason_total
    for reason, count in reason_counts.items()
} if reason_total else {}
mean_visible_actors = (
    sum(d["visibleActors"] for d in fire_decisions) / len(fire_decisions)
    if fire_decisions else 0.0
)
target_decisions = [d for d in fire_decisions if d["target"]]
mean_nearest_target_distance = (
    sum(d["targetDist"] for d in target_decisions) / len(target_decisions)
    if target_decisions else 0.0
)
mean_visible_actors_when_target = (
    sum(d["visibleActors"] for d in target_decisions) / len(target_decisions)
    if target_decisions else 0.0
)
duplicate_pair_samples = sum(d["duplicatePairs"] for d in fire_decisions)
self_like_actor_samples = sum(d["selfLikeActors"] for d in fire_decisions)
duplicate_pair_ticks = sum(
    d["duplicatePairs"] > 0 for d in fire_decisions)
self_like_actor_ticks = sum(
    d["selfLikeActors"] > 0 for d in fire_decisions)
trigger_presses = sum(d["trigger"] for d in visible_decisions)
want_fire_ticks = sum(d["wantFire"] for d in visible_decisions)
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
    "traceLastTick": last_trace_tick,
    "traceCoveragePct": (
        100.0 * last_trace_tick / match_ticks
        if last_trace_tick >= 0 and match_ticks else 0.0
    ),
    "meanContactPct": (
        100.0 * sum(v["contactTicks"] for v in contact.values()) /
        sum(survival_ticks)
        if contact and sum(survival_ticks) > 0 else 0.0
    ),
    "contactDenominatorTicks": sum(survival_ticks),
    "fireDecisionTicks": len(fire_decisions),
    "fireVisibleDecisionTicks": reason_total,
    "fireReasonCounts": reason_counts,
    "fireReasonPct": reason_pct,
    "fireGateFailedCounts": gate_failed_counts,
    "aimErrorMagnitudes": {
        "count": len(aim_errors),
        "mean": sum(aim_errors) / len(aim_errors) if aim_errors else 0.0,
        "max": max(aim_errors, default=0),
        "p50": median(aim_errors) if aim_errors else 0.0,
        "p95": (
            sorted(aim_errors)[int(0.95 * (len(aim_errors) - 1))]
            if aim_errors else 0.0
        ),
    },
    "meanVisibleActors": mean_visible_actors,
    "meanVisibleActorsWhenTarget": mean_visible_actors_when_target,
    "meanNearestTargetDistance": mean_nearest_target_distance,
    "duplicatePairSamples": duplicate_pair_samples,
    "duplicatePairTicks": duplicate_pair_ticks,
    "selfLikeActorSamples": self_like_actor_samples,
    "selfLikeActorTicks": self_like_actor_ticks,
    "visibleWantFireTicks": want_fire_ticks,
    "visibleTriggerPresses": trigger_presses,
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
    "lastKillTick": max((e["tick"] for e in events if e.get("kind") == "kill"),
                        default=-1),
    "playersAliveAtCap": alive_at_cap,
    "endCondition": end_condition,
    "matchTicks": match_ticks,
    "medianSurvivalSec": median_survival_sec,
    "minSurvivalSec": min_survival_sec,
    "shoutEvents": shouts,
    "ticks": events[-1].get("ticks", None) if events else None,
    "replay": replay_path,
    "flagged": end_condition == "wipe" or alive_at_cap <= 2,
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
print(f"last kill tick: {metrics['lastKillTick']}; "
      f"minimum survival seconds: {min_survival_sec:.1f}")
print(f"ending: {end_condition}")
print(f"median survival seconds: {median_survival_sec:.1f}; shout events: {shouts}")
print(f"mean contact ticks: {metrics['meanContactPct']:.2f}% of live survival ticks; "
      f"mean sighting episodes: {metrics['meanSightingEpisodes']:.2f}; "
      f"kills/sighting episode: {metrics['killsPerSightingEpisode']:.4f}")
print(f"trace last tick: {last_trace_tick}; "
      f"trace coverage: {metrics['traceCoveragePct']:.1f}%")
print(f"fire decisions: {len(fire_decisions)}; visible-target decisions: "
      f"{reason_total}; reason distribution: {reason_pct}")
print(f"visible actors mean: {mean_visible_actors:.2f}; "
      f"nearest target distance mean: {mean_nearest_target_distance:.1f}; "
      f"wantFire ticks: {want_fire_ticks}; trigger presses: {trigger_presses}")
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
