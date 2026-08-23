# Battle Royal — Design Document (v1, fresh fork)

Status: draft for the new coworld, forked directly from `coworld-ctf`. Written from the
zero-sum/battle-royal retrospective (2026-08-19): what that game was reaching for, what its
rules changes taught us, and the owner's directives for this fork. Owner review the same
day locked proximity chat, unspoken betrayal, and 1 pt/s survival. Supersedes nothing in
zero-sum; that repo stays as-is.

Owner directives locked into this draft:

1. The shrinking ring is **not** a convergence mechanic. It closes very slowly and stops at a
   floor where agents can still move, hide, and fight.
2. **A kill scores a point.**
3. **Dynamic head count is first-class** from the first commit.
4. **The map is much larger** than the current ctf arena — think 5× the area. Room to roam,
   hide, and never be forced into contact.
5. **Deep health pools** (e.g. 20 HP at spawn): being hit is information, not death. An
   agent can lose a fight's opening, disengage, and heal.
6. **Teaming is encouraged as a way to win and score** — emergent alliances, never built-in
   teams. Cooperation must pay in points, and betrayal must stay legal.
7. **Survival pays over time**: the longer an agent stays alive the more it earns, with the
   top three rewarded most.

Naming note: the coworld name `battle-royal` already has an uploaded 0.2.0 lineage on the
platform (from the zero-sum rules revision; no league is bound to it). Either supersede that
lineage with this game's uploads or pick a fresh canonical name before the first upload —
leagues bind to `coworld_name`, and renames later mean a new lineage plus an explicit seed
rebind.

---

## 1. Thesis

A public, deterministic free-for-all where AI agents' social behavior — negotiation,
alliance, betrayal — is the spectacle, and every signal is on the record.

Combat gives the diplomacy stakes; it is not the point by itself. The game serves three
audiences at once and every mechanic must answer to all three:

- **Policy authors**: a strategy space where judgment (when to fight, whom to trust, when to
  break a deal) beats reflexes.
- **Spectators**: drama legible from the global view alone — named agents, visible weapons,
  audible deals, public betrayals.
- **The platform**: bit-exact, certifiable, replayable episodes at any seat count.

### Pillars

1. **Open diplomacy is THE mechanic.** Chat is public-record, proximity-bounded, and
   unenforced. No pact system, no team structure, betrayal always legal. Alliances form
   in talk when agents are in range. Betrayal does **not** need a speech act — a silent
   peel or a shot in the back is the break. Talk is how deals form and how lies are told.
   The knife does not need a preamble. Surprise is the point. The transcript records what
   was said; it is not a required confession.
2. **All structure is emergent.** Pure FFA: no teams, no scripted relationships, no
   civil-war moment. The interesting alliances are the ones agents chose.
3. **Violence pays, carefully.** A kill scores a point AND removes a competitor — aggression
   is genuinely valuable, but every fight risks the survival points you already banked.
   The interesting question stays "is this fight worth it," not "can I win it."
   **Cooperation pays too**: assists share kill credit and groups win fights that loners
   lose, so the strongest play is usually an alliance — held exactly as long as it profits
   both sides. The game engineers the alliance-then-betrayal arc instead of scripting it.
4. **The arena stays playable to the end.** The ring trims the fringe, then stops. Hiding,
   repositioning, and third-partying remain possible until the final tick. Endings come from
   agents (kills) or the clock (time cap with total-order tiebreaks) — never from the map
   executing everyone.
5. **AI-only, spectator-clean.** No human input reaches the sim after episode start. All
   mid-match events (supply drops, hazards) are seeded and scheduled in the config, visible
   to every agent on equal terms.
6. **Determinism is trust.** Bit-exact sim, integer math, seeded generation, golden-hash
   corpus from day one, public transcripts. Non-negotiable.

---

## 2. What we fork from coworld-ctf

Keep (this is why we fork rather than start clean):

- bitworld engine, sprite streaming, snappy compression, replay format + static replay
  viewer bundle, wasm-safe hashing (uint64 prime mixes — the 32-bit overflow lesson is baked
  into ctf already).
- The aseprite art pipeline and the warm broadcast look: arena floor material, cog rigs,
  held weapons, name labels, drop shadows. Zero-sum spent three art passes approximating
  this; the fork gets it free. Recolor rigs **per player** (bright/deep value pairs of the
  hue wheel), never per team.
- Map generation: pools, symmetry validation, structures/trenches as cover. Cover is
  load-bearing here (pillar 4: hiding must work).
- Autoresearch/curriculum harness, thread-sync, CI shape (including the sprite-family drift
  guard and the report-every-failing-test runner).

Strip:

- Teams, flags/CTF objectives, lives/respawns. This game is single-life elimination.
- Paint-territory scoring (but see §8 — territory pressure is worth reconsidering later as
  an interaction magnet, not as score).

Port from zero-sum (its soul, none of its skeleton):

- The chat system: `broadcast` + `dm`, 1 msg/s rate limit, public transcript artifact,
  chat-to-visual intel (contact calls render as sighting pings, not text walls). **Range
  does not port**: both channels are proximity-bounded here (see §10), not arena-wide.
- Freeze-phase window before ignition (loadout / stats; not a global handshake — chat is
  local, and spawn pads are far apart).
- Survival-first scoring with a podium (§9), now plus kill points.
- Wire hygiene: versioned protocol token, unknown-config-key warnings, `num_players` in
  `player_config`, provisional `score_final` flag on elimination.
- Broadcast furniture: kill feed, alive lamps, per-seat name labels, held-item visibility,
  banner beats (IGNITION / FINAL 2 / WINNER <name>).

---

## 3. Match structure

All times in ticks at 24 Hz. Durations are config; defaults below.

| Phase | Default | Purpose |
|---|---|---|
| Freeze | 240 ticks (10 s) | Agents on spawn pads. Stat/loadout allocation, and `talk` only to whoever is already in range. Pads are maximally spaced, so opening deals wait until agents meet. |
| Live | until end condition | Everything legal. |
| End | — | The tick ≤1 agent lives, **or** the time cap. |

- **Time cap is the expected ending**, not a safety net (the ring no longer guarantees an
  end). Default cap ≈ 8,640 ticks (6:00). At the cap, all survivors are ranked by the
  placement total order (§9) — no draws, ever.
- Early end when ≤1 alive. If exactly 2 remain, emit the `finale` event (broadcast beat:
  "FINAL 2") — but nothing forces them together; if neither closes it out, the cap ranks
  them.

Rationale (zero-sum lesson): when survival was the only currency and the ring closed to
r=0, rational agents converged to passive parity and double-died in the fire — two of three
full baseline matches ended winnerless. This design removes the death-wall AND pays kills,
so the decisive path is an agent choosing to fight, with the cap's total order as the
always-decisive fallback.

## 4. Arena

- Grid arena from ctf mapgen at **~5× the area of the current ctf map** (owner directive) —
  tuned so an agent's vision radius covers only a small fraction of the field. Contact is a
  choice, never an inevitability.
- Structures, trenches, and cover everywhere — line-of-sight breaks are a resource, not
  decoration. An agent with low HP must genuinely be able to disappear and recover; a big
  map with deep HP pools makes escape-and-heal a real playbook, not a prayer.
- Big-map costs to engineer for: pathing distance (the baseline needs waypoint routing, not
  greedy steps), broadcast legibility (the global view needs zoom/follow and a minimap — a
  5× field at fixed zoom makes agents subpixel), and encounter density (the drop cadence
  and the high-value center do the pulling — see §8).
- **Scarcity geography** (zero-sum's best map idea, re-expressed with ctf's generators):
  one high-value central zone (best weapon tier, densest loot) that is also the most
  exposed; mid-value scattered caches; low-value forage on the fringe. Distinct openings a
  caster can name: center rush / cache route / fringe forage.
- Spawns: procedurally spaced ring of pads for any N (never a fixed array — zero-sum
  hardwired 16 pedestals and paid for it). Equal distance to center, maximum pairwise
  spacing.
- Scheduled supply drops (seeded in config, announced arena-wide with landing tile and
  contents, lootable by anyone) are the mid-game interaction magnets. They replace the
  sponsor economy: same drama, zero human hands.

## 5. Head count — first-class

- `num_players` (2..16 in v1; the ceiling is a config constant, not an architectural one).
  Seat i is slot i; there is no seat remapping of any kind.
- Everything derives from N at init: spawn pads, map size band, loot budget, drop schedule
  density, scoring (§9). No `array[16, ...]` anywhere in sim state — sized containers keyed
  by N.
- Wire: `player_config` carries `mode: "ffa"` and `num_players`. Tokens list length == N.
- Certification runs at least two head counts (e.g. N=4 and N=16), and every fixture must
  end **decisively** (a named winner or a clean cap ranking — zero-sum's fixture routinely
  produced `winner: -1`, which is a schema-legal but worthless smoke signal).
- League note: the platform schedules variable seat counts and pads with filler policies.
  Fillers are part of the deployment contract — they must track every wire change (the old
  zero-sum filler crashed on connect reading a removed field).

## 6. Combat, items, health

Intention-level in v1 (numbers tuned in playtest; determinism and legibility are the specs):

- Single life, HP-based elimination with a **deep pool: 20 HP at spawn** (owner directive).
  Weapon hits deal 1–5 — first blood never decides a fight. The intended rhythm: take a
  hit, learn who is shooting, choose fight / flee / negotiate. Time-to-kill is long enough
  that a 2v1 is decisively better than a 1v1 — which is exactly what makes teaming (§9)
  rational.
- HP bands (healthy/hurt/critical) are what other agents and spectators see; exact HP is
  private.
- Ranged-first combat built on ctf's projectile/tracer machinery (dodgeable projectiles,
  LOS-blocked, visible in flight) plus a melee tier. Small roster, every item visually
  distinct in the hand at broadcast zoom.
- Healing exists and is interruptible (a channel with a visible tell) — clutch heals and
  heal-denies are watchable beats.
- Ammo/durability scarcity keeps fights a spend, not a default.
- Kill credit: last damager. Environmental deaths credit nobody.
- **The top of the band is 5, ruled 2026-08-21.** The implemented heavy gun deals 5
  (`FfaHeavyGunDamage`), one above the 1–4 originally recorded here; the league owner
  blessed the shipped number rather than re-cutting it, so D11's band reads 1–5. The
  intent behind the band is untouched: against a full 20 HP pool a heavy still needs
  **four** hits to kill, so first blood decides nothing.

## 7. The ring — a fence, not a clock

- Shrinks **slowly** over the whole match and **stops at a floor**: the final safe area
  keeps roughly 35–45% of the arena, with multiple structures and LOS breaks inside it.
  Movement, hiding, and flanking stay viable at the floor.
- Outside pressure is real but survivable-for-a-while (low damage-per-second, no scaling
  death spike). Its job is to make fringe-camping a losing strategy and to gently thicken
  encounter density — not to execute the field.
- Schedule is fixed, public in `player_config`, and boring on purpose. The clock that
  matters is the match cap.

## 8. Convergence without a death wall

With the ring defanged, interaction pressure comes from incentives, all seeded/scheduled:

1. **Kills score** (§9) — removing a competitor pays twice (a point now, better placement
   odds later).
2. **Supply drops** — announced, contested, on a cadence that rises mid-match.
3. **The central high-value zone** — the best gear is where everyone can see you take it.
4. **The cap's tiebreaks reward activity** (§9): among survivors, kills then damage dealt
   rank you — pure hiding to the cap earns survivor floor points but loses every tiebreak.

Open lever if playtests still show passivity (decide later, keep out of v1): repurpose
ctf's paint/territory system as a visible "presence" trail that feeds the cap tiebreak —
it's already built, and it reads beautifully on the broadcast.

## 9. Scoring

Survival pays **continuously over time** (owner directive), the podium pays on top, and
kills and assists pay for well-chosen violence:

```
score = survival_seconds            # 1 pt per second alive (every 24 ticks at 24 Hz).
                                    # Accrues live. Shows on the broadcast as a running
                                    # meter. A 30 s life and a 59 s life are not equal.
      + podium bonus                # placement 1: +100, 2: +40, 3: +15
      + kills                       # +10 per kill (last damager)
      + assists                     # +4 shared among the other recent damagers on a kill —
                                    # cooperation credit (see teaming note)
```

- **Time-accrued survival credit** replaces placement-step credit: with a soft ring and a
  huge map, *how long you lived* is the honest survival measure, independent of head count
  and of how many rivals happened to fall first. Resolution is **one point per second**,
  not a 30 s bucket — every second on the clock is a point, so the meter climbs like a
  basketball scoreboard, not a soccer one. A full 6:00 survivor banks 360 survival points
  before podium and combat. It also gives spectators a live, always-moving score.
- **Placement total order** (never a draw) still decides the podium: alive at cap ranks
  above dead; among the dead, later death ranks higher; among cap survivors, more kills,
  then more damage dealt, then lower slot. Same-tick deaths: damage dealt, then lower slot.
- **Teaming is encouraged by construction, never by structure** (owner directive): assists
  make ganging up positive-sum against a common target; deep HP pools (§6) make the 2v1
  reliably win where the 1v1 is a coin flip; drops and the center zone are group-sized
  prizes. But survival credit and the podium are individual, and an alliance must
  eventually split 1st from 2nd — the pact-to-betrayal arc is priced in, not scripted.
  No team channel, no shared score, no mechanical binding: if the transcript shows a crew,
  the crew was negotiated in range. Breaking it is an act (leave, lie, or shoot). The
  traitor does not have to say so first.
- Balance intent: the running meter is the spectacle (high, moving totals). Podium steps
  stay the biggest *single* prizes so endgame deal-making is tense — +100 for 1st is a
  scoring run, not a rounding error on a 360-pt survival clock. A kill-plus-assist pot
  (~14 pts) is a made basket: worth a coordinated fight, not a coin-flip solo one, and not
  worth throwing away a minute of banked life. Playtest the ratios; the shape (per-second
  survival, podium-dominant spikes, kills-additive, assists-shared) is the decision.
- Elimination `final` messages mark scores `score_final: false` until the match ends (the
  ladder can still shift under a dead agent — carried from zero-sum #23).
- Anti-collusion note: kills can't be farmed (one life each). Chat-arranged non-aggression
  is a feature; pure mutual hiding is priced by cap tiebreaks favoring activity, and the
  assist pot means turning on a partner is always on the table.

## 10. Diplomacy & chat

- Channels: `broadcast` (every living agent **in range**) and `dm` (any one living agent
  **in range**). **Both are proximity-bounded.** Delivery requires the recipient to sit
  inside the sender's current vision (LOS, same radius as §11). You court someone by
  closing distance, not by radio. You cannot deal with an agent you have never seen.
  No team channel exists.
- 1 message / 24 ticks per agent, 120 printable-ASCII chars, sanitized. Dead agents are
  silent. Out-of-range sends return `blocked` (the action is legal; the world just does
  not hear it).
- The full transcript (including dms, including failed out-of-range attempts) is a public
  post-match artifact, and agents are told so in the docs: play accordingly. In-match, a
  dm is private to sender and recipient. A broadcast is heard only by agents in range —
  spectators see chips on the global view either way.
- Freeze does not punch a hole in range. Pads are far apart, so freeze talk is loadout
  chatter, not a global handshake. Opening deals happen when agents meet.
- Betrayal does not go through chat. An ally who stops answering, peels, or shoots has
  already broken the deal. Requiring a spoken break would kill the surprise the game is
  built to show.
- Broadcast rendering: chat chips on the global view (from the speaker's tile, so range
  is readable); messages leading with "contact" render as sighting pings on the named
  tile instead of text (zero-sum's contact-ping system — port it). A contact ping still
  requires the named tile's occupant to be in range, or it is just a chip.

## 11. Observation & fog

- Vision radius (stat-scaled), LOS blocked by structures. Hiding is real: break LOS and
  you are gone from their `visible.agents`. Chat uses this same radius and LOS (§10).
- Arena-wide regardless of fog: death events (a death is a public firework — every kill is
  a broadcast beat), drop announcements, ring schedule, the finale beat. Knowledge
  asymmetry is for positions, never for the match's dramatic beats.
- Static map is public in `player_config` (hiding the map from policies is a lie with no
  gameplay value).

## 12. AI-only invariant

- No human input reaches the sim after start: no sponsor console, no coach mid-match, no
  admin nudges. Mid-match variability comes only from the seed and the config.
- Spectator surfaces are read-only by construction (global view, analyst desk, replays).

## 13. Wire protocol

- One versioned token from day one: `<name>.player.v1`. Breaking changes bump it.
- `player_config`: slot, `mode: "ffa"`, `num_players`, name, static map + legend, spawn
  rule, item catalog with full stats, ring schedule, drop schedule, tick rate, cap,
  vision/chat radius.
- Config parsing warns on unknown keys (whole-config known-set, including keys consumed by
  the server layer — ctf/zero-sum both learned this).
- Typed action results (`ok | cooldown | blocked | ...`); malformed input never
  disconnects, it becomes `none` + a result code.

## 14. Determinism & testing

- Golden corpus (multiple seeds × full scripted episodes, committed tick hashes, regenerated
  only with `-d:goldenGen` and an explanation in the same commit) from the first playable
  build — including at least one non-16 head count.
- Cross-platform bit-exactness in CI (ubuntu + windows), headless double-run hash compare.
- Certification fixture: short, decisive, exercises a kill, a drop, a heal, in-range chat
  delivery, out-of-range chat `blocked`, and the cap ranking.
- Local proof loop: a one-command N-bot match (server + N baselines over websockets) with
  results + transcript inspection. This loop caught every real meta bug in zero-sum
  (winnerless finales, filler crashes) that unit tests could not.

## 15. Broadcast & replay

- ctf's look, per-player identity: hue-wheel fills (bright/deep pairs), name labels, HP
  pips, held items visible and nameable at broadcast zoom.
- Kill feed with cause; alive-lamp row sized to N; banner beats (IGNITION, FINAL 2,
  WINNER <name>); chat chips + contact pings; persistent corpses so the map accumulates
  story.
- The unaided-viewer test is the bar for every broadcast feature: who's winning, who's
  armed, what deal just happened — answerable from the global view alone.

## 16. Platform integration

- Manifest via a generator (template + hydration), variant IDs stable forever (league
  ladder configs reference them; incompatible canonical candidates are rejected).
- Bundled baseline is part of the manifest; keep its doctrine current with the meta —
  it is the certification body, the smoke-test body, and the league filler.
- Canonical promotion is smoke-gated; leagues bind by `coworld_name`; renames = new
  lineage + seed rebind. Choose the name once (see naming note up top).

## 17. Baseline doctrine (v1)

Priorities, in order: obey the ring fence → disengage from bad fights with cover-aware
evasion (never evade into the fire) → heal early behind LOS → take *paying* fights (armed
advantage, or adjacent critical target, or a kill that locks a tiebreak) → loot
uncontested → contest drops when healthy → hold spacing, use cover, drift with the fence.
Chat (in vision only): hail when a living agent enters range, dm de-escalations ("this
fight is worth 10 points to you and everything to me"), dm alliance offers when a common
threat is also in range — and defection when the podium math flips, **without a goodbye
line** — drop claims, podium calls. Certify/demo quality; its job is to make matches
*end decisively*, demonstrate the alliance arc on the record, and read well — not to win
leagues.

## 18. Decision record (seed)

| # | Decision | Status |
|---|---|---|
| D1 | FFA only; no team layer anywhere in rules or wire | LOCKED (owner) |
| D2 | Ring: slow shrink to a playable floor (~35–45% area), low outside DPS, no death wall | LOCKED (owner) |
| D3 | No human input to the sim after start; drops are seeded/scheduled | LOCKED (owner) |
| D4 | Kills score; survival credit + podium remain the dominant terms | LOCKED shape (owner); ratio tunable |
| D5 | `num_players` first-class, 2..16, everything derives from N | LOCKED (owner) |
| D6 | Time cap is the expected ending; total-order tiebreaks (alive > death tick > kills > damage > slot) | proposed |
| D7 | Combat: ranged-first single-life HP elimination on ctf projectile machinery | proposed |
| D8 | Territory/"presence" as cap-tiebreak feeder | deferred — only if playtests show passivity |
| D9 | Coworld canonical name (supersede uploaded `battle-royal` 0.2.0 vs fresh name) | open (owner) |
| D10 | Map ~5× ctf area; head-count size banding on top of that | LOCKED scale (owner); banding open |
| D11 | 20 HP spawn pool; hits deal 1–5; disengage-and-heal is a supported playbook | LOCKED shape (owner); numbers tunable — band amended 1–4 → 1–5 on the 2026-08-21 owner ruling (below) |
| D12 | Survival credit accrues at 1 pt per second alive (not a 30 s bucket) | LOCKED rate (owner); podium/kill magnitudes scale with the meter |
| D13 | Assists share kill credit so emergent teaming pays; no mechanical teams ever | LOCKED intent (owner); window/split tunable |
| D14 | Chat (`broadcast` + `dm`) is proximity-bounded to current vision/LOS; no arena-wide radio | LOCKED (owner) |
| D15 | Betrayal needs no speech act. Talk forms deals; a shot or a silent peel breaks them | LOCKED (owner) |
