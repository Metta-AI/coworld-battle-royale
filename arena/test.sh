#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/coworld-ctf-arena.XXXXXX")"
trap 'rm -r "$test_dir"' EXIT

"$repo_dir/arena/build.sh"
nim c -d:release --mm:arc --exceptions:goto \
  --path:"$repo_dir" --path:"$repo_dir/src" \
  --path:"$repo_dir/players/baseline" --out:"$test_dir/native-parity" \
  "$repo_dir/tests/arena_native_parity.nim"
mkdir "$test_dir/ctf" "$test_dir/ffa"
"$test_dir/native-parity" "$test_dir/ctf"
"$test_dir/native-parity" ffa "$test_dir/ffa"
test -s "$test_dir/ctf/hashes"
test -s "$test_dir/ctf/player_masks"
test -s "$test_dir/ctf/results"
test -s "$test_dir/ffa/hashes"
test -s "$test_dir/ffa/player_masks"
test -s "$test_dir/ffa/results"

npx --yes @bytecodealliance/jco@1.20.0 transpile \
  "$repo_dir/arena/ctf_game.wasm" -o "$test_dir/game" \
  -M 'softmax:game/output=../test_host_output.mjs' \
  -M 'softmax:game/log=../test_host_output.mjs' -q
npx --yes @bytecodealliance/jco@1.20.0 transpile \
  "$repo_dir/arena/ctf_player_baseline.wasm" -o "$test_dir/player" \
  -M 'softmax:player/log=../test_host_output.mjs' -q
cp "$repo_dir/arena/test_components.mjs" "$test_dir/test_components.mjs"
cp "$repo_dir/arena/test_host_output.mjs" "$test_dir/test_host_output.mjs"
printf '{"type":"module","dependencies":{"@bytecodealliance/preview2-shim":"0.17.9"}}\n' \
  > "$test_dir/package.json"
npm install --silent --prefix "$test_dir"
NATIVE_HASHES_FILE="$test_dir/ctf/hashes" \
NATIVE_PLAYER_MASKS_FILE="$test_dir/ctf/player_masks" \
NATIVE_RESULTS_FILE="$test_dir/ctf/results" \
  node "$test_dir/test_components.mjs"
FFA_CONFIG="$repo_dir/config.br.json" \
NATIVE_HASHES_FILE="$test_dir/ffa/hashes" \
NATIVE_PLAYER_MASKS_FILE="$test_dir/ffa/player_masks" \
NATIVE_RESULTS_FILE="$test_dir/ffa/results" \
  node "$test_dir/test_components.mjs" ffa
