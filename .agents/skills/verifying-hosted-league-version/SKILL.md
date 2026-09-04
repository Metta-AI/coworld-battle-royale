---
name: verifying-hosted-league-version
description: Prove which GameVersion the hosted battle-royale league is actually serving, using public unauthenticated endpoints only — read the replay header, cross-check the behavior with the ledger tooling, and sweep coworld_version transitions to date when a change really went live. Run after every publish and before announcing any rule change.
---

# Verify what the hosted league is actually running

## The two-step model (read this first)

Shipping a rule change to the board is **two separate events**:

1. **Merge.** A PR sets a knob in `config.br.json` and both manifest variants
   (`coworld_manifest_battleroyale.json`, `br-12` / `br-16`), bumps
   `GameVersion`, re-records fixtures, and lands on `main`. This arms the
   config **in the repo**.
2. **Publish.** Someone builds a `battleroyale` Coworld package from a `main`
   checkout and uploads it (`.agents/skills/deploying-battleroyale-coworld`).
   The league is pinned to a package version; only a new canonical package
   changes what the board runs.

Nothing links the two. The upload workflow
(`.github/workflows/upload-coworld-battleroyale.yml`) triggers on every green
`main` run but has never published: its `SOFTMAX_TOKEN` secret is empty, so
every real run fails at "Determine version" (the "success" rows in
`gh run list` are the stale-SHA skip path). Every live package so far was
published by hand by someone holding a Softmax user token. **A merged arm is
not a shipped arm**, and the gap can be days.

The incident this skill exists for: `dropWeaponOnDeath` merged armed as GV46
on 2026-08-29 06:46Z. The live package, `0.1.15`, was published at 01:48Z the
same day — five hours *before* that commit. Six days later the board was still
serving GV45 with no drops, and nobody had noticed, because the merge looked
like the finish line.

## Recipe: read the version the board is stamping

Public endpoints only. No token, no `softmax set-token`, nothing under
`/v2/episode-requests/`.

```bash
B=https://api.observatory.softmax-research.net
L=league_b88a269b-0de7-4723-b1c7-06dab50fe61d

# 1. newest completed round
curl -s "$B/v2/rounds?league_id=$L&limit=5" | python3 -c '
import json,sys
for r in json.load(sys.stdin)["entries"]:
    if r["status"]=="completed":
        print(r["id"], r["round_number"], r["completed_at"]); break'

# 2. its episodes (replay_url + coworld_version live here)
curl -s "$B/v2/rounds/<round_id>/episodes?limit=1000" | python3 -c '
import json,sys
for e in json.load(sys.stdin)["entries"]:
    print(e["coworld_version"], e["status"], e["replay_url"]); break'

# 3. one replay, header only
curl -s -o /tmp/one.replay "<replay_url>"
```

Round records carry **no version field** at all (`id`, `round_number`,
`status`, `created_at`, `completed_at`). Episode records carry
`coworld_version` — the *package* — but not the GameVersion. The only thing
that says which rules ran is the replay header, so the header is the
authority:

```python
import gzip, struct, sys
b = open(sys.argv[1], "rb").read()
if b[:2] == b"\x1f\x8b": b = gzip.decompress(b)     # hosted replays are gzip
assert b[:8] == b"COWLDCTF", b[:8]
off = 10                                             # magic + u16 format
n = struct.unpack_from("<H", b, off)[0]; off += 2 + n          # game name
n = struct.unpack_from("<H", b, off)[0]; off += 2
gv = b[off:off+n].decode(); off += n + 8                       # version, u64 seed
n = struct.unpack_from("<H", b, off)[0]; off += 2
cfg = b[off:off+n].decode()                                    # config JSON
print("GameVersion", gv); print(cfg)
```

Layout is `src/ctf/replays.nim` / the codec's `readHeader`: magic, `u16`
format, length-prefixed name, length-prefixed **GameVersion**, `u64` seed,
length-prefixed config JSON. Check the config JSON too: the serializer only
emits a dormant bool when it is `true`, so a live `dropWeaponOnDeath` arm
shows up as the key being *present*; absent means off.

Read the header of every replay in the round, not one — a round straddling a
publish has a mix. Run on 2026-09-04 against round 2066
(`round_98b94301-3a07-4df7-a847-e56057d084a1`, completed 10:40:13Z): 26/26
replays stamp `GameVersion "45"`, none carries `dropWeaponOnDeath`,
`coworld_version` is `0.1.15` on every episode. Repo `main` at that moment was
GV46. That is a mismatch.

## Cross-check the behavior, not just the stamp

The stamp says what the code *claims*; the ledger says what the game *did*.
Confirm both, because either alone misleads: a version string can be bumped
without the config change reaching the manifest, and a behavior change can
land without a bump. Run the ledger tooling over the same round.

```bash
# extractor + economy tool must be built from the GameVersion the replays
# stamp, otherwise the re-simulation mismatches. main is GV46; the board
# was GV45, so build from a detached worktree at the last GV45 commit:
git worktree add /tmp/wt45 <last-GV45-sha>
( cd /tmp/wt45 && nim c -d:release -o:/tmp/extract_events45 tools/extract_events.nim \
                && nim c -d:release -o:/tmp/loot_economy45  tools/loot_economy.nim )

mkdir -p /tmp/led
for f in /tmp/replays/*.replay; do
  j=$(basename "$f" .replay)
  /tmp/extract_events45 "$f" --out /tmp/led/$j.jsonl --results /tmp/led/$j.results.json
done
/tmp/loot_economy45 /tmp/led --label "round 2066 (newest completed, GV45)"
```

For a drop-on-death arm the signal is **gains by origin**: before the arm every
tier gain is `spawn`; after it, `corpse`-origin gains appear and the "drops per
episode" line is non-zero. Round 2066 read:

```
episodes: clean 26 / total 26 (excluded 0: none)
seat-episodes: 312
credited kills 261   with a tier gain in window 25 (0.096 per kill)
gains by origin: spawn 25
no corpse-origin gains in this arm: dropWeaponOnDeath was off
```

Zero corpse-origin, zero drop rows — behavior agrees with the GV45 stamp. Had
the header said 46 and the ledger still shown `spawn` only, the arm did not
reach the manifest the package was built from; that is a different bug and
worth saying precisely.

Trap: an extractor built from `main` (GV46) refuses GV45 replays with
`Replay game version "45" is not compatible` (the codec gates on an exact
version match). That refusal is itself evidence of the mismatch, but you get
no ledger from it — read the header first, then build the tool at the
matching commit.

## Dating a change: the coworld_version sweep

To find *when* something went live, walk the round listings, find the package
version transitions, and read headers at each boundary.

```bash
# rounds page newest-first; page with cursor=<next_cursor>, NOT offset
curl -s "$B/v2/rounds?league_id=$L&limit=100"
curl -s "$B/v2/rounds?league_id=$L&limit=100&cursor=2026-09-04T08:31:06.178787+00:00,3a436d81-7e38-4547-9622-1be846c5fb85"
```

`offset=` is silently ignored — you get the same first page forever (this
cost the better part of an hour). Use the `next_cursor` from the response
verbatim (`<created_at>,<uuid>`); `after=`/`before=`/`next_cursor=` are
accepted and ignored, and a malformed `cursor=` is a 422. Fetch
`/v2/rounds/<id>/episodes?limit=1000` per round concurrently (8 workers is
fine) and record each round's `coworld_version` set. A transition is the first
round whose episodes all carry the new version; download one replay from that
round and from the round before it and compare headers.

Worked example, swept 2026-09-04 over rounds 1067–2066:

| package | first round | completed | header |
|---|---|---|---|
| 0.1.12 | … through 1202 | | GV45 |
| 0.1.13 | 1203 | 2026-08-24T22:34Z | GV45 |
| 0.1.14 | 1822 | 2026-08-27T18:46Z | GV45 |
| 0.1.15 | 1884 | **2026-08-29T01:48Z** | GV45 |

The GV46 commit is `22c3610`, authored **2026-08-29T06:46Z** — after the
0.1.15 package went live. So no package built since the arm has ever been
published, and the arm date for the board is "not yet", not "Aug 30".

## On a mismatch

A header/config that lags `main` means **the publish has not happened**. It
does not mean the gameplay change is broken, and it is not fixed from the
repo:

- do not re-merge, revert, or re-arm anything;
- do not touch `config.br.json`, the manifest, or `GameVersion`;
- do not bump a version "to force it through" — the workflow cannot publish.

Report the exact evidence (round id, header GameVersion, `coworld_version`,
the ledger origin line, and the `main` SHA/GameVersion you compared against)
and escalate to whoever holds the publish token. If you *are* the publisher,
follow `deploying-battleroyale-coworld`, then come back here and re-run this
recipe on the first round fully on the new package.

## Notice coupling

A rule change is announced to submitters at the **round boundary where it goes
live** — the first round whose episodes all carry the new `coworld_version`
and whose headers stamp the new GameVersion. That is the publish, not the
merge. Announcing on merge announces a change that has not happened; for
drop-on-death it would have told every submitter their bots were fighting
over corpses for six days while nothing was dropping.

## Known gap

`tools/ci/check_gameversion.sh` is a **repo-side** guard: it fails a PR that
reuses a `GameVersion` number the base already spent for a different rule. It
protects the *claim* of a number, not the board, and it is not wired into any
workflow — wiring it needs the `workflows` permission on `.github/workflows/`,
which a session's token does not have (see AGENTS.md for the exact step to
add). Nothing in CI compares what `main` says to what the league is serving;
until something does, this recipe is the check.
