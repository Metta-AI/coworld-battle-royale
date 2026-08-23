---
name: visual-evidence-standards
description: Produce the screenshot/PNG evidence set a render or presentation change is judged on — genuine full frames at desktop and 640x360, zoom-matched before/after pairs, FFA presentation with CTF chrome off — using tools/capture_evidence.py instead of improvising a capture each time.
---

# Visual evidence standards for render/presentation changes

A presentation change is accepted or rejected on its screenshots, so a
technically-correct change with unreadable evidence gets bounced and re-done.
This is the standard the reviewer applies, and the mechanical way to hit it.

`.agents/skills/live-ffa-viewer-testing/SKILL.md` covers *how to get a board on
screen* (build, boot, bots, viewer quirks, transient FX, two-build comparison).
This skill covers *what to capture and how to prove it*. Read that one first if
you do not already have a live board or a replay loaded.

## The four rules evidence is judged by

1. **Two sizes, always: desktop and a genuine 640x360.** 640x360 is the small
   embed the board must survive; the desktop shot is where detail is judged.
2. **"Genuine" means rendered at that size.** The page must be rendered with the
   viewport set to 640x360 and the whole frame captured. A crop of a 1440px
   frame, a canvas dump relabeled "640x360", or a downscaled desktop shot are
   all rejected — they do not show what the embed actually does to layout, HUD
   scaling, and legibility, which is the entire question being asked.
3. **Before/after pairs must be zoom-matched.** Same viewport, same zoom, same
   camera/follow target, same seed and `mapSeed`, same tick where the surface is
   tick-dependent. An unmatched pair proves nothing: any difference could be the
   camera. Capture both with identical flags — see the pairing recipe below.
4. **Judge FFA on the FFA presentation, with CTF chrome off.** Battle-royale is
   `mode: "ffa"` in `config.br.json`, and the renderer gates CTF chrome on
   `withCtfPresentation = not config.isFfa()`. Screenshotting an FFA change on a
   CTF config shows chrome that will never ship with it. When a change is
   supposed to leave CTF alone, that is a separate parity shot (see below).

## Capture the standard set

```bash
# One Chrome with CDP open; --remote-allow-origins is required or the
# websocket handshake 403s.
google-chrome --remote-debugging-port=9333 --remote-allow-origins='*' &

# Live FFA board (see live-ffa-viewer-testing for the server + 12 bots).
python3 tools/capture_evidence.py http://127.0.0.1:9500/client/global \
  --out /tmp/evidence/after --label after
```

Writes `after-1440x900.png` and `after-640x360.png`, each rendered at its own
viewport via `Emulation.setDeviceMetricsOverride` and captured whole. The helper
polls until the board has actually painted and **fails instead of writing a
black frame** — a fixed sleep silently captures the lobby/countdown and exits 0,
which is how a session ends up submitting worthless PNGs.

Useful flags: `--viewports 1440x900,640x360,1024x576`, `--settle` (paint delay),
`--ready-timeout` (how long to wait for a painted board), `--tick N` (seek a
replay page before the shutter), `--port` (Chrome's CDP port).

Broadcast chrome (scorebug, timeline, HUD state) is more reliable off a recorded
replay than a live match:

```bash
bin/ctf-server --load-replay:tests/fixtures/ffa-scorebug.bitreplay --port:8792 &
python3 tools/capture_evidence.py http://127.0.0.1:8792/client/replay \
  --out /tmp/evidence/after --label after-chrome --tick 1200
```

## The before/after pair

Build the base commit in a worktree — copying the gitignored repo-root `nim.cfg`
in, or it cannot build — and serve both builds at once on different ports with
the SAME seed and `mapSeed`, so geometry is identical and only presentation
differs:

```bash
git worktree add /tmp/br-base HEAD~1 && cp nim.cfg /tmp/br-base/nim.cfg
(cd /tmp/br-base && nim c -d:release -o:bin/ctf-server src/ctf.nim)
# base on :9600, HEAD on :9500, same config
python3 tools/capture_evidence.py http://127.0.0.1:9600/client/global \
  --out /tmp/evidence/before --label before
```

Identical flags on both invocations is what makes the pair zoom-matched. For
pixel-exact claims ("walls/pits/windows untouched"), skip the browser: bake both
boards offline with `tools/render_ffa_board.nim <config>` and diff the PNGs; an
unchanged-pixel mask is stronger evidence than two eyeballed screenshots. Render
a CTF config through the same tool on both builds and compare md5 to prove CTF
parity.

## Put it in the PR in this order

**Investigation → change → evidence.**

1. **Investigation** — what you observed, where the cause lives (`file:line`),
   and what you ruled out. A reviewer who disagrees with the diagnosis stops
   here, before spending attention on the diff.
2. **Change** — what you changed and why that follows from the investigation.
   Name the surfaces touched, and say explicitly what you did NOT touch when the
   change sits next to something version- or contract-sensitive.
3. **Evidence** — the pairs, labeled with size and which build:
   `![after 640x360](path/to/after-640x360.png)`. State the seed/mapSeed and
   tick, and say what each pair is meant to prove. Include the CTF-parity shot
   or md5 when the change is FFA-only.

Order matters because it is the order a reviewer reads in: evidence first with
no diagnosis reads as "here are some pictures", and the reviewer has to
reconstruct the argument themselves.

## Before you attach anything

- Open each PNG and confirm its pixel dimensions match its filename.
- Confirm the board is actually rendered — not a black lobby frame, not a
  half-painted first frame.
- Confirm the pair differs ONLY in the thing you changed. If the camera, tick,
  or map moved, recapture; do not explain the mismatch in prose.
