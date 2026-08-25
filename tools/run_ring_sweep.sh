#!/bin/bash
# Paired BR sweep driver for the RingHoldFrac / RingSafeMarginPx calibration.
# Runs each (arm, seed) pair SEQUENTIALLY (one match at a time, per the task's
# instructions) so results aren't corrupted by fleet load contention between
# concurrently-running matches.
#
# Arms:
#   frac035   BRHOLDFRAC=0.35
#   frac055   control (unset -> shipped default 0.55)
#   frac075   BRHOLDFRAC=0.75
#   disabled  BRHOLDDISABLE=1 (wrapper's out-of-contact branch off entirely)
#
# Usage: tools/run_ring_sweep.sh
set -uo pipefail
cd /private/tmp/br-ringtune

SEEDS=(1 7 13)
MAXTICKS=4320
DEADLINE=1200
BASEPORT=21600

declare -a ARM_NAMES=(frac035 frac055 frac075 disabled)

run_one() {
  local tag="$1" port="$2" seed="$3"
  shift 3
  echo "=== $tag seed=$seed port=$port $* ===" | tee -a /tmp/br-sweep-progress.log
  env "$@" NUM_PLAYERS=12 \
    BOT_A=/private/tmp/br-ringtune/players/picasso/picasso.out \
    BOT_B=/private/tmp/br-ringtune/players/baseline/baseline.out \
    DEADLINE_SECS=$DEADLINE PORT=$port \
    BOTLOG=/tmp/bd-bots-${tag}-s${seed}.log \
    LOG=/tmp/bd-srv-${tag}-s${seed}.log \
    RESULTS=/tmp/bd-res-${tag}-s${seed}.json \
    /private/tmp/br-ringtune/tools/record_br_local.sh \
    /private/tmp/br-ringtune/replays/bd-${tag}-s${seed}.bitreplay "$seed" "$MAXTICKS" \
    >>/tmp/bd-run-${tag}-s${seed}.out 2>&1
  local rc=$?
  echo "=== $tag seed=$seed EXIT=$rc ===" | tee -a /tmp/br-sweep-progress.log
  return $rc
}

port=$BASEPORT
for seed in "${SEEDS[@]}"; do
  port=$((port+1)); run_one frac035  "$port" "$seed" BRHOLDFRAC=0.35
  port=$((port+1)); run_one frac055  "$port" "$seed"
  port=$((port+1)); run_one frac075  "$port" "$seed" BRHOLDFRAC=0.75
  port=$((port+1)); run_one disabled "$port" "$seed" BRHOLDDISABLE=1
done
echo "SWEEP COMPLETE" | tee -a /tmp/br-sweep-progress.log
