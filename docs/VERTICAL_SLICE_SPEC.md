# Battle Royale vertical slice — implementation spec (v0.1)

Authoritative design: [DESIGN.md](DESIGN.md). This file is the *slice* scope:
the smallest set of engine changes that makes a battle-royale match playable,
watchable, and decisive, so we can answer "is this fun?" from a replay.

Non-goals for the slice: renaming `src/ctf/**`, manifest/league upload,
golden-hash corpus, item roster expansion, minimap/zoom broadcast work.

## Mode gating (hard requirement)

Everything below hangs off a new config field `mode` (`"ctf"` default,
`"ffa"` = battle royale). With `mode == "ctf"` the sim must stay
byte-identical to the fork point: no new RNG draws, no gameHash shape change,
existing replay fixtures and tests untouched, no `GameVersion` bump.

`config.json` stays the CTF default. The slice adds `config.br.json` for the
battle-royale match, used by the demo script.

## A. FFA core

1. `mode: "ffa"`, `numPlayers` (2..16, validated; everything derives from it —
   no `array[16, ...]` state). Unknown-config-key warnings must still fire.
2. Single life: `lives = 1`, no respawn (`respawnTimer` never rearms), spawn
   `hitPoints = 20`. Fists deal 2 damage at contact range; low/mid/heavy gun
   tiers deal 2/3/5 damage with 150%/100%/60% cooldowns. Spray and grenade
   hits remain 4 damage (cross-trench grenade splash remains 1).
3. No hearts/flags in ffa: none spawned, no carry/capture/steal path reachable,
   no capture scoring. Endzone/pedestal geometry may remain as terrain.
4. Spawn pads: procedurally spaced ring for any N — equal distance to center,
   with every FFA player starting unarmed. A seed-derived integer offset rotates
   seat ownership of the unchanged pad set per episode; the mapping is
   bijective and CTF spawn positions are untouched. Fists are the fallback
   weapon, while rectangular-arena-anchored low/mid/heavy bands offer a broad
   weak pickup across the board, an intermediate current-strength pickup, and
   a scarce heavy weapon in the center risk/reward contest. The bands do not
   collapse when the safe zone reaches its final floor. Pads use maximum
   pairwise spacing, snapped to
   reachable floor, never a fixed array.
   Teams are irrelevant in ffa: per-player identity comes from `color`/skin
   (distinct hue per slot), and no code path may branch on `team` for
   damage, vision, scoring, or win.
5. End conditions: `<= 1` alive, or `maxTicks` cap. `gameover` must always name
   a winner — never `-1` while at least one player joined.
6. Placement total order (no draws): alive-at-cap > later death tick > more
   kills > more damage dealt > lower slot. Same-tick deaths: damage dealt, then
   slot. Needs a per-player `damageDealt` counter (in-sim, deterministic).

## B. Scoring

`reward` per player = `survivalSeconds * 1` (accrued live, one point per
24 ticks alive) `+ podium (1st +100, 2nd +40, 3rd +15) + 10 per kill (last
damager) + 4 per assist, split among the other damagers of the victim within
the last 240 ticks` (integer split, remainder dropped — deterministic).
Config knobs with these defaults: `survivalPointsPerSec`, `killPoints`,
`assistPoints`, `assistWindowTicks`, `podiumPoints`.
Environmental/ring deaths credit nobody.

## C. Ring — a fence, not a clock

Circular safe zone, centered on the map center, radius shrinking **linearly**
from "covers the whole arena" to a floor of 3% of arena area, reached at
`ringShrinkSec` (default 150 s) and then constant. Outside: 1 HP per
`ringDamageTicks` (default 48 = one HP per 2 s), no scaling. Integer math only
(compare squared distances; no floats anywhere in the sim).
Schedule is fully described in `player_config` so policies can plan.
Config: `ringEnabled`, `ringShrinkSec`, `ringFloorAreaPct`, `ringDamageTicks`.

The shipped baseline doctrine closes on the nearest living enemy when three or
fewer players remain, rather than disengaging while hurt; ring safety and
normal aim/fire gating still apply.

## D. Proximity chat

Reuse the existing shout system; in ffa, delivery is gated by the recipient
being inside the sender's vision radius **and** LOS (same test as
`visible.agents`), for both broadcast and dm. Out-of-range sends are legal and
return/record as blocked rather than erroring. Keep the 1 msg/s cooldown.
Raising `ShoutMaxChars` is optional for the slice — only do it if the chat
chip rendering stays legible; otherwise leave it and note it.

## E. Arena

`config.br.json` uses generated terrain (`mapPath: "gen"` or a pool entry) at
**~5x the CTF arena area** (CTF arena is 1235x659 ≈ 814k px², so target
≈ 4.0M px², e.g. ~2760x1470) with structures and trenches for cover. If the
generator's size bands can't reach that with symmetry validation passing,
report the largest that does and say so — do not silently ship a small map.

## F. Baseline bot + demo

Baseline doctrine (slice-level, in priority order): stay inside the ring →
disengage and heal when hurt (break LOS first) → take fights only with an
advantage (target is critical, or we outnumber) → otherwise roam/loot → hail
agents that enter vision. With three or fewer players alive, it instead closes
on the nearest enemy while retaining ring safety and normal aim/fire gates. It
only has to make matches end decisively and read well on the broadcast; it
does not have to be strong.

Demo: one command that runs a full headless N-bot match (server + N baselines),
prints the final ranking + scores, and writes a `.bitreplay` that plays in the
existing replay viewer.

## G. Verification

- `nim check src/ctf.nim` clean.
- Full existing test suite green (`nim c -r -d:release tests/tests.nim` from
  repo root) — proof that `mode: "ctf"` is untouched.
- New tests: N-derived spawn ring for N in {2, 5, 16}; single-life elimination
  and HP pool; ring damage only outside and only on schedule; placement total
  order incl. the same-tick-death tiebreak; scoring arithmetic (survival +
  podium + kill + assist split); chat delivered in range and blocked out of
  range; ffa match always ends with a named winner (both by wipe and by cap).
- Determinism: same seed twice → identical tick hashes, at N=4 and N=16.
- `docs/ENV_VARIATION.md` row for every new config field (repo rule).
