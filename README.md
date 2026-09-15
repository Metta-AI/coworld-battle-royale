# Coworld Battle Royale — AI Free-for-All Shooter

Coworld Battle Royale is a free-for-all shooter for the Coworld platform. The
shipped config (`config.br.json`, `mode: "ffa"`) seats **12 players**
(`numPlayers: 12`); the Coworld manifest
(`coworld_manifest_battleroyale.json`) ships the `br-12` and `br-16` variants.
Every seat is its own team and receives its own identity color, and each player
has a **single life**. Players spawn unarmed on an evenly spaced ring and fight
with their fists until they pick up a weapon — gun pickups form a permanent
upgrade ladder of tiers. A **shrinking ring** (`ringShrinkSec` 150 s, closing
to a floor of 3% of the arena) forces the survivors together, and an armed
victim drops their gun as a one-use pickup at the death site
(`dropWeaponOnDeath`, armed as of GV46). **Placements** decide the results.
Vision is fog-of-war: you observe the full map, but enemies only appear inside
your forward vision cone (walls block it) or your small omnidirectional bubble.

It is a fork of [Crewrift](https://github.com/Metta-AI/coworld-crewrift). It keeps
Crewrift's continuous 2D movement, line-of-sight, Sprite v1 protocol, websocket
server, and replay infrastructure, and replaces the social-deduction game layer
(roles, tasks, voting) with teams, guns, and fog-of-war vision.

The **full, authoritative ruleset lives in [`docs/RULES.md`](docs/RULES.md)**. The
summary below is just an orientation.

If docs, commands, runtime behavior, logs, or replays disagree while you are
building or submitting a policy, preserve the evidence and file a GitHub issue
instead of silently working around it. Include the command, league/Coworld ids,
logs or replay links, and the smallest repro.

## Battle Royale at a glance

- **Free-for-all, single life.** Every seat is its own team with its own
  identity color. There is no respawn — death ends your episode, and
  **placements** decide the result.
- **Unarmed start.** Everyone spawns on an evenly spaced ring with no gun; the
  fallback attack is a **fist** — 70 px reach, 2 damage, twice the normal fire
  cooldown, hitting the nearest living player inside the ±67.5° aim cone. A
  punch always connects inside reach, cone, and line of sight, and is only
  available while you hold no gun or spray can.
- **Weapon tiers are a permanent upgrade ladder.** Touching a higher-tier
  pickup raises your tier for the rest of the episode: **low** (2 damage,
  700 px reach), **mid** (3 damage, 1050 px), **heavy** (5 damage, 1050 px at
  a faster cooldown). With the shipped config, no weapon has ammo, durability,
  or a magazine (`finiteAmmo` is a dormant knob) — the only way to lose a gun
  is to die.
- **Drop on death (GV46).** With `dropWeaponOnDeath` on — it is armed in the
  shipped configs — a non-unarmed victim leaves their gun as a one-use pickup
  at the death site, consumable only by a strictly lower-tier player. Grenades
  and spray cans drop nothing.
- **The ring shrinks.** The safe zone closes over the match
  (`ringShrinkSec` 150 s in `config.br.json`) down to a final floor of 3% of
  the arena (`ringFloorAreaPct`).
- **Vision is fog-of-war**, as in the legacy mode: the map is always visible,
  but enemies only appear inside your forward vision cone or your small
  omnidirectional bubble.

See [`docs/RULES.md`](docs/RULES.md) for exact mechanics and tuning defaults.

## Legacy CTF mode — rules at a glance

The bullets below describe the two-team capture-the-heart mode that remains in
the engine and tests (`config.json`, `mode: "ctf"`); it is not the Coworld this
repo publishes. "Flag" below is the heart: the mode reskinned flags as hearts.

- **8 vs 8.** Red spawns on the **left** edge, Blue on the **right**. Each team's
  flag sits on a pedestal inside its spawn pocket.
- **Move** with the d-pad — locomotion only; it never changes where you aim.
- **Aim** with a continuous per-player **aim angle** (256 brads per turn, 0 =
  east, counter-clockwise): hold **B** to rotate counter-clockwise, **Select**
  to rotate clockwise (~7°/tick). Spawns aim toward the enemy side. A short aim
  indicator line shows every visible player's aim.
- **Vision is fog-of-war:** the map itself is always visible, but enemies (and an
  enemy carrying a flag) only appear inside your **forward vision cone** (±60°
  around your **aim**, reaching 1.5× the gun range — 1575px — with stone walls
  blocking it) or your **~90px omnidirectional bubble**. Six wall stubs are **glass windows** (the
  second-from-top, middle, and second-from-bottom stubs of each half's outer
  stub column): they block
  movement and bullets like any wall but are **transparent to vision**. Your aim carries your vision — you see where you
  point, not where you walk. Both pedestals, your own flag's state, and your
  own position (a distinct self marker) are always visible — teammates are
  NOT (no team radio). Shots are invisible to players and firing is
  silent: each shot's only trace is a brief impact ring randomly offset
  from where it landed — heard, not pinpointed.
- **Shoot** with **A**: an instant, line-of-sight hitscan along your aim angle
  (locked at the trigger pull, released after a short windup), with a fixed
  **1050px range** on every map and lightly **fuzzed aim** — a fully visible
  target at max range is hit 80% of the time, near-certainly when closer.
  Each hit removes one of **3 hit points** — at zero you die, and HP
  resets on respawn. **Friendly fire is on.**
- **Spray cans** spawn high in the side back columns and respawn 30 seconds
  after pickup. Carrying one disables the gun (and a carrier visibly holds the
  can); press **A** to spray a forward paint cone — 4 squares of reach, 2
  squares wide at the tip — that stays on for 5 ticks and takes 20 ticks to
  repressurize. A touch deals 3 damage (lethal to a bare cog; a shield carrier
  survives one), hits teammates too, credits kills to the attacker, and the can
  is lost on death.
- **Lives & respawn:** each player has a few lives and respawns at their home edge
  after a delay until their lives run out.
- **The flags:** touch the **enemy** pedestal flag to steal it; you carry it
  slower but can still shoot. If the carrier dies, the flag returns instantly to
  its own pedestal.
- **Win** by carrying the enemy flag into **your own home capture zone**, or by
  **wiping** the enemy team. Scoring: winners **+1**, losers **-1**; a
  time-limit draw is **-1 for both sides**, a mutual-wipe draw is 0.

See [`docs/RULES.md`](docs/RULES.md) for exact mechanics and tuning defaults.

## Campaign mode (territory leagues)

The Coworld platform also runs **campaign leagues** (e.g. "CTF Campaign",
"Paintbot Campaign" — those are platform league names): territory wars on a cell grid where an LLM strategist issues
invasion orders for your player each round, guided by a standing **strategy
prompt** you control. Each contested cell is settled by the policies playing a
normal match on the cell's variant (which sets the battle mode — 1v1 duel,
2v2, …), so your policy needs no campaign-specific changes — the campaign
lever you control is the strategy prompt.

The campaign player API is **not in this repo** — it ships with the `coworld`
package in the [Metta-AI/metta](https://github.com/Metta-AI/metta) repo
(`packages/coworld`), as the `coworld campaign` subcommands: `board`,
`history`, `prompt`, `set-prompt`, `full-prompt`, and `conversation`. If your
installed `coworld` release doesn't have the `campaign` subcommand yet (it
landed after v0.1.34), run it from a metta checkout:

```bash
uv run coworld campaign board "CTF Campaign"
uv run coworld campaign set-prompt "CTF Campaign" "Hold the corners; strike only weak neighbors."
```

The full recipes (reading your battle history, inspecting the exact strategist
payload, JSON output for tuning loops) are in the Coworld Cookbook's **"Play A
Campaign League"** section:
[`packages/coworld/COOKBOOK.md`](https://github.com/Metta-AI/metta/blob/main/packages/coworld/COOKBOOK.md).

## Run the game locally (without Docker)

Install Nim and sync the lock file. We recommend
[Nimby](https://github.com/treeform/nimby).

```sh
nimby use 2.2.10
nimby sync -g nimby.lock
```

Build and run the game with the repo config:

```sh
COGAME_HOST=0.0.0.0 \
COGAME_PORT=2000 \
COGAME_CONFIG_URI=file://$PWD/config.json \
nim r src/ctf.nim
```

Build the baseline bot:

```sh
nim c players/baseline/baseline.nim
```

Run 16 bots in parallel (slots 0–15, eight per team, with the matching tokens
from `config.json`):

```sh
for i in $(seq 0 15); do
  token="0xBADA55_$i"
  url="ws://localhost:2000/player?slot=$i&token=$token"
  COWORLD_PLAYER_WS_URL="$url" ./players/baseline/baseline.out &
done
wait
```

Watch the match with the global viewer at <http://localhost:2000/client/global>.

To play one slot yourself, open a configured player URL in the browser, e.g.
`http://localhost:2000/client/player?slot=0&token=0xBADA55_0`.

## Run the game with Docker

> **Note:** the public battle-royale images are not published yet. Build the image locally
> first (`docker build -t coworld-battle-royale:local .`) and substitute it below, or wait
> for the published image. The flow mirrors Crewrift's.

```sh
docker network create ctf-local || true

docker run --rm -d \
  --name ctf-server \
  --network ctf-local \
  -p 2000:2000 \
  -v "$PWD/config.json:/workspace/ctf/config.json:ro" \
  -e COGAME_HOST=0.0.0.0 \
  -e COGAME_PORT=2000 \
  -e COGAME_CONFIG_URI=file:///workspace/ctf/config.json \
  coworld-battle-royale:local
```

## Policy starting points

Policies speak the shared Bitworld Sprite v1 protocol:
<https://github.com/Metta-AI/bitworld/blob/master/docs/sprite_v1.md>

The runner starts every policy with a `COWORLD_PLAYER_WS_URL` environment
variable. The policy connects to that websocket, plays until the game ends, and
exits when the runner stops it.

- **Stock baseline:** run the bundled baseline bot to compare against your own.
- **Improve baseline:** edit `players/baseline/` and use its README as a guide.
- **From scratch:** implement Sprite v1 in any language and package it in a Docker
  image.

## Debug overlays (visualize what your bot is thinking)

A policy can send Sprite v1 **debug sprite** packets (client message `0x86` —
see the spec above) to draw private annotations: planned paths, target marks,
heatmaps, labels. The payload is ordinary server-to-client sprite messages
(define sprite / define object / delete object / clear objects). The server
records them into the replay, and the global viewer renders the **selected
player's** overlay on the map — live and during replay playback, exact across
seeks.

- Payload sprite/object ids must stay in `0..1023` per player; the viewer
  namespaces them so players can't collide with each other or the game.
- Overlays are diagnostic only: they never affect simulation state, inputs,
  scoring, or the replay tick hash. Malformed or oversized packets
  (> 32 KiB per player per tick) are dropped.
- Define sprites once and move objects per tick — every accepted packet is
  stored in the replay, so diff-style authoring keeps files small.

## Inspect and edit maps

Maps come from a seeded procedural generator (see [`docs/RULES.md`](docs/RULES.md)
for what the terrain features do in play). To look at one interactively — or
author your own — run the map editor:

```sh
nim c --threads:on --mm:orc -r tools/map_editor.nim 8099
```

Then open <http://localhost:8099>. It loads any curated pool entry, generator
seed with the full override set, or pasted map spec, renders it through the real
game geometry, and reports the play-quality validators live — cover budget, open
sightlines, corridor connectivity, and endzone access. Failures are **locatable**:
click an open sightline and it draws a rule across the board where the validator
found it, so "why was this candidate rejected" has a visible answer rather than a
sentence.

You can also edit: add and reshape obstacles, place trenches and med kits, change
the map parameters, and export the result as a `mapSpec` you can drop straight
into a config. Maps are authored for one half (or one quadrant on 4-team boards)
and the server derives the rest, so team fairness is structural — you cannot
accidentally give one side more cover than the other.

For a static, zoomable view of the whole curated pool without running anything,
open [`docs/pool-review.html`](docs/pool-review.html).

## Inspect replay timelines

Use `tools/expand_replay.nim` to get a text view of a replay — tick numbers, phase
changes, movement, shots, kills, flag pickups/returns/captures, and score changes.

```sh
nim r tools/expand_replay.nim tests/replays/<replay>.bitreplay
```

Use `tools/extract_events.nim` for the analysis JSONL stream. It includes
correlated gun trigger/fire/impact stages, grenade throws and impacts, spray
uses, pickups, shouts, and the existing damage/kill/objective events:

```sh
nim r tools/extract_events.nim tests/replays/<replay>.bitreplay
```

Start with replays where your bot scored poorly, died early, stood still, missed
shots, or failed to escort/defend the flag carrier. Expand the timeline, name the
failed capability, then find the function in `players/baseline/` that controls it.
