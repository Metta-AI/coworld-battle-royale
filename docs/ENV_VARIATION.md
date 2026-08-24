# Environment Variation Catalog

Every knob that changes what a level looks like or plays like — for procedurally
generating new levels / curricula. Two kinds of knobs:

- **`GameConfig` fields** — league-settable per game via JSON (`src/ctf/sim_config.nim`).
  This is the primary variation surface (~40 fields + `mapGen` + `slots[]`).
- **Compile-time consts** (`src/ctf/sim_types.nim`) — the defaults those fields
  fall back to, plus tuning constants that are *not* individually config-exposed
  but define the gameplay envelope. Varying these needs a code change (and usually
  a GameVersion bump if they enter `gameHash`).

Key files: [`src/ctf/sim_types.nim`](../src/ctf/sim_types.nim) (types + consts),
[`src/ctf/sim_config.nim`](../src/ctf/sim_config.nim) (config lifecycle/validation/JSON),
[`src/ctf/arena.nim`](../src/ctf/arena.nim) (maps + procedural generator),
[`src/ctf/map_pool.nim`](../src/ctf/map_pool.nim) (curated seeds),
[`src/ctf/roster.nim`](../src/ctf/roster.nim) (team/seat assignment),
[`src/ctf/sim.nim`](../src/ctf/sim.nim) (item spawn placement).

Struct: `GameConfig` at [sim_types.nim:828](../src/ctf/sim_types.nim#L828).
Defaults: `defaultGameConfig()` [sim_config.nim:10](../src/ctf/sim_config.nim#L10).
JSON read: `update()` [sim_config.nim:385](../src/ctf/sim_config.nim#L385).
Validation: `validate()` [sim_config.nim:295](../src/ctf/sim_config.nim#L295).
Serialize: `configJson()` [sim_config.nim:482](../src/ctf/sim_config.nim#L482).

Legend: **JSON key** is the config-file key when it differs from the field name.
Bounds are enforced by `validate()` unless noted "(gen)" = checked inside the map
generator.

---

## Map selection & generation — the richest variation surface

Pick an arena with `mapPath`, then (for `gen`/`pool`) shape terrain with `mapSeed`
+ the `mapGen` overrides.

| Field | Type / default | JSON key | Bounds | Effect |
|---|---|---|---|---|
| `mapPath` | string / `"arena"` | `map`, `mapPath` | resolved | Which arena: `"arena"`, `"arena-large"` (hand-authored), `"gen"` (procedural), `"pool"` (curated seeds). |
| `mapSeed` | int / `-1` | `mapSeed` | -1 = derive from game `seed` | Terrain seed for gen/pool maps. |
| `mapPoolIndex` | int / `-1` | `mapPoolIndex` | -1 = `mapSeed mod 20` | Explicit pool pick (pool = 20 seeds, `map_pool.nim:5`). |
| `mapGen` | `MapGenOverrides` | (per-field below) | per-field | Per-parameter generator locks. |
| `mapSpec` | string / `""` | `mapSpec` | must be JSON object | Frozen expanded geometry for replay determinism; **derived**, filled at parse, not authored. |

### `MapGenOverrides` — the procedural terrain knobs

Definition [sim_types.nim:796](../src/ctf/sim_types.nim#L796). Zero/`-1`/`""` value =
"unlocked, draw from seed". Validated inside `generateMapAttempt` (`arena.nim:1315+`).

| Field | Type / default | JSON key | Valid values / draw | Effect |
|---|---|---|---|---|
| `size` | string / `""` | `mapSize` | `small`/`standard`/`large`/`huge`/`giant` (scales 0.85/1.0/1.3/1.8/2.6 of 1235×659); `colossal`=5.2 override-only | Field dimensions. |
| `symmetry` | string / `""` | `mapSymmetry` | 2-team: `mirror`/`rot180` (coin); 4-team draws `rot90` (square), `quadmirror` override = rectangular board completed by both reflections (GV39) | How half/quadrant seed set completes. |
| `columns` | int / `0` | `mapColumns` | `3..24` (gen); draw 4-team 3–4, compact-endzone 6–8, else 4–6 | Obstacle column count per half. |
| `windows` | int / `-1` | `mapWindows` | `0..6` per half; -1 = draw | Glass-window count (walls transparent to fog). |
| `centerFeature` | string / `""` | `mapCenterFeature` | `bracket`/`ring`/`walls` | Central obstacle archetype. |
| `layout` | string / `""` | `mapLayout` | 4-team: `corners`/`plus` (coin); 2-team `""`/`sides` | Team placement (4-team). |
| `pits` | int / `-1` | `mapPits` | `0..64` (gen); -1 = density draw; even = symmetric pairs, odd = center pit; 4-team supports only 0/-1 | Exact trench count. |
| `pitDensity` | int / `-1` | `mapPitDensity` | `0..1000` percent (gen); -1 = 100; ignored if `pits` set | Trench density multiplier. |
| `puddles` | int / `0` | `mapPuddles` | `0..64` (gen), COUNT mode only — ≤0 = none (the default, no density draw); even = symmetric pairs, odd = center puddle; 4-team supports only ≤0 | Exact paint-puddle count (damage-over-time floor hazards; see `puddleDamagePct`). |
| `endzone` | string / `""` | `mapEndzone` | `column`/`disc`/`square`; 2-team draw ¼ disc / ¼ square / ½ column; 4-team forced column | Home capture-region shape. |
| `endzoneRadius` | int / `0` | `mapEndzoneRadius` | `90..width` (gen); needs disc/square; 0 = draw | Compact endzone scoring radius. |
| `baseDepth` | int / `0` | `mapBaseDepth` | `400..800` permille (gen); needs disc/square; 0 = draw | Home anchor depth. |

Generator internals (all `arena.nim`, config-gated, no GameVersion bump; change in code):
`MapGenMaxAttempts`=100 (re-rolls until validators pass), `MinCorridorWidth`=26,
cover-density band `CoverPermilleMin`=40..`CoverPermilleMax`=170,
`ColumnFamily` per column = one of `colStubs`/`colDiamonds`/`colDiscs`/`colChevrons`,
pit-candidate kinds `pitInstead`/`pitGap`/`pitEndzone`, curated `MapPoolSeeds` = 20 seeds.

### Hand-authored arenas (fixed geometry, selected by `mapPath`)

- **`arena`** (`arenaCtfMap()` [arena.nim:462](../src/ctf/arena.nim#L462)): 1235×659,
  `flagRing`=70, `captureClear`=210, `spawnClearW`=70, `spawnClearH`=130,
  `gunRange`=1050, 5 obstacle columns, 2 med-kit spawns.
- **`arena-large`** (`arenaLargeCtfMap()` [arena.nim:486](../src/ctf/arena.nim#L486)):
  1606×858, `flagRing`=91, `captureClear`=273, `spawnClearW`=91, `spawnClearH`=169,
  2 med-kit spawns.

Per-map descriptor `CtfMap` [sim_types.nim:733](../src/ctf/sim_types.nim#L733) carries
`width`/`height`, `flagRing`, `captureClear`, `spawnClearW/H`, `gunRange`, `endzone`
+ `endzoneRadius`, `homeDepth`, `symmetry`, `layout`, `genSeed`, `medKitSpawns`,
`leftObstacles`, `trenches` — mostly derived from the above, not separately config-set.

> **Note:** if the config omits `gunRange`, it is overwritten by the selected map's
> own `gunRange` ([sim_config.nim:454](../src/ctf/sim_config.nim#L454)).

---

## Teams & agents

| Field | Type / default | Bounds | Effect |
|---|---|---|---|
| `teams` | int / `2` | must be `2` or `4` | Active team count: 2 (classic sides) or 4 (corners/plus FFA). |
| `minPlayers` | int / `16` | `1..32` | Players required to start; effectively sets roster size on open join. |
| `closedRoster` | bool / `false` | needs ≥`minPlayers` named+tokened slots | Fixed named roster vs open join. |
| `slots` | `seq[PlayerSlotConfig]` / `@[]` | ≤32; unique names/tokens; `team < teams` | Per-seat overrides. |
| `handicaps` | `array[Team, int]` permille / all `0` | authored as `{team: 0.0..1.0}` | Per-team handicap: 0 = normal, 1 = 50% miss + 1 life + 1 hit point + ½ max speed, linearly interpolated. |
| `perks` | `array[Team, seq[PerkGroup]]` / all empty | perk names `armor scope grenade thruster luck`; flat list, list-of-groups, or policy-name object | Per-team perk groups: one unnamed group = team-wide, N unnamed = per-policy (CTF-Doubles) dealt to distinct policies in join order, named (object form) = pinned to exact policies. |
| `perkMods` | `PerkMods` struct / `DefaultPerkMods` | `armorHp` `0..100`, `luckDamage` `1..100`, fractions authored `0.0..1.0` (permille-stored) | Perk magnitudes: `armorHp` (1) extra hp, `scopeAim` (0.5) aim-sigma cut, `grenadeRange` (0.25) extra throw range, `thrusterSpeed` (0.1) extra speed, `luckChance` (0.1) lucky-shot odds, `luckDamage` (2) lucky-shot hp. |
| `puddleDamagePct` | int / `20` | `0..100` | Percent chance of 1 damage per full second of continuous paint-puddle occupancy; inert on maps without puddles (`mapPuddles`). |
| `barrierPickups` | int / `0` | `0..2` ([sim_config.nim](../src/ctf/sim_config.nim) validate, cap `MaxBarrierPickupsPerTeam`) | Cardboard-barrier pickups PER TEAM, staged between base anchor and map center ([sim.nim `barrierSpawnPoints`](../src/ctf/sim.nim)); 0 = none (the default — echo omitted, no GV bump). |
| `mode` | string / `"ctf"` | `mode` | `"ctf"` or `"ffa"` | Match rules. `"ctf"` is the classic team game and every ffa branch is gated off it (a ctf game draws no new RNG and hashes exactly as before); `"ffa"` is battle royale: single life, no hearts, N-derived spawn ring with seed-rotated seat-to-pad ownership, last player standing. Echoed into the replay config only in ffa. |
| `numPlayers` | int / `0` | `numPlayers` | `2..16` in ffa; must be `0` in ctf | ffa seat count N. Explicit values win; when omitted, FFA derives N from `players` length, or `tokens` length when no `players` roster is authored. Everything ffa derives from it — the fixed spawn-pad ring and its seed-derived per-episode rotation ([sim_state.nim `ffaSpawnPosition`](../src/ctf/sim_state.nim)), the lobby's `minPlayers` default, every per-player container. |
| `ringEnabled` | bool / `false` | `ringEnabled` | ffa only | Enables the shrinking circular safe zone; omitted ffa configs enable it by default. |
| `ringShrinkSec` | int / `150` (`FfaRingShrinkSec`) | `ringShrinkSec` | `>=1` (ffa only) | Linear safe-zone shrink duration from the arena-covering radius to the configured floor. |
| `ringFloorAreaPct` | int / `3` (`FfaRingFloorAreaPct`) | `ringFloorAreaPct` | `1..100` (ffa only) | Safe-zone floor as a percentage of the arena area; the shipped 3% floor herds late survivors while gradual outside damage limits ring-only executions. |
| `ringDamageTicks` | int / `48` (`FfaRingDamageTicks`) | `ringDamageTicks` | `>=1` (ffa only) | Cadence for one HP of outside-ring damage. |
| `ringRecoveryTicks` | int / `2` (`FfaRingRecoveryTicks`) | `ringRecoveryTicks` | `>=0` (ffa only) | Exposure ticks drained per tick spent inside the safe zone; zero reproduces reset-on-entry behavior. |
| `ffaGunDamage` | int / `3` (`FfaGunDamage`, mid-tier) | `ffaGunDamage` | `1..5` (ffa only) | Direct mid-tier gun damage per hit against the FFA hit-point pool; low and heavy tiers use their named ladder constants. |
| `ffaSprayDamage` | int / `4` (`FfaSprayDamage`) | `ffaSprayDamage` | `1..4` (ffa only) | Direct plasma-arc damage in FFA. |
| `ffaGrenadeDamage` | int / `4` (`FfaGrenadeDamage`) | `ffaGrenadeDamage` | `1..4` (ffa only) | Direct grenade damage in FFA. |
| `ffaGrenadeTrenchSplashDamage` | int / `1` (`FfaGrenadeTrenchSplashDamage`) | `ffaGrenadeTrenchSplashDamage` | `1..4` (ffa only) | FFA grenade damage when the victim is in another trench. |
| `ffaMedKitSpawns` | int / `2` (`FfaMedKitSpawns`) | `ffaMedKitSpawns` | `1..2` (ffa only) | Upper bound on the weighted med-kit share of the FFA center cluster; the share remains a minority as the cluster grows. |
| `ffaLootCount` | int / `12` (`FfaLootCount`) | `ffaLootCount` | `0..64` (ffa only) | Total seq-backed center-cluster items. Sustain items use roughly one sixth each when large enough; the remainder is split between spray cans and barriers, plus four relocated grenade slots. |
| `ffaLootRadius` | int / `180` (`FfaLootRadius`) | `ffaLootRadius` | `>=1` (ffa only) | Maximum center-cluster radius in map pixels; center items are bounded by the rectangular arena, while low/mid/heavy gun families use deterministic per-axis outer, intermediate, and center bands. |
| `ffaLootRespawnTicks` | int / `480` (`FfaLootRespawnTicks`) | `ffaLootRespawnTicks` | `>=1` (ffa only) | Respawn cadence for offensive FFA cluster items after pickup. Med kits and shields retain their slower 30-second cadence; initial appearances are staggered every three seconds. |
| `ffaLowGunSpawns` | int / `0` (`FfaLowGunSpawns`) | `ffaLowGunSpawns` | `0..16` (ffa only) | Low-tier gun pickups. `0` derives one per player; deterministic placements are outside the center cluster and use the offensive loot respawn cadence. |
| `ffaMidGunSpawns` | int / `0` (`FfaMidGunSpawns`) | `ffaMidGunSpawns` | `0..16` (ffa only) | Mid-tier gun pickups. `0` derives `max(2, numPlayers div 4)`; deterministic placements sit between the center cluster and spawn ring and use the offensive loot respawn cadence. |
| `ffaHeavyGunSpawns` | int / `0` (`FfaHeavyGunSpawns`) | `ffaHeavyGunSpawns` | `0..16` (ffa only) | Heavy-tier gun pickups. `0` derives `max(1, numPlayers div 4)`; deterministic placements are center-cluster only and use the offensive loot respawn cadence. |

The baseline FFA bot enables this late-close behavior by default: once three or
fewer players remain, it closes on the nearest living enemy while retaining
ring safety and normal aim/fire gates. Set `CTF_BOT_FFA_LATE_CLOSE=0` to
disable it for comparison arms; `1` explicitly enables it.

**Per-team handicap** ([sim_types.nim `handicaps`](../src/ctf/sim_types.nim), accessors
`hitPointsFor`/`livesFor`/`maxSpeedFor`/`missPermilleFor`): a single `0.0..1.0`
knob per team, authored as a float map `"handicaps": {"red": 0.0, "blue": 0.6}`
and stored internally as permille (`0..1000`) so every in-sim derivation is
integer-only (native/wasm agree). At `0` a team plays normally (byte-identical to
no handicap — no extra RNG, existing replays re-simulate unchanged); at `1` it
gets 50% of would-be gun hits dropped, 1 life, 1 hit point, and half max speed;
values between interpolate linearly from the base config toward that floor.
Omitted/inactive teams stay at 0. Intended for a league (Campaign) to weaken a
dominating team. Handicaps are OBSERVABLE to policies: the init snapshot
carries one `handicap <color> <permille> hp <n> lives <n> spd <n> miss <n>`
marker per team (every team, permille 0 included) stating the fraction and the
engine-resolved deltas — see docs/RULES.md. Design: [docs/plans/2026-08-05-per-team-handicaps-design.md](plans/2026-08-05-per-team-handicaps-design.md).

**Team perks** ([sim_types.nim `Perk`](../src/ctf/sim_types.nim), accessors
`maxHpFor`/`maxSpeedFor(team, perks)`/`grenadeRangeFor`; join resolution
`roster.nim perkSetForJoin`): named buffs assigned per team as
`"perks": {"red": ["armor", "scope"]}` (one team-wide group),
`"perks": {"blue": [["grenade"], ["thruster", "luck"]]}` (unnamed per-policy
groups, CTF-Doubles: the Nth distinct policy to seat on the team gets group N,
clamped to the last), or `"perks": {"blue": {"botA": ["grenade"], "botB":
["luck"]}}` (groups PINNED to policy names; an unmatched policy gets nothing).
Magnitudes are the `perkMods` block
(`{"armorHp": 1, "scopeAim": 0.5, "grenadeRange": 0.25, "thrusterSpeed": 0.1,
"luckChance": 0.1, "luckDamage": 2}`), fractions stored as integer permille.
armor = +hp per bot; scope = tighter gun aim; grenade = longer throws;
thruster = faster top speed; luck = a fraction of landed gun shots deal
`luckDamage`. Defaults (no perks) are byte-identical to an engine without the
feature — no extra RNG, existing replays re-simulate unchanged. Perks are
OBSERVABLE: one `perks <color> <group> [<group>…]` marker per team in the init
snapshot and per-seat `pk` arrays in the broadcast roster — see docs/RULES.md.
Design: [docs/plans/2026-08-07-team-perks-design.md](plans/2026-08-07-team-perks-design.md).

`Team` enum: Red, Blue, Green, Yellow ([sim_types.nim:637](../src/ctf/sim_types.nim#L637));
active teams are always the prefix `Red..Team(teams-1)`. Hard caps `MaxPlayers`=32,
`MinPlayers`=16. Seats deal round-robin over active teams (`roster.nim:11`) unless a
slot pins a team. **There is no "players-per-team" knob** — it emerges from
`minPlayers`/joins split across `teams`.

Per-slot config `PlayerSlotConfig` [sim_types.nim:787](../src/ctf/sim_types.nim#L787):
`name`, `token`, `team`, `color` (16-color palette), `skin` (`DefaultSkin`/`CrownSkin`).

---

## Items & pickups

Counts are **not** individually config-numbered — they scale with `teams` and map
layout, and trench count via `mapGen`. Spawn placement in `sim.nim`.

Obstacles and trenches are `ArenaShape`s in five kinds: `rect`, `disc`,
`diamond`, `diagonal`, and (GV37+) `polygon` — a closed ring of integer vertices
for curved/organic terrain. Trenches are also `ArenaShape` (the generator emits
`rect` pits; authored maps may use any shape).

| Item | Count | Key consts (sim_types.nim) |
|---|---|---|
| Flags/hearts | 1 per active team | `FlagPickupRange`=34 (GV42, covers the 60px drawn heart), `CaptureZoneWidth`=40, `PedestalCoverSize`=96 |
| Grenades | exactly 4 corner pickups | `GrenadeRespawnTicks`=120, `GrenadeChargeTicks`=24, `GrenadeBlastRadius`=52, `GrenadeDamage`=2, `GrenadeTrenchDamage`=6 (blast in the victim's OWN trench; ffa has no analog — see the ffa consts below), `GrenadeTrenchSplashDamage`=1 (victim in a DIFFERENT trench), max throw = `MapWidth/5` |
| Med kits | 2 (sides) / up to 4 (4-team) | `MedKitPickupRange`=12, `MedKitRespawnTicks`=720 |
| Shields | 1 per team endzone | `ShieldRespawnTicks`=720, `ShieldLayerHp`=3, `ShieldFireSlowdown`=3 |
| Plasma arcs (spray) | 1 per team endzone | `PlasmaArcRespawnTicks`=720 (`30 * ReplayFps`), `PlasmaArcPickupRange`=12, `PlasmaArcSpawnInset`=`GrenadeSpawnInset`, `PlasmaArcSquare`=`SoldierBodyPx`=34, `PlasmaArcReach`=170 (5 squares), `PlasmaArcMaxWidth`=85 (cone width at max reach), `PlasmaArcBodyRadius`=17, `PlasmaArcDamage`=3 (ffa: `ffaSprayDamage`=4), `PlasmaArcActiveTicks`=5 / `PlasmaArcResetTicks`=20 (one burst every 25 ticks; the can is never consumed), fx-only `PlasmaArcFxReach`=136 / `PlasmaArcFxMaxWidth`=68 / `PlasmaArcFxTicks`=4 |
| Trenches | via `mapGen.pits`/`pitDensity` | `TrenchSize`=56, `TrenchSpeedDivisor`=5, `TrenchFireSlowdown`=3, `TrenchMissPct`=70 |
| Paint puddles | via `mapGen.puddles` (`mapPuddles`) | `PuddleSize`=64, `PuddleRollTicks`=24, `DefaultPuddleDamagePct`=20 (config `puddleDamagePct`), `MaxPuddles`=64 |
| Cardboard barriers | via `barrierPickups` (per team) | `BarrierHp`=10, `BarrierRadius`=24, `BarrierHalfThick`=2, `BarrierRespawnTicks`=720, `MaxBarriersPlaced`=16 ([sim_types.nim](../src/ctf/sim_types.nim)) |

To vary item counts today: change `teams` (scales per-team items), change `mapGen`
pits (trenches), or edit the per-map spawn lists / consts in code.

---

## Scoring & win conditions

| Field | Type / default | JSON key | Bounds | Effect |
|---|---|---|---|---|
| `scoring` | string / `"classic"` | `scoring` | `"classic"` or `"pot"` | Reward rule: classic (+1 win / −1 loss) vs pot (ante/pot split). |
| `maxTicks` | int / `7200` (5:00) | `maxGameTicks` | `>=0` | Scheduled game end (0 = unlimited); with the barrage on it is not a hard end. |
| `gameOverTicks` | int / `360` | | `>=0` | End-screen dwell ticks. |
| `maxGames` | int / `0` | | `>=0` | Games before server stops (0 = unlimited). |
| `barrageMaxPerSec` | int / `0` (off) | | `0..50`; `>0` needs `maxTicks>0` | Grenade-barrage endgame: environment grenades rain from the edges inward, ramping to this rate across the whole board (see RULES.md "Grenade barrage"). |
| `barrageStartPerSec` | int / `4` | | `1..barrageMaxPerSec` | Launch rate at the latch, targeting a 40px band inside every edge. |
| `barrageStartSec` | int / `30` | | `>=1` | Clock seconds remaining that latch the barrage (4:30 elapsed on the default 5:00 clock). |
| `barrageSaturateSec` | int / `30` | | `>=1` | Seconds from latch to full saturation (whole board at `barrageMaxPerSec`); defaults land it exactly at the scheduled end. |
| `survivalPointsPerSec` | int / `1` (`FfaSurvivalPointsPerSec`) | `survivalPointsPerSec` | `>=0` (ffa only) | ffa reward per whole second alive, accrued live once every `TargetFps` ticks of play. |
| `killPoints` | int / `10` (`FfaKillPoints`) | `killPoints` | `>=0` (ffa only) | ffa reward to the LAST damager of a kill. Environmental deaths (puddle, barrage) credit nobody. |
| `assistPoints` | int / `4` (`FfaAssistPoints`) | `assistPoints` | `>=0` (ffa only) | ffa assist pot for a kill, split evenly among the victim's other recent damagers (integer split, remainder dropped). |
| `assistWindowTicks` | int / `240` (`FfaAssistWindowTicks`) | `assistWindowTicks` | `>=0` (ffa only) | How far back a damager still counts as an assister; also bounds the in-sim damage log. |
| `podiumPoints` | `seq[int]` / `@[100, 40, 15]` (`FfaPodiumPoints`) | `podiumPoints` | each `>=0` (ffa only) | ffa reward by final placement, best first; places past the list pay nothing. |

ffa consts: `FfaHitPoints`=20 (spawn pool), weapon ladder
`FfaFistDamage`=2 / `FfaLowGunDamage`=2 / `FfaMidGunDamage`=3 /
`FfaHeavyGunDamage`=5 with cooldown percentages 200% / 150% / 100% / 60%
(`FfaLowGunCooldownPct`=150, `FfaMidGunCooldownPct`=100,
`FfaHeavyGunCooldownPct`=60 applied to `fireCooldownTicks` and floored at 1
tick; the fist's 200% is the literal `2 *` in `tryFist`, and the declared
`FfaFistCooldownTicks`=24 is not read on the fire path), tier ranges
`FfaLowGunRange`=700 / `FfaMidGunRange`=`GunRange`=1050 /
`FfaHeavyGunRange`=`GunRange`=1050 (only mid reads `config.gunRange` at runtime;
low and heavy are consts, so retuning `gunRange` moves mid's range alone — while
`aimJitterSigma` reads it for every tier, so the retune still shifts all three
tiers' accuracy), tier ids
`FfaWeaponUnarmed`=0 / `FfaWeaponLow`=1 / `FfaWeaponMid`=2 /
`FfaWeaponHeavy`=3, fist geometry `FfaFistReach`=70 px center-to-center and
`FfaFistAimHalfBrads`=48 (of the 256-brad turn, so ±67.5°),
plus `FfaSprayDamage`=4 / `FfaGrenadeDamage`=4 /
`FfaGrenadeTrenchSplashDamage`=1 (there is no ffa analog of
`GrenadeTrenchDamage`, so a blast in the victim's own trench deals the ordinary
`ffaGrenadeDamage`),
`FfaRingDamage`=1 (one hp per `ringDamageTicks` outside the safe zone),
`FfaMedKitSpawns`=2,
`FfaSpawnRingPermille`=800 (spawn-ring radius as permille of the inscribed
circle; seed-derived rotation changes ownership, not the pad set),
`FfaMinPlayers`=2, `FfaMaxPlayers`=16. Weapon tiers carry **no ammo,
durability, or magazine** and never expire: a tier is set at match start, raised
only by a higher-tier pickup, and otherwise permanent (single life, so death
ends it). Aim-jitter sigma is calibrated against `config.gunRange` alone and is
NOT re-derived per tier, so the GV34 "80% at max range" figure holds for mid and
heavy while low hits ~94.5% at its own 700 px maximum
(https://github.com/Metta-AI/coworld-battle-royale/issues/19); the fist rolls no
jitter and no trench duck at all, so a punch inside reach, cone, and line of
sight is deterministic. No tier touches MOVEMENT — max speed, acceleration,
friction, and the carrier/trench speed rules read `weaponTier` nowhere, so a
heavy carrier moves exactly like an unarmed one. None of the
low/heavy damage, tier range, cooldown-percentage, fist, or spray-cycle consts
above has a `GameConfig` field — knobs proposed in
https://github.com/Metta-AI/coworld-battle-royale/issues/18; the
same-trench grenade gap is
https://github.com/Metta-AI/coworld-battle-royale/issues/20. ffa win logic: the
game ends when at most one player is alive or the clock runs out, and the total
placement order (alive > later death tick > kills > damage dealt > lower slot)
always names a single winner — an ffa match is never a draw.

Kill credit is applied inside `killPlayer` only after its alive guard, so a
valid non-self combat killer receives one kill counter increment and the
victim's recent damage can feed the assist split; environmental and
elimination deaths remain uncredited. `recordFfaDamage` ignores posthumous
victims, preserving damage dealt as the placement tiebreak under kills.

### Baseline policy doctrine (process environment)

These are reference-policy controls rather than `GameConfig` fields: they do
not change the Coworld manifest or simulation `GameVersion`. Hunter is now the
baseline default; `legacy` is the explicit opt-out for the previous behavior.
The existing selector semantics and all other doctrine arms remain unchanged.

| Environment variable | Values / default | Effect |
|---|---|---|
| `CTF_BOT_FFA_DOCTRINE` | `hybrid`, `legacy`, `passive`, `rush`, `shade`, `hunter` / `hunter` | Selects the baseline FFA doctrine; set `legacy` explicitly to opt out of hunter. |
| `CTF_BOT_FFA_HUNTER_RING_MARGIN` | float `>=0` / `0.0` | Extra safety margin used by the hunter ring gate. |
| `CTF_BOT_FFA_HUNTER_ARM` | bool / `true` | Allows hunter trips to arm a weapon. |
| `CTF_BOT_FFA_HUNTER_FIRE_RANGE` | bool / `true` | Enables hunter range gating. |
| `CTF_BOT_FFA_HUNTER_PURSUIT` | bool / `true` | Enables hunter pursuit of a weaker target. |
| `CTF_BOT_FFA_HUNTER_PURSUIT_MIN_HP` | int `>=1` / `6` | Minimum hunter HP for pursuit. |
| `CTF_BOT_FFA_HUNTER_SUPPORT_RADIUS` | float `>=1` / `300.0` | Radius used to detect supporting allies. |
| `CTF_BOT_FFA_HUNTER_ARM_TRIP_MAX_SEC` | int `>=1` / `30` | Maximum hunter arming-trip duration. |
| `CTF_BOT_FFA_HUNTER_ARM_TRIP_MAX_DETOUR_RADIUS` | float `>=1` / `240.0` | Maximum detour radius for an arming trip. |
| `CTF_BOT_FFA_HUNTER_ARM_SAFE_MARGIN` | float `>=0` / `80.0` | Safety margin required before arming. |

The hunter-only controls are ignored by the other doctrines. The parser in
[`players/baseline/baseline.nim`](../players/baseline/baseline.nim#L4083)
keeps an unset `CTF_BOT_FFA_DOCTRINE` at `hunter`; set it to `legacy` for the
explicit opt-out. The defaults and bounds for the hunter controls are declared at
[`baseline.nim:253`](../players/baseline/baseline.nim#L253).

Reward consts: `WinReward`=+1, `LossReward`=−1, `TimeoutReward`=−1 (draw penalty).
GV41 removed the action-floor overtime: the clock never extends, and a game with
the barrage configured ignores `maxTicks` entirely (it ends only on capture/wipe). Win logic:
capturing a heart eliminates that team; last team standing wins; 2-team ends on
first capture.

---

## Combat

| Field | Type / default | Bounds | Effect |
|---|---|---|---|
| `lives` | int / `3` | `>=1` | Respawns per player before permanent death. |
| `hitPoints` | int / `3` | `>=1` | Hits to kill. |
| `respawnTicks` | int / `72` (~3s) | `>=0` | Delay before respawning at home. |
| `gunRange` | int / `1050` px | `>0` | Gun reach; also drives aim-jitter sigma. Falls back to map's `gunRange` if omitted. |
| `fireCooldownTicks` | int / `12` (~0.5s) | `>=0` | Ticks between shots. |
| `fireWindupTicks` | int / `5` (~0.2s) | `>=0` | Trigger-pull-to-shot delay; aim locks at pull. |
| `carrierSpeedPct` | int / `70` | `1..100` | Flag/heart carrier movement speed %. |

Non-config envelope consts (change in code): `BulletHalfWidth`=8.0,
`AimJitterCentralZ`=1.2815516, `CarrierFireSlowdown`=3,
`FireMaxToleranceBrads`=32 (FFA baseline close-range aim gate cap).

---

## Aim & vision

| Field | Type / default | Bounds | Effect |
|---|---|---|---|
| `aimTurnRate` | int / `5` | `>=1` | Aim rotation speed in brads per tick. |
| `visionConeDeg` | int / `60` | `0..180` | Vision cone half-angle around aim. |
| `visionBubble` | int / `90` | `>=0` | Omnidirectional vision radius (px). |

Non-config: `FovCellSize`=8, `visionRange`=1.5×gunRange.

---

## Motion / physics

Integer fixed-point model — `accel` = thrust, `frictionNum/frictionDen` = drag,
`maxSpeed` = velocity clamp. No `mass`/`drag`/`thrust` fields.

| Field | Type / default | Bounds | Effect |
|---|---|---|---|
| `motionScale` | int / `256` | `>0` | Fixed-point subpixel scale; a pixel of movement per `motionScale` of carry. |
| `accel` | int / `76` | | Per-tick acceleration while a direction is held (1/256 px/tick). |
| `maxSpeed` | int / `704` | | Per-axis velocity clamp (~2.75 px/tick). |
| `frictionNum` | int / `144` | | Friction numerator (idle velocity ×144/256 ≈ 56%/tick). |
| `frictionDen` | int / `256` | `>0` | Friction denominator. |
| `stopThreshold` | int / `8` | | Below this idle abs velocity, snap to 0. |
| `playerBouncePct` | int / `40` | `0..100` | Restitution of player-player collisions (0 = dead stop, 100 = elastic). |

Non-config: `TrenchSpeedDivisor`=5 (climbing out of a trench caps that axis to 1/5),
`PlayerHalf`=6, `MovementSlideMaxScan`=3.

---

## Determinism, pacing & timing

| Field | Type / default | JSON key | Bounds | Effect |
|---|---|---|---|---|
| `seed` | int / `0xA6019` | `seed` | | Master sim RNG seed (spawns, shot jitter, trench misses, respawns). Also feeds map seed when `mapSeed=-1`. |
| `speed` | int / `1` | `speed` | in `[1,2,3,4,8,16]` | Playback/real-time multiplier (pacing only, not physics). |
| `fastMode` | bool / `true` | | | Advance frames early once all ready (pacing; never hashed). |
| `startWaitTicks` | int / `120` (5s) | `gameStartWaitTicks` | `>=0` | Countdown once roster full. |
| `lobbyJoinTimeoutTicks` | int / `0` | | `>=0` | Abort lobby if still short (0 = wait forever). |
| `showPlayerLabels` | bool / `true` | | | Cosmetic name labels. |

---

## What varies a level, ranked

1. **`mapPath="gen"` + `mapSeed` + `mapGen` locks** — by far the richest: field size
   (5 classes), symmetry, 2-vs-4 team layout, columns (3–24) & family, windows (0–6),
   center feature, endzone shape + radius + depth, trenches (0–64).
2. **`teams`** (2/4) — changes layout, item counts, and win logic.
3. **Combat/motion/vision fields** — same map, different game feel and skill ceiling.
4. **`scoring`, `maxTicks`, `lives`, `hitPoints`** — match structure and stakes.

Cosmetic FX-duration consts (`ShotFxTicks`, `HitFlashTicks`, `SplatterFxTicks`, …)
never enter `gameHash` and do not vary gameplay.
