---
name: change-safety-preflight
description: The never-touch list for this engine (labels.nim, GameVersion, hashed sim state, RNG draw order, /player streams, engine layer) with the label-manifest exception, plus the pre-merge self-check that mirrors the reviewer's spot-checks. Run the preflight before editing and the self-check before opening a PR.
---

# Change-safety preflight and pre-merge self-check

Most rejected work in this repo is not wrong logic — it is a presentation or
tooling change that reached into a contract surface. These surfaces share one
property: **breaking them is silent.** No compiler error, no failing test at the
moment of the edit; the cost lands later as replays that no longer decode,
policies that stop seeing an observation, or a fixture diff nobody can explain.

Run PART 1 before you edit. Run PART 2 before you open the PR.

## PART 1 — Preflight: the never-touch list

Unless the task **explicitly** asks for it, do not modify:

| Surface | Where | Why touching it silently breaks things |
|---|---|---|
| Label vocabulary | `src/ctf/labels.nim` (+ emit sites in `src/ctf/global.nim`) | Sprite labels are the observation API every policy reads. Renaming one does not fail a build — it makes bots blind to a thing that is still on screen. `labels.nim` also keeps **zero imports** by design; adding one couples the contract to the engine. |
| `GameVersion` | `src/ctf/sim_types.nim` | The number gates replay compatibility, and it is claimed across BRANCHES, not just against `main` — two current branches can pick the same number and the collision lands silently. Bumping it also invalidates every fixture. |
| Hashed sim state | `gameHash` inputs in `src/ctf/sim_state.nim`, sim fields in `sim_types.nim` | Determinism tests compare hashes tick-by-tick. Adding a field to a hashed structure, or reordering one, breaks every recorded replay. The flatty wire format is **positional**: field order is sacred. |
| RNG draw order | `sim.nim`, `arena.nim`, anywhere pulling from the sim RNG | Inserting or removing a draw shifts every subsequent draw, so unrelated maps and spawns change. If you need randomness, use a separate stream keyed off the seed (`seed xor const`) the way endzone archetypes do, so the main draw order never moves. |
| `/player` wire stream | `src/ctf/server.nim`, `spriteprotocol` | This is what policies consume. `/global` (spectator) and `/player` (policy) are different streams; presentation work belongs in the `/global` path only. A new sprite family leaking into `/player` is an unannounced contract change. |
| Engine/sim layer, for presentation work | `sim.nim`, `sim_state.nim`, `roster.nim`, `arena.nim` | If the task is visual, the fix is almost always in `global.nim` / `broadcast.nim` / `client/`. An "obvious" one-line sim tweak to make a visual bug go away changes gameplay for every policy. |
| Generated files | `src/ctf/map_pool.nim` (via `tools/gen_map_pool.nim`), `docs/pool-review.html`, `nim.cfg` | Hand-edits are overwritten by the generator and desync the artifact from its source. |

If the task genuinely requires one of these, say so in the PR body, name the
surface, and carry the matching consequence (re-record fixtures, scan branches
for the version claim, regenerate the artifact).

### The exceptions: intentional label changes

A deliberate change to `labels.nim` is legal, but it is a **four-surface change**
and all four land in the same PR:

1. `src/ctf/labels.nim` — the producer-side contract.
2. `tests/label_manifest.txt` — regenerate, never hand-edit:
   ```bash
   nim r -d:writeLabelManifest tests/test_label_contract.nim
   ```
   The test refuses to self-heal on a normal run precisely so an accidental
   rename cannot rubber-stamp itself; the resulting manifest diff IS the artifact
   to review, and a reviewer reads it as "this is what every policy now sees".
3. `docs/RULES.md` — the human-readable description of what bots observe.
4. `players/baseline/` — the reference consumer, so at least one policy is
   updated in lockstep and the rename is demonstrably survivable.

The standing exception is a **spectator-board-only label family**: chrome the
board draws that no policy reads (zone rings, scorebug ornaments). That may land
as a manifest regeneration plus sweep coverage in `test_label_contract.nim`,
without touching `labels.nim` or `players/baseline/` — precedent: the
spectator-board zone chrome labels. Say in the PR body that the family is
spectator-only and point at the sweep test that pins it.

Outside that case, a manifest diff with no `labels.nim` change means you changed
emit behavior by accident. Stop and find out why.

### Version claims, when a bump is in scope

```bash
tools/ci/check_gameversion.sh origin/main    # exits non-zero on a reused number
```
It compares the RULE on the changelog comment, not the digits, because a
colliding branch and the base both read the same number. Also scan open branches
for claims at or above `main`'s (recipe in `AGENTS.md`), take the next free
number, and record in the PR what you saw claimed. Then re-record fixtures.

## PART 2 — Pre-merge self-check

Run these five before opening the PR. Each mirrors a spot-check the reviewer
performs, and each is cheaper to run than to be told about.

**1. Determinism scan.** Look at your own diff, not the test output:
```bash
git diff --merge-base origin/main -- src/ctf/ | grep -nE 'rand|Rng|rng|gameHash|GameVersion'
git diff --merge-base origin/main --stat -- src/ctf/sim_types.nim src/ctf/sim.nim \
  src/ctf/sim_state.nim
```
Any hit needs a sentence in the PR body explaining why it is safe, or it needs
to come out. A clean sim-layer stat line is the strongest thing a presentation
PR can show.

**2. Label emit sites.**
```bash
git diff --merge-base origin/main -- src/ctf/labels.nim tests/label_manifest.txt
nim c -r -d:release tests/test_label_contract.nim
```
Green with no manifest diff = the vocabulary is untouched. If you added a
spectator-only visual, confirm it did not become a label: for a stream-level
proof (serve one replay on both builds, diff printable label-shaped strings off
`/global` and `/player`), see `live-ffa-viewer-testing`.

**3. Evidence quality.** Per `visual-evidence-standards`: genuine full frames at
desktop and 640x360, zoom-matched pairs, FFA judged on the FFA presentation with
CTF chrome off, PR body ordered investigation → change → evidence. Open each PNG
and confirm its dimensions match its filename.

**4. Scope matches ownership.** Compare `git diff --merge-base origin/main
--stat` against the file-ownership map in `AGENTS.md`: every file should belong
to the kind of work the task described. A board-render task touching
`broadcast.nim`, or a tooling task touching `src/ctf/`, is either scope creep or
the wrong fix — and in a parallel-session repo it is also a merge conflict
somebody else pays for.

**5. Tests, at the right cost.** From the repo ROOT (assets resolve via
`data/`), release builds only — debug is 10-50x slower through the per-pixel map
code. A new test module goes in a shard file, never in `tests/tests.nim` (which
imports the shards). Measured 2026-08-22 on a Devin snapshot (see `AGENTS.md` for
the shard route and the per-shard budget):
```bash
nim c -r -d:release tests/tests.nim    # 653 tests, ~4m45s
```
Plus `git fetch origin && git rev-list --left-right --count HEAD...origin/main` —
`behind` must be 0 before you build the evidence you are going to submit, or the
evidence describes a base that no longer exists.
