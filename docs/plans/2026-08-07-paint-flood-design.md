# Paint Flood — shrinking-arena endgame

## Problem

Timed games that reach `maxTicks` without a capture or wipe end in a scoreless
draw (`checkMaxTicks`). Passive play can ride the clock out. We want an
endgame forcing function: when the clock gets low, killer paint flows in from
all four map edges, shrinking the safe area toward the center until somebody
wins.

## Behavior

- When the game clock has **`paintFloodStartSec` seconds remaining** (default
  20), the flood latches on and paint starts advancing inward from all four
  edges at **`paintFloodPxPerSec` map-pixels per second** (integer; the mode
  is off at the default 0).
- The advance is **monotonic from the latch tick**: kills extend the clock via
  the existing action floor (`floorGameClock`), but the flood never retreats —
  extra overtime just gives it more time to finish the sweep.
- Any live cog whose solid body box touches the flooded band **dies**
  (a normal death: deaths stat, lives decrement, flag return, respawn if lives
  remain). Log line: `<color> swallowed by the paint flood`. Respawns still
  use the team endzone; if the endzone is already flooded the fresh spawn is
  consumed on the next tick — lives drain at `respawnTicks` pace, which is the
  intended endgame pressure.
- Depth caps at `min(MapWidth, MapHeight) div 2 + 1` — full coverage. As the
  flood consumes players, the existing wipe check ends the game the moment at
  most one team has live players. A tie now requires the last players of two
  teams to die on the same tick, which the flood makes vanishingly rare.

## Config

| Field | JSON key | Default | Bounds |
|---|---|---|---|
| `paintFloodPxPerSec` | `paintFloodPxPerSec` | 0 (off) | >= 0; > 0 requires `maxTicks > 0` |
| `paintFloodStartSec` | `paintFloodStartSec` | 20 | >= 1 |

`configJson` emits the two keys **only when the mode is on** (same pattern as
`handicaps`), so a default game's replay config echo is byte-identical.

## Sim

- `SimServer.paintFloodStartTick: int` — the `tickCount` at which the flood
  latched; -1 before. Set to -1 in `initSimServer`, `resetToLobby`, and
  `startGame`. Latch condition (checked each Playing tick):
  `effectiveMaxTicks - gameTicksElapsed <= paintFloodStartSec * TargetFps`.
- `paintFloodDepth(sim)` = `(tickCount - paintFloodStartTick) * pxPerSec div
  TargetFps`, clamped to the full-coverage cap. Pure integer math off
  deterministic state — replays re-derive it exactly.
- A new `updatePaintFlood(sim)` runs in `step()` after combat/pickups and
  before `checkWinCondition`, so flood deaths feed the same tick's win check.
- `killPlayer` gains an optional `cause: string` that replaces the
  "killed by X" log line; flood kills pass killerIndex -1 with a cause.
- `gameHash` mixes `paintFloodStartTick` **only when >= 0** — a default game's
  hash stream is untouched, so all six fixtures pass without a GameVersion
  bump (GV stays 40; per the GameConfig-additions rule the default path is
  byte-identical).

## Rendering (board + POV)

No new wire messages — the flood is sprites + objects, so the wasm replay
viewer renders it for free.

- Two solid dark-violet strip sprites per stream: horizontal
  `MapWidth × FloodStripPx` and vertical `FloodStripPx × MapHeight`
  (`FloodStripPx = 8`).
- **Permanent rows, stain-style**: once a strip row is fully submerged it is
  placed once and deliberately left out of `currentIds`, so it persists at
  zero per-frame cost (`addPaintStains` pattern). Per-viewer cursors
  (`floodRowsSent: array[4, int]`) live in both viewer states; a cursor ahead
  of the current flood (new game) deletes the stale objects and re-arms.
- **Four frontier strips** (fixed object ids, one per side) are re-placed each
  frame at `depth - FloodStripPx`, overlapping the permanent rows, so the
  front advances pixel-smooth while costing 4 object messages per frame.
- Drawn in both the spectator board section and the player POV (bots must see
  the deadly band; it is semantic terrain, not decoration), unfogged, at a
  high z so it covers floor art and pickups. Label `paint flood` joins the
  label manifest (regenerated via `test_label_contract`).

## Testing

`tests/test_paint_flood.nim`:
1. Config: default off; JSON round-trip; echo gating; validation errors
   (negative rate, rate without maxTicks, startSec < 1).
2. Latch tick + depth math against a hand-computed schedule.
3. Kill on touch: edge-placed player dies with deaths/lives/log updated;
   center player survives.
4. Anti-tie: a passive two-player game with the mode on ends before/at the
   time limit by wipe or survivor win, not a timeout draw.
5. Default-path invariance: existing fixture tests (capture-seed1, draw-nokill,
   wipe-lives1, gen-*) must pass unchanged.

Docs: RULES.md gets a "Paint flood" section; ENV_VARIATION.md gets the two
fields.
