---
name: live-ffa-viewer-testing
description: Boot a live CTF/FFA (battle-royale) server with bots and inspect the board visually in the browser viewer — for testing rendering/presentation changes (map art, palettes, HUD) end-to-end instead of only via unit tests.
---

# Live FFA/CTF board testing in the browser viewer

## Build

From the repo ROOT (assets and `nim.cfg` resolve relative to it):

```bash
nimby --global sync nimby.lock              # only if nim.cfg / deps are missing
nim c -d:release -o:bin/ctf-server src/ctf.nim
nim c -d:release players/baseline/baseline.nim
```

## Boot a live match with players connected

`tools/run_ffa_demo.sh 12 42` is headless (replay only) — for a *live* board run the
server binary and attach baseline bots yourself:

```bash
# Options use Nim colon syntax: --config-path:<path> --port:<port>
# (also: --save-replay:<path> to record, --load-replay:<path> to replay).
# `bin/ctf-server --help` prints the authoritative option list. Parsing lives in
# readRuntimeConfig (bitworld/runtime, runtime.nim:291-397): it accepts CLI flags
# AND COGAME_* env vars; CLI takes precedence when both are present.
bin/ctf-server --config-path:config.br.json --port:9500 &   # FFA config (mode: "ffa")
# Baseline bots read their connection from COWORLD_PLAYER_WS_URL; the binary is baseline.out.
# Tokens must match the config's roster tokens (config.json / config.br.json use 0xBADA55_<slot>).
for i in $(seq 0 11); do
  COWORLD_PLAYER_WS_URL="ws://127.0.0.1:9500/player?name=Bot_$i&slot=$i&token=0xBADA55_$i" \
    players/baseline/baseline.out &
done
```

The repo's scripted convention is the env-var form instead (see
`tools/run_ffa_demo.sh:105-111`, `README.md`):

```bash
COGAME_HOST=127.0.0.1 COGAME_PORT=9500 \
COGAME_CONFIG_URI="file://$PWD/config.br.json" \
COGAME_SAVE_REPLAY_URI="file:///tmp/match.bitreplay" \
bin/ctf-server &
```

Note `--config-path` has no env twin: the env equivalent is `COGAME_CONFIG_URI`
with a `file://` URI.

Then open the spectator viewer at:

```
http://127.0.0.1:<port>/client/global
```

`/client/global` is the generic bitworld global client (websocket `/global`); the
`/replay*` routes serve a different, embedded replay client. Viewer path decisions
live in `src/ctf/server.nim`.

### Testing broadcast-chrome features (`s.ring`, HUD state): use a recorded replay

The rich broadcast UI (`client/replay_broadcast.html` + `client/broadcast_core.js`)
only receives its JSON state frames (`onFrame` — ring, roster, events) when the
server is started with `--load-replay:<file>`; on a live server, `/client/replay`
can stay stuck on the locker-room curtain (binary sprite packets arrive but no
chrome frame dismisses it). Workflow that works:

```bash
bin/ctf-server --config-path:/tmp/my.json --save-replay:/tmp/match.bitreplay --port:9500 &
# ...attach bots, let the match finish (fastMode:true finishes quickly)...
bin/ctf-server --load-replay:/tmp/match.bitreplay --port:9501 &
# open http://127.0.0.1:9501/client/replay — full chrome: timeline, seek, speed, minimap
```

The replay viewer's timeline makes shrink/floor comparisons easy (seek to two ticks,
compare screenshots). To inspect numeric state (e.g. `ring.radius`, roster hp) from
the devtools console, the parsed state is closure-scoped — hook `JSON.parse` to
capture frames containing the field you care about.

### Make the match last long enough to inspect

Default FFA configs finish fast. Copy the config and relax it, e.g.:

```json
{ "fastMode": false, "hitPoints": 200, "ffaGunDamage": 1,
  "ringShrinkSec": 900, "maxTicks": 40000 }
```

`fastMode: false` is what makes the server run in realtime so the browser view is watchable.

## Viewer quirks (cost real debugging time)

- The 2D canvas only repaints while the Chrome window/tab has focus. After switching
  tabs, click into the page before judging a screenshot — a black or stale canvas is
  usually focus, not a server/websocket failure (check `Network`/console: the ws stays open).
- **Double-click the canvas** to re-enable auto-fit and frame the whole board; mouse
  wheel zooms, drag pans.
- Clicking on/near a player can switch the view into that player's fog-of-war
  perspective (board goes dark with a visibility cone). Reload the page to get the
  full-board spectator view back.

### POV lens vs the follow camera (they are different things)

The POV lens is NOT the `FREE VIEW` / `FOLLOW` camera chip. Clicking a chrome control
wired to `togglePov(slot)` (CTF `.squad-pip`, FFA lamps/leader plates, league KDA rows)
shows `#povBadge` (`👁 POV: <name> — click to clear`) plus the EYES first-person PiP and
a fogged board; the camera chip may still read `FREE VIEW`. Judge POV by `#povBadge` /
the PiP / `pov` in the state frame, or you will report a working path as broken.
`togglePov` also *clears* on a second click of the same seat, so clicking two seats in a
row is fine but clicking one seat twice looks like nothing happened.

Transport and POV commands leave the page as **binary** ASCII frames via
`core.sendCommand`, so a `WebSocket.prototype.send` hook that only logs string args sees
nothing. Log every arg and decode `ArrayBuffer`/`Blob` to see `v:8`, `s:<tick>`, etc.

### Browser QA harnesses

`tools/qa_aspects.cjs` / `tools/qa_mock_embed.cjs` (with `tools/mock_observatory.html`)
sweep the embed at many aspect ratios. They need `tools/proxy_harness_binary.py` in front
of the game port — the plain proxy drops the binary board frames. `tools/qa_teamname.cjs`
is **CTF-only**: it drives `#name-red`/`#name-blue` and throws on an FFA replay page, so it
contributes no FFA coverage.

## Comparing against the pre-change build (recommended for art changes)

Create a worktree at the base commit and **copy the repo-root `nim.cfg` into it**
(it is gitignored, so a fresh worktree cannot build without it):

```bash
git worktree add /tmp/br-base HEAD~1 && cp nim.cfg /tmp/br-base/nim.cfg
(cd /tmp/br-base && nim c -d:release -o:bin/ctf-server src/ctf.nim)
```

Run both builds on different ports with the SAME `seed`/`mapSeed` so geometry is
identical and only presentation differs; open both in two tabs.

For pixel-exact evidence, bake boards offline with `tools/render_ffa_board.nim <config>`
(renders with the same `withCtfPresentation = not config.isFfa()` gate as the server) and
diff the PNGs; an "unchanged pixels" mask is a good way to prove walls/pits/windows
were untouched. Rendering a CTF config through the same tool on both builds and comparing
md5 proves CTF parity.

## Devin Secrets Needed

None — the server and viewer run locally with no auth.
