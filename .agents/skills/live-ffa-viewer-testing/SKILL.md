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
bin/ctf-server --config config.br.json --port 9500 &      # FFA config (mode: "ffa")
for i in $(seq 0 11); do players/baseline/baseline --port 9500 & done
```

Then open the spectator viewer at:

```
http://127.0.0.1:<port>/client/global
```

`/client/global` is the generic bitworld global client (websocket `/global`); the
`/replay*` routes serve a different, embedded replay client. Viewer path decisions
live in `src/ctf/server.nim`.

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
