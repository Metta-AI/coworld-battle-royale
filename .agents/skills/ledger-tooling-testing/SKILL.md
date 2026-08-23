---
name: ledger-tooling-testing
description: CLI end-to-end verification of the episode-ledger tools (tools/ledger.nim, tools/highlight_cuts.nim, tools/report_card.nim) — how to get ledgers, how to build an independent oracle to check derived beats/stats, and which edge cases actually distinguish right from wrong.
---

# Testing the ledger tools (highlight_cuts / report_card)

These are **tools-only** changes: no server, no client, no viewer. Do NOT reach
for `live-ffa-viewer-testing` — there is no UI to inspect. Verify from the shell.

## Build

Always from the repo ROOT (the renderer resolves art via `data/ascii.png`):

```bash
nimby --global sync nimby.lock          # only if a build complains; nim.cfg is gitignored
nim c -d:release -o:/tmp/highlight_cuts tools/highlight_cuts.nim
nim c -d:release -o:/tmp/report_card    tools/report_card.nim
nim c -d:release -o:/tmp/extract_events tools/extract_events.nim
```

`-d:release` matters: debug builds of the per-pixel map code (and therefore
`render_replay_movie`) are 10-50x slower.

## Getting ledgers

A "ledger" is the JSON-lines stream from `tools/extract_events.nim` (same
serializer as the live server's `COGAME_EVENTS_URI`, `src/ctf/events.nim`).

```bash
/tmp/extract_events tests/fixtures/ffa-scorebug.bitreplay --out /tmp/led.jsonl
```

Row shape: event rows carry `kind`; the trailing summary row carries
`"type":"summary"` (**not** `kind`) plus `slot_address` / `slot_team` /
`slot_shots_fired` / `slot_shots_hit`. Note `tools/run_ffa_demo.sh`'s inline
python filters on `kind == "summary"`, which is a different key — do not use it
as the schema reference.

For a fresh episode (writes replay + events + metrics; keep artifacts out of the
repo with `DEMO_DIR`, and reuse a prebuilt validator to save a compile):

```bash
DEMO_DIR=/tmp/demo CTF_EXTRACT_EVENTS_BIN=/tmp/extract_events tools/run_ffa_demo.sh 12 <seed>
```

Useful fixture set: `tests/fixtures/ffa-scorebug.bitreplay` (12 kill rows vs 11
death rows — the canonical unmatched-kill case, and a **ring-decided** ending),
`draw-nokill.bitreplay`, `wipe-lives1.bitreplay`.

## Build an independent oracle — do not eyeball the output

The whole value of these tools is the derivation, so re-derive it in ~60 lines of
python from the spec (not from the Nim source) and diff. The rules:

- a `kill` row counts only if a `death` row exists with the **same tick** and
  `death.source == kill.target` (death rows: `source` = victim, `target` = killer);
- a seat's **terminal** elimination is its last `death` with no later `respawn`;
- `first_blood` = earliest `death` row;
- `final_2` = the elimination after which exactly 2 seats remain
  (`seats - index - 1 == 2`, 0-based over tick-sorted eliminations);
- `winning_kill` = the **LAST elimination**, not the last matched kill row. In a
  ring-decided episode the last matched kill lands long before the end, so a
  regression here shows up as an anchor hundreds/thousands of ticks too early;
- lead changes need a **strictly greater** tally — a tie must not hand over.

## Cases that actually distinguish working from broken

- **Ring-decided endings** must report "no winning kill" / "no killer credited"
  and must not fabricate a killer seat. Check both a ring ending and a
  kill ending in the same run.
- **Ties in the kill tally.** Real ledgers do contain them, but they are easy to
  miss; a 3-seat hand-written ledger (`kill`+`death` pairs at t100/t200/t300/t400
  producing 1-1 then 2-2) proves tie non-handover deterministically.
- **Unmatched kill rows** must be excluded from every count and shown separately.
  Pick the seat whose ONLY kill row is unmatched — its card must read `Kills 0`.
- **Tied elimination ticks** (two seats dying on the same tick, incl. mutual
  kills) leave placement/`final_2` ordering ambiguous. `eliminations()` sorts a
  `Table`'s iteration order, so the tie order is arbitrary though stable. Run the
  tool 5x and `md5sum` the output to confirm determinism rather than assuming a
  seat-ascending tie-break.
- **Cap endings** (2+ survivors at `maxTicks`) make `final_2` and `winning_kill`
  the same event — worth including one.
- **Bad input**: empty file, truncated JSON, missing summary row, an event row
  after the summary, nonexistent path, `--seat` out of range, `--pre/--post` 0 /
  huge / negative / integer-overflow, and the **binary** `--frames` output fed in
  as a ledger. Expect exit 1 with `path:line` context and no raw Nim traceback.
  Two regressions worth re-checking, both found this way and since fixed: an
  empty ledger used to exit 0 from `highlight_cuts` (an empty file is a truncated
  extraction, not an episode with no beats), and a NEGATIVE `--seat` used to be
  treated as "every seat" because `-1` is the internal sentinel. A silently
  ignored flag is the failure mode those two share, so test the flags you expect
  to be REJECTED, not only the ones you expect to work.

## Rendering a cut (optional visual evidence)

`highlight_cuts --recipe <path>` emits a runnable bash script. It is runnable
verbatim **from the repo root**: `render_replay_movie` does its own
`createDir`, and it numbers frames sequentially from `frame-00000.png` (a frame
counter, not the tick), so the recipe's `ffmpeg -i frame-%05d.png` needs no
`-start_number`. It writes into `./clips/`, which is untracked repo output —
delete it and check `git status --porcelain` is empty afterwards. Shorten a clip
with `--pre 12 --post 12`; the renderer re-simulates from tick 0 to reach the cut,
so late anchors cost real time.

## Devin Secrets Needed

None.
