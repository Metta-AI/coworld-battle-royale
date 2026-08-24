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

### Live CTF bots must use the CONFIGURED slot names

`config.json` (CTF) names its seats `player1`…`player16`, and
`validatePlayerSlot` (`src/ctf/roster.nim`) rejects a join whose `name` differs from the
configured slot name with `403 Player credentials do not match configured roster.` The
`Bot_<slot>` convention only works for configs (like `config.br.json`) that leave slot
names blank. For a CTF *regression* check it is usually faster to skip live bots entirely
and serve the committed fixture on two ports:
`bin/ctf-server --load-replay:tests/replays/ctf.bitreplay --port:9603`.

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

### Fixture re-simulation with `--mismatch-quit` is REALTIME

`readRuntimeConfig` has no speed/fast flag, so `--load-replay:<fixture> --mismatch-quit`
plays back at 1x: a 7200-tick fixture needs ~5 min, and the server does NOT exit at the end
(maxGames=infinite -> it goes back to "waiting for players"). Poll the log for
`wins|game over|draw` (success), or `mismatch|unhandled exception` (failure), then kill the
pid yourself. Budget ~8 min per fixture and report honestly which runs reached an ending
and which merely ran clean up to your timeout.

### Make the match last long enough to inspect

Default FFA configs finish fast. Copy the config and relax it, e.g.:

```json
{ "fastMode": false, "hitPoints": 200, "ffaGunDamage": 1,
  "ringShrinkSec": 900, "maxTicks": 40000 }
```

`fastMode: false` is what makes the server run in realtime so the browser view is watchable.

### Make bots actually FIRE the weapon you want to look at (spray cans etc.)

A default FFA match is mostly gun fire: spray cans are a fraction of the FFA loot
cluster (`ffaFamilyTargets` / `resetPlasmaArcs` in `sim.nim`), so a scan of a default
replay's events can show zero spray pickups. Flood the board with loot and keep every
bot alive so bursts keep coming:

```json
{ "mode": "ffa", "seed": 42, "mapSeed": 42, "fastMode": false,
  "hitPoints": 2000, "ffaGunDamage": 1, "ffaSprayDamage": 1, "ffaGrenadeDamage": 1,
  "ffaLootCount": 64, "ffaLootRespawnTicks": 48,
  "ringShrinkSec": 3000, "ringDamageTicks": 480, "maxTicks": 100000 }
```

With that config a handful of rapid `screenshot` calls in a row reliably lands on a
burst mid-flight, so the replay/`extract_events` route below is optional for
"is the FX shaped right" questions. Note that with low damage the match still thins
out over ~10 minutes — if `ALIVE` drops to 2-3, restart the server and re-attach bots
rather than hunting for fights.

### Unarmed FFA punch-fest config

`ffaLootCount: 0` keeps every FFA bot at `FfaWeaponUnarmed`, and the step loop auto-calls
`tryFist` for unarmed FFA players, so punches keep landing for the whole match instead of
only the opening scramble. Keep `hitPoints` low (e.g. 40) if you want punch kills quickly —
fist damage is 2/hit with a 24-tick cooldown, so 2000 hp means nobody ever dies.

### Another session on the same box can kill your server

`pkill -f ctf-server` / `pkill -f baseline.out` (common in other agents' test scripts)
will take down YOUR live match too — the symptom is the viewer going
`disconnected…`/`WAITING NEED MORE!` with **no error in the server log**. Defend by
running from uniquely named copies, e.g. `cp bin/ctf-server /tmp/myviewsrv;
cp players/baseline/baseline.out /tmp/mybot.out`, and start them with `setsid nohup`.
Also avoid `pkill -f` yourself: patterns like `ctf-server` match the shell running the
command and kill your own tool session.

## Testing bot POLICY/doctrine (not rendering): logs + two live boards

For behavior changes (e.g. `CTF_BOT_FFA_DOCTRINE` defaults) the proof is in the bot
process logs, and the viewer supplies the "and the bots actually behave" half:

```bash
# unset-env run must really be unset: use `env -u`, the shell may export it
env -u CTF_BOT_FFA_DOCTRINE CTF_BOT_TRACE=1 \
  COWORLD_PLAYER_WS_URL="ws://127.0.0.1:9500/player?name=Bot_0&slot=0&token=0xBADA55_0" \
  players/baseline/baseline.out > /tmp/legacy/bot_0.log 2>&1 &
```

- The startup line (`baseline slot=… ffaDoctrine=<name> …`, baseline.nim ~3934) names the
  resolved doctrine; `CTF_BOT_TRACE=1` adds per-frame lines carrying
  `phase=… objective=… action=… doctrine=…`.
- Doctrines are separable by trace phase: `LEGACY` (converge/`move_center`, `engage`),
  `PASSIVE`/`SHADE` (`hold_band`), `PERIMETER`/`LOOT` (hybrid), `RUSH`. Asserting
  `grep -c phase=PASSIVE == 0` etc. is what makes a default-flip test falsifiable.
- **Bot and server stdout are BLOCK-buffered when redirected to a file.** A log that
  only shows the startup lines for the first ~60s is not a hang — it is a partly-filled
  4KB buffer. Wait (or wrap with `stdbuf -oL`) before concluding traces are missing.
- Running two servers on two ports with the SAME config but different doctrine envs and
  screenshotting both at a similar match clock gives a clean visual contrast: legacy piles
  bots into the ring center, passive leaves the center empty with bots on the outer band.

## Viewer quirks (cost real debugging time)

- The 2D canvas only repaints while the Chrome window/tab has focus. After switching
  tabs, click into the page before judging a screenshot — a black or stale canvas is
  usually focus, not a server/websocket failure (check `Network`/console: the ws stays open).
- A **cold `/client/global` load is black for 30-60s** even with the tab focused: the
  server pushes the sprite atlas first (~7 MB of images, ~88% of all player traffic in a
  12-bot FFA), and nothing paints until it lands. `ss -tn | grep <port>` showing a
  multi-MB send queue on the browser socket is that atlas streaming, not a hang. So open
  the viewer, wait ~45s, click into the page, and only then judge the screenshot — a
  6-minute FFA can otherwise be half over before the first frame appears. If you need the
  early unarmed/fist phase on camera, load the viewer BEFORE the bots join (the FFA
  startup barrier holds the match until all seats connect).
- **Double-click the canvas** to re-enable auto-fit and frame the whole board; mouse
  wheel zooms, drag pans.
- The per-seat number in the top-left HUD roster is not a reliable readout for a report
  (rows are easy to misalign with the colour swatches when zooming a screenshot). Take
  kills/deaths from `results-*.json` or the events ledger instead.
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

### Board overlays are world-anchored, so high zoom exposes misplacement

Nameplates, HP bars, and tier/loadout marks are world-space sprites drawn at a fixed
tile offset above the cog. At 20×+ zoom that offset becomes hundreds of screen pixels,
which is exactly how a marker that is supposed to sit *on* a held gun becomes visibly
detached. So: judge "is this marker attached to the thing it annotates" at high zoom
(20×+) on an armed seat, not at fit/4×, where everything looks plausibly adjacent.

### Browser QA harnesses

`tools/qa_aspects.cjs` / `tools/qa_mock_embed.cjs` (with `tools/mock_observatory.html`)
sweep the embed at many aspect ratios. They need `tools/proxy_harness_binary.py` in front
of the game port — the plain proxy drops the binary board frames. `tools/qa_teamname.cjs`
is **CTF-only**: it drives `#name-red`/`#name-blue` and throws on an FFA replay page, so it
contributes no FFA coverage.

## Landing on a transient FX frame (spray/plasma bursts, muzzle flashes)

Combat FX last only a handful of ticks, so hunting for one by eye in the viewer wastes
a lot of time. Drive it from the replay data instead:

```bash
nim c -d:release -o:/tmp/xevents tools/extract_events.nim
/tmp/xevents /tmp/match.bitreplay --out /tmp/ev.jsonl --frames /tmp/frames.bin
```

`--frames` is a fixed-size per-tick record (header `<HHHH` slots/mapW/mapH/teams at
offset 8, then per tick `<IBB` tick/phase/… + `slots` × `<hhBBBBBB`
x/y/aim/hp/lives/flags/…). Flags **bit 64 = spray cone active**, **bit 1 = alive**, so a
~30-line python scan prints every burst as `(tick, seat, x, y, aim)`.

Two gotchas when translating those ticks into the viewer:

- **The viewer's tick counter is game-relative, the frame dump is sim-absolute.** The
  offset is the first tick whose `phase` byte is 1 (the lobby/countdown length; it was
  510 in one CTF recording and 243 in an FFA one — do not assume a constant). Cross-check
  with the HUD clock: `displayed tick / 24 == elapsed seconds`.
- `http://127.0.0.1:<port>/client/replay?t=<simTick>` seeks **and pauses** there
  (it uses the same `s:<tick>` command as the scrubber), and it takes the SIM tick, so
  no conversion is needed for the URL. Do not press `space` afterwards — the page is
  already paused and space resumes playback (and while playing you drift ~25 ticks per
  reload attempt). If you do need fine positioning, click the timeline strip
  (`x ≈ 10 + displayedTick / totalTicks * 1004` at 1024px wide) or the `◂|` back-one-tick
  button, and turn OFF `▸▸` auto-skip-lulls, which silently plays at ~2x.
- The FX belongs to the *sprayer*, who is usually off-screen: use the `◂`/`▸` follow
  chips until the label reads the seat from the frame dump (`FOLLOW <name> S<seat>`),
  then `zoom` into the nozzle region for the close-up.
- **Faster than cycling follow chips: click the MINIMAP.** A single click on the minimap
  switches the camera to `FREE VIEW` and centres it on that map point, so an event's map
  coordinates (from `extract_events.nim`) translate directly:
  `click_x = minimapLeft + x/MapWidth * minimapW`, same for y (worked pixel offsets for
  the 640x360 and full-page layouts are under "identical camera for A/B panels" below).
  Two or three clicks of refinement land the contact near the view centre. This never
  touches a cog, so it cannot trip the POV/fog mode. Re-navigating to `?t=<tick>` resets
  the camera, so re-click the same minimap point for each tick to keep an identical crop
  across a fade sequence.
- Resizing the window or clicking chrome can resume playback (and Chrome may re-maximize
  the window): re-load `?t=<tick>` after any resize, and verify the frame counter is the
  same on both builds before treating two screenshots as the same frame.

### Live matches make short FX hard to catch; prefer a replay

On a huge/standard generated map the viewer's wheel zoom caps out with cogs ~10-30px, and a
mark that lives ~8 ticks (1/3 s) is very easy to miss between screenshots; bots also bunch
into a stack that hides ground marks. For contact/impact FX, record a match once
(`--save-replay:`) and do all judging through `--load-replay` + `?t=<tick>`, which is the
same `buildSpriteProtocolUpdates` spectator path as live play.

### Impact/contact FX: expect the victim sprite to occlude it sometimes

A mark drawn at a victim's body centre (even offset back toward the attacker) is only
visible when the offset direction points away from the victim's chassis art; on other
angles the cog sprite covers most of it and only a sliver shows a tick or two later, when
the later stages have expanded. Judge such FX on several contacts with different attack
directions before calling it invisible.

### Prove transient FX presence/absence numerically, not by eyeballing

Screenshot the same camera at consecutive `?t=` ticks and count FX-coloured pixels inside a
crop that excludes HUD chrome (HUD has its own amber/orange, which will otherwise swamp a
whole-frame scan and make every frame look identical). Example that produced clean evidence
for a 4-tick amber impact burst: crop below the victim body, accept
`r>140 and r-b>55 and r-g>25 and g>60` -> 0/95/116/104/7/0/0 across ages -1..5, i.e.
present ages 0..3, gone at age 4. Do the same for spray pink
(`r>165 and r-g>55 and b>95`) sampled row by row to compare nozzle width between builds
(near-nozzle rows differ, far rows must match for a nozzle-only change).

### Pixel-exact FX evidence offline (`renderBoardFrame`)

For a deterministic, zoom-free ground truth of what the spectator board draws at an exact
tick, write a throwaway tool (delete it afterwards — do not commit) that steps a replay
and composites the global packet:

```nim
import std/[os, strformat, strutils], pixie, ../src/ctf/[sim, global], toolutil
# ... openReplay(path); while sim.tickCount < t: replay.stepReplay(sim)
# let bs = boardRenderScaleFor(MapWidth, MapHeight)   # 2 on normal maps, 1 on huge ones
# var canvas = sim.renderBoardFrame()                 # canvas is MapW*bs x MapH*bs
# crop around (mapX*bs, mapY*bs) and upscale for review
```

Two traps: `boardRenderScaleFor` lives in `ctf/global`, not in the `ctf/sim` re-export
(import both, or you get `undeclared identifier`), and **sim coordinates must be multiplied
by that board scale** — cropping with unscaled coords (or passing `scale = 1` to
`renderBoardFrame`) yields an all-black tile and looks exactly like "the FX never rendered".
## Proving no new sprite family/label reached the streams

Serve the SAME replay file on both builds (`--load-replay`, two ports), connect a python
`websockets` client to `/global` and `/player?name=Obs&slot=0&token=0xBADA55_0` on each,
and collect printable ASCII runs (`re.compile(rb"[ -~]{3,}")`) from the binary frames.
Raw runs contain a lot of binary noise, so filter to label-shaped strings
(`^[a-z][a-z ]{4,30}$`) before diffing — that filter gave stable sets (359 `/global`,
275 `/player`) that diff cleanly between builds. FX labels only appear once the FX
actually fires, which is why replaying a burst-rich recording (rather than an idle
server) is what makes the check meaningful.

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

### Exact-viewport (e.g. 640x360) full-frame captures — use CDP, not window resizing

Resizing the Chrome window can never give an exact page viewport (chrome/decoration eats
pixels), and cropping is routinely rejected as evidence. Drive your own Chrome over CDP
instead:

```bash
google-chrome --remote-debugging-port=9333 --remote-allow-origins='*' &   # both flags:
# without --remote-allow-origins the websocket handshake fails with HTTP 403
```

Then `Emulation.setDeviceMetricsOverride {width:640,height:360,deviceScaleFactor:1}` +
`Page.captureScreenshot {captureBeyondViewport:false}` yields a PNG that is exactly
640x360 and contains the WHOLE page (HUD row, board, minimap, replay bar). Verify with
`Runtime.evaluate "[innerWidth,innerHeight].join('x')"` and with PIL `Image.open(p).size`,
and quote both in the report. `Emulation.clearDeviceMetricsOverride` returns to desktop
width (a maximized 1600px window gives a 1600x1017 page).

### Identical framing on two builds via keystrokes

Mouse zoom/pan is not reproducible; keyboard is. Load the same
`?t=<simTick>` URL on both ports, click once into the page (canvas focus), then drive
the camera with the SAME keystroke sequence on each build: `]` / `[` step the follow
camera, `z` / `x` zoom one step. The zoom readout (`7.3×`, `24.1×`) and the
`FOLLOW <name> S<seat>` chip confirm the two tabs match before you diff. Crops taken
this way diff cleanly; everything that differs is then a real build difference.

Screenshots taken through the computer tool are captured at the display's native
resolution while the tool's coordinates are 1024-wide, so multiply screen coordinates by
`nativeWidth/1024` (1.5625 on a 1600px display) before cropping with Pillow. **numpy is
not installed** — plain Pillow `load()` loops are fast enough for these crops.

### Deterministic, build-to-build identical camera for A/B panels

Both viewer camera controls are also reachable as viewport-space clicks, and — verified —
they do NOT resume playback after a `?t=<simTick>` seek (the frame counter stays put):

- At a 640x360 viewport: zoom `-`/`+` at (450,127)/(530,127) (1.9x -> 6.3x in 4 clicks),
  follow `◀`/`▶` at (452,148)/(552,148), minimap area ~x448..557, y50..97.
  At a 1600x1017 page: follow `▶` (1526,316), `◀` (1290,316), zoom `+` (1474,262).
- **Prefer a minimap click over the follow chip** when you know the event's map
  coordinates: `page_x = 440 + mapx/mapW*132`, `page_y = 39 + mapy/mapH*68` at 640x360
  puts the free camera on that spot ("FREE VIEW" chip) — identical on both builds, whereas
  follow-chip click counts do not always land on the seat you expect.
- Get event coordinates from `tools/extract_events.nim` (`CTFFRM01` frame dump: seats' x/y,
  aim, flags; flag bit 64 = spray cone active, bit 1 = alive).

## Devin Secrets Needed

None — the server and viewer run locally with no auth.
