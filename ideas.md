# Battle Royale climb

## Current state

- League: Battle Royale, Coworld `battleroyale` v0.1.14.
- Player: Stierlitz (`ply_607f17a2-3acf-405b-91fe-d12ef1001c00`), renamed
  in place from Andre von Houck with all ladder history preserved.
- Submitted policy: `andre-battleroyale:v15`.
- Upstream policy base: `a39eb196131ac0083506bb344130359de1c2d9c8`.
- Game update audit: The live v0.1.14 variant keeps generated huge maps and
  rotates seat ownership over the same fixed spawn pads using the episode
  seed. New death-site gun drops are dormant because `dropWeaponOnDeath` is
  false, and the new curated BR map pool is inactive because the variant still
  uses `mapPath: gen`. Winner and loot-ledger changes are instrumentation. No
  file under `players/`, including the example policy, changed from the
  submitted policy base through audited upstream `8363831`.

## Backlog

- Switch only the FFA doctrine from legacy to hunter.
- Add only a conservative hunter ring-safety margin.
- Allow only safe hunter pursuit against equal-HP opponents.
- Move only the hunter hold band deeper inside the safe radius.
- Prefer only a vulnerable hunter target over a closer strong opponent.
- Allow only safe hunter upgrades after initial arming.
- Persist only a safe hunter gun trip while its target is fog-hidden.
- Kite only visible nearby heavy-gun threats while preserving hunter fire.
- Strafe only laterally inward from nearby heavy-gun threats while preserving
  Hunter fire.
- Strafe only an armed Hunter laterally inward from nearby heavy-gun threats.
- Start only the hunter ring-retreat alarm one margin earlier.
- Add only a persistent tangential unstick burst during hunter ring retreat.
- Let only Hunter ring-unstick rays leave a falsely blocked coarse origin cell.
- Cycle only the existing Hunter ring-unstick candidates on repeated retries.
- Lengthen only the hunter ring-unstick clearance probe.
- Prefer only inward-diagonal hunter ring-unstick candidates before pure
  tangents.
- Add only a bounded low-health Hunter medkit detour.
- Prevent only an active Hunter ring-unstick burst from rearming itself.
- Scan only the Hunter's vision cone while holding without a visible target.
- Scan only while an unarmed Hunter holds without a visible target.
- Scan only while an armed Hunter holds without a visible target.
- Detour only an unarmed, unshielded Hunter to a nearby safe shield.
- Throw only already-carried Hunter grenades at visible safe-range targets.
- Extend only the hunter heavy-gun arm reach.
- Shorten only the hunter opening arm-trip deadline.
- Reduce only the hunter arm-trip detour radius.
- Prefer only the nearest safe opening gun over the highest-tier safe gun.
- Search toward the center only while an unarmed Hunter sees no safe gun.
- Compensate only armed Hunter aim for continuing movement during gun windup.
- Switch only the FFA doctrine from legacy to passive.
- Switch only the submitted hunter doctrine to passive.
- Switch only the submitted hunter doctrine to rush.
- Switch only the FFA doctrine from legacy to shade.
- Switch only the FFA doctrine from legacy to pact.
- Inspect hosted artifacts for avoidable unarmed time, ring damage, and
  target-contact gaps, then add one evidence-backed idea at a time.

## Trial log

### Trial 41: defer low-gun fire beyond the accurate range

- Idea: The newest exact-v15 hosted controls fire the low gun across its full
  700-pixel mechanical range. Replay extraction attributes only one hit in 17
  gun impacts beyond 500 pixels, versus 45 in 118 impacts below 500. The low
  gun is the only gun that can fire beyond the submitted mid/heavy 520-pixel
  cap, and it also has the slowest cooldown at 150 percent of the base. Hosted
  artifact extraction finds 197 visible low-gun samples between 520 and 700
  pixels, in six sustained windows across six of 10 files. That is 30.35
  percent of all 649 armed-visible samples, while extending mid/heavy range
  would affect only eight samples in one file. Defer low-gun fire until the
  target reaches the accurate 520-pixel band so a long miss cannot consume
  the cooldown needed for a closer shot.
- Change: Only for the default Hunter carrying a low gun, cap firing at 520
  pixels instead of the mechanical 700. Movement, target selection, pursuit,
  aim, low-gun damage and cooldown, mid/heavy firing, gun acquisition, items,
  ring behavior, Pact, every other doctrine, and all submitted v15 settings
  are unchanged. A visible low-gun target in the withheld 520-to-700 interval
  emits reason `low_gun_wait`.
- Isolation: `nim check`, the doctrine source-contract suite, the hosted
  fire-opportunity extractor, and the Linux amd64 production build pass.
  Production startup reports `ffaHunterLowGunFireRange=520.0` while retaining
  Hunter, the submitted 0.85 passive band, 240-pixel arm cap, 80-pixel safety
  margin, 60-tick ring unstick, and every other printed v15 setting. Hosted
  candidate branch confirmation is pending; replay and artifact opportunity
  counts are behavior evidence only, never score.
- Artifact: Local Linux amd64 `andre-battleroyale:candidate-41`, command
  `/bin/baseline`, digest
  `sha256:19e3111c091abe00c8c86f33656c5fb699b68636a94457536e07808309cae490`.
  Uploaded unsubmitted as main candidate `andre-battleroyale:v42` and immutable
  XP candidate `andre-trial-41:v1` after source commit `d2cc3d5` was pushed.
- XP id: Initial ten-episode control
  `xreq_d4f9a9ec-55bf-400c-9b50-2aca1da2c6ff`; initial ten-episode candidate
  `xreq_130cee1e-dd48-44b2-9c65-23b41b9fc195`.
- Opponents: At freeze our player is #17 at 1377.34 MRR. The nearest three
  unique other players are softmaxwell (`Picasso:v63`, 1384.90), David Greis
  (`Battle Royale Baseline:v1`, 1348.84), and NanosaurusX (`nancy-br:v1`,
  1407.58), in that fixed order for both arms. Each champion was verified on
  its live player page.
- Verdict: Pending hosted statistical comparison. Champion
  `andre-battleroyale:v15` remains submitted unless this candidate wins
  significantly.

### Trial 40: orbit the submitted hunter hold band

- Idea: The newest exact-v15 field produces 17,996 passive-hold ticks while
  replay attribution records nine deaths in 10 episodes, including four to
  mid guns. The hold-motion extractor finds 1,515 sampled passive holds across
  all 10 hosted files, and every one sends a zero movement mask. Across the
  preceding two exact-control fields, all 3,393 additional sampled holds also
  send zero movement. In the newest field, 88.53 percent of consecutive hold
  samples move less than 12 pixels per half-second sample. The submitted
  radial target collapses onto the Hunter's current position once it reaches
  the 0.85 band, leaving it stationary against unseen attackers. Preserve the
  proven survival radius but move tangentially along it. This is distinct from
  rejected band-depth changes, turret-only scans, and reactive threat jinks.
- Change: Only for the default Hunter's normal passive-hold fallback, replace
  its same-bearing radial target with a continuously advancing tangential
  target at the exact submitted 0.85 radius. Even and odd seats orbit opposite
  directions, with a fixed 0.50 tangent lead, to balance map orientation.
  Existing ring safety, persistent ring unstick, gun trips, pursuit, late
  close, target selection, aim and firing after contact, items, Pact, all
  other doctrines, and every numeric v15 setting are unchanged. Active
  fallback decisions emit phase `HUNTER_ORBIT`, objective `hunter_orbit`,
  action `orbit_band`, and reason `orbit_hold`.
- Isolation: `nim check`, the doctrine source-contract suite, the hosted
  hold-motion extractor, and the Linux amd64 production build pass. Production
  startup reports `ffaHunterOrbit=true` and `ffaHunterOrbitLead=0.5` while
  preserving the submitted 0.85 passive band, 240-pixel arm cap, 60-tick ring
  unstick, and every other printed v15 setting. All 10 initial hosted candidate
  artifacts are valid and contain 21,710 `hunter_orbit` objective and
  `orbit_band` action ticks, so the branch fired in every file. On the exact
  field, candidate band samples move 13.89 pixels per half-second on average
  versus 6.74 in control, while 61.22 percent versus 86.13 percent move less
  than 12 pixels. This confirms increased movement; diagnostics are never
  score.
- Artifact: Local Linux amd64 `andre-battleroyale:candidate-40`, command
  `/bin/baseline`, digest
  `sha256:b30f9ed7f4833ee0159a4c81661d2b44a73e2d54c9b1914f916e30466523471f`.
  Uploaded unsubmitted as main candidate `andre-battleroyale:v41` and immutable
  XP candidate `andre-trial-40:v1` after source commit `b84399a` was pushed.
- XP id: Initial ten-episode control
  `xreq_0b54e8df-22b2-4188-87ee-45dc15a7771e`; initial ten-episode candidate
  `xreq_05f03485-bc0a-4099-99e5-5cd0f032fb90`. The exact same-field
  20-episode extension is control
  `xreq_c58aaf04-5f8e-4d8b-bcad-da1e9dc1af84` and candidate
  `xreq_8d819d6b-df35-4bb2-9b4c-0bd654783756`.
- Opponents: At freeze Stierlitz is #17 at 1368.61 MRR. The nearest three
  unique other players are Kenny Sheftel (`kenshef-my-player:v1`, 1365.71),
  NanosaurusX (`nancy-br:v1`, 1356.78), and sivannn
  (`sivan-br-ringsurfer:v1`, 1381.08), in that fixed order for both arms.
- Verdict: Revert. The initial exact ten-per-arm comparison was positive but
  inconclusive: control 181.70, candidate 208.80, delta +27.10, Welch 95
  percent CI [-18.6641, 72.8641], p=0.228944. After the exact same-field
  extension, all 30 hosted episodes per arm give control 196.3000 and
  candidate 175.6667, delta -20.6333, 95 percent CI [-52.7356, 11.4689],
  Welch p=0.203344. The branch is active but the extended score is
  inconclusive and directionally worse, so restore the exact submitted v15
  source. `andre-battleroyale:v41` remains uploaded but unsubmitted and
  `andre-battleroyale:v15` remains champion.

### Trial 39: inward fallback band only while unarmed

- Idea: The newest 10 exact-v15 controls on live Coworld v0.1.14 put
  Stierlitz at a 731.40-pixel mean early radius and first gun tick 1214.71.
  The exact field opponents average 605.01 pixels and first gun tick 897.43.
  Scaling the submitted 0.85 band by that radial ratio gives 0.70. Unlike
  Trial 6's 0.60 band for every Hunter state or Trial 36's unarmed movement
  all the way to center, test a moderate inward band only during the unarmed
  fallback. The dedicated hosted-artifact extractor finds 825 submitted
  unarmed fallback samples in 29 windows across all 10 newest files, plus
  1,421 samples in 86 windows across all 10 preceding files. This is much
  broader than extending mid/heavy fire from 520 to its 1050-pixel mechanical
  range, which changes one sampled opportunity in the same preceding 10 files
  and none in the newest 10. The fresh XP metadata confirms live v0.1.14, and
  fetched upstream `origin/main` remains `8363831`, so the mechanics and
  example policy have not changed since the recorded audit.
- Change: Only for the default Hunter while unarmed, ring-safe, not pursuing,
  without a valid committed gun trip, and without a newly eligible gun, use a
  0.70 fallback band instead of the submitted 0.85 passive band. Armed
  holding remains exactly 0.85. Ring safety, gun selection and trip behavior,
  four-player late close, firing, pursuit, target selection, items, Pact, all
  other doctrines, and every other setting are unchanged. Active decisions
  emit phase `HUNTER_UNARMED`, objective `unarmed_band`, action and reason
  `hold_unarmed_band`.
- Isolation: `nim check`, the doctrine source-contract suite, the unarmed-hold
  hosted-artifact extractor, and the Linux amd64 production build pass.
  Production startup reports `ffaHunterUnarmedBand=0.7` while preserving the
  submitted `ffaPassiveBand=0.85`, 240-pixel arm cap, 60-tick ring unstick,
  and all other printed v15 settings. All 10 hosted candidate artifacts are
  valid and record 9,926 `unarmed_band` objective ticks, 9,926
  `hold_unarmed_band` action ticks, and 832 sampled 0.70-band decisions versus
  zero in exact control, proving the branch fired. These diagnostics are never
  score.
- Artifact: Local Linux amd64 `andre-battleroyale:candidate-39`, command
  `/bin/baseline`, digest
  `sha256:49df8f5f9872ea982b684979c0f874655a72886abdcec9049894d1e8bca96228`.
  Uploaded unsubmitted as main candidate `andre-battleroyale:v40` and immutable
  XP candidate `andre-trial-39:v1` after source commit `2726950` was pushed.
- XP id: Initial ten-episode control
  `xreq_1c75ccc6-53fc-483b-8305-dec3f5902b36`; initial ten-episode candidate
  `xreq_18a3f482-2f12-48c1-98cc-223ac92e7f09`.
- Opponents: At freeze Stierlitz is #13 at 1416.56 MRR. The nearest three
  unique other players are softmaxwell (`Picasso:v63`, 1413.97), sivannn
  (`sivan-br-ringsurfer:v1`, 1412.24), and Aaron (`aaln-br-hunter:v2`,
  1443.10), in that fixed order for both arms.
- Verdict: Revert. The exact ten-per-arm hosted comparison gives control
  128.70 and candidate 129.40, delta +0.70, Welch 95 percent CI
  [-73.2705, 74.6705], p=0.984349. The active mechanism is statistically
  indistinguishable from zero, so do not spend an extension on it. Restore the
  exact submitted v15 source. `andre-battleroyale:v15` remains champion and
  `andre-battleroyale:v40` remains uploaded but unsubmitted.

### Trial 38: pursue an equal-health armed opponent

- Idea: The newest 30 exact-v15 Coworld v0.1.14 controls show that weapon
  accuracy is not the primary gap. Stierlitz lands 53.04 percent of shots but
  averages only 0.20 kills and 10.83 damage, versus aosgoods at 0.97 kills and
  23.30 damage and softmaxwell at 0.90 kills and 30.83 damage. Replay
  resimulation finds 24,338 armed Hunter ticks and 6,194 ticks with a visible
  target. The submitted weak-target pursuit qualifies for 2,540 ticks. An
  equal-health armed target that passes the unchanged solo, HP, and ring gates
  adds 2,315 ticks across 85 windows in 15 of 30 files. Trial 5 saw zero
  hosted activations on its older field, so it never measured this strategy;
  the current field now provides direct coverage. By comparison, ignoring the
  gun opponent-lead veto changes only seven files, and longer gun reach changes
  four, so those lower-coverage arming ideas are rejected before XP.
- Change: Only for the default Hunter, allow its existing armed pursuit when
  the nearest visible armed opponent has equal HP. The submitted six-HP floor,
  300-pixel support rejection, ring-safe target gate, weak-target pursuit,
  target selection, firing, arming, navigation, items, and every other
  doctrine are unchanged. Active samples emit reason `pursue_equal`.
- Isolation: `nim check`, the doctrine source-contract suite, the pursuit
  replay extractor, and the Linux amd64 production build pass. Production
  startup reports `ffaHunterPursueEqual=true` while preserving the submitted
  six-HP floor, 300-pixel support radius, 240-pixel arm cap, 60-tick ring
  unstick, and 0.85 hold band. Replay counterfactual coverage is behavior
  evidence only, never score. The ten hosted candidate artifacts contain zero
  `pursue_equal` samples, so the new branch did not activate on this XP field.
- Artifact: Local Linux amd64 `andre-battleroyale:candidate-38`, command
  `/bin/baseline`, digest
  `sha256:84b427cdcd4273f3bf853716373ff6396088a0c7a531ce6e7429f4271633c323`.
  Uploaded unsubmitted as main candidate `andre-battleroyale:v39` and immutable
  XP candidate `andre-trial-38:v1` after source commit `e13ed5f` was pushed.
- XP id: Initial ten-episode control
  `xreq_0f546494-ddd3-47d5-9855-e51a031bf237`; initial ten-episode candidate
  `xreq_3979f444-86ca-4c3f-94c6-44ffe49b6455`.
- Opponents: Live champion rating 1455.79 at freeze. The exact nearest three
  unique other players are Aaron (`aaln-br-hunter:v2`, 1458.92), richard
  (`co-gas-battleroyale-baseline-richard:v3`, 1449.48), and softmaxwell
  (`Picasso:v63`, 1472.27), in that fixed order for both arms.
- Verdict: Revert. The exact ten-per-arm hosted comparison gives control
  205.70 and candidate 151.00, delta -54.70, Welch 95 percent CI
  [-177.7809, 68.3809], p=0.355953. This is inconclusive and directionally
  poor, and hosted artifacts show the changed branch never fired. Do not spend
  an extension on a candidate that was behaviorally inactive; restore the
  exact submitted v15 source. `andre-battleroyale:v15` remains champion and
  `andre-battleroyale:v39` remains uploaded but unsubmitted.

### Trial 37: compensate armed hunter aim for own movement

- Idea: Replay-backed extraction over the newest 50 exact-v15 controls finds
  339 attributable gun releases. The submitted target lead accounts for enemy
  motion but locks aim before a five-tick firing windup while the shooter keeps
  moving. Submitted mean release-time heading error is 2.07 brads. An online
  counterfactual using only the Hunter's previous-frame velocity lowers it to
  1.93 brads and improves 21.83 percent of attributable releases. The oracle
  using actual future displacement reaches 1.84 brads, so most of the
  available own-motion correction is predictable without changing navigation.
  In the same controls, extending mid/heavy opening-gun reach from 240 to 320
  pixels would alter only five ticks in one of 20 newest files, and a visible
  safe medkit within 180 pixels occurs in only one file; those lower-coverage
  ideas are rejected before XP.
- Change: Only for the default armed Hunter with a visible target, outside
  ring retreat, compensate the already-predicted target point by the Hunter's
  measured previous-frame velocity over the five-tick gun windup. Apply the
  correction only while measured velocity remains plausible and points toward
  the unchanged navigation target. Target selection, enemy-motion lead,
  trigger tolerance, navigation, ring behavior, arming, pursuit, items, hold
  band, and every non-Hunter doctrine are unchanged. Active samples emit
  `aim_own_motion`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. The exhaustive suite stayed green through the
  engine, manifest, roster, client, and map-editor service suites before its
  long generated-map validation shard was stopped. Production startup reports
  `ffaHunterOwnMotionAim=true` while retaining Hunter, the 0.85 hold band,
  240-pixel arm cap, and 60-tick ring unstick. All 10 initial hosted artifacts
  per arm are valid. Candidate artifacts record 104 `aim_own_motion` action
  samples versus zero in exact control, so the isolated branch fired. Replay
  diagnostics and artifact coverage are behavior evidence only, never score.
- Artifact: Local linux/amd64 `andre-battleroyale:candidate-37`, digest
  `sha256:09eb7b21347785d69e68788a131e1030bde8f8a81ff9611ddaa0497743a5da72`.
  Uploaded unsubmitted as `andre-battleroyale:v38`; immutable candidate is
  `andre-trial-37:v1`. Exact submitted control is `andre-battleroyale:v15`.
- XP id: Exact submitted control
  `xreq_794a18a6-23a1-4e79-94cb-cab0fe795a48` and candidate
  `xreq_51cb4717-324e-44be-bbb7-2c112d665bd5`, both requested at 10 hosted
  episodes on Coworld v0.1.14. The 20-per-arm exact same-field extension is
  control `xreq_99ee82fa-4249-46c3-8731-5736406864af` and candidate
  `xreq_729732fe-07e7-4173-9d7a-bba7941b67ad`.
- Opponents: Frozen outside-top-three field at request creation: Andre #11 at
  1446.11 MMR versus nearest unique other players aosgoods at 1437.96
  (`eatth-battleroyale-decision-stack-v29:v1`), sivannn at 1432.19
  (`sivan-br-ringsurfer:v1`), and softmaxwell at 1417.39 (`Picasso:v63`).
  Both arms use this exact roster and ordering.
- Verdict: Revert. The initial 10-per-arm result was control 144.50 versus
  candidate 160.60, difference +16.1000, 95 percent Welch CI [-40.9430,
  73.1430], p=0.557337. Across all 30 hosted episodes per arm, exact control
  mean is 139.7000 and candidate mean is 152.9000, difference +13.2000, 95
  percent CI [-24.7615, 51.1615], Welch p=0.489126. The dashboard confirms all
  30 candidate episodes, mean 152.9 and 43 percent +/- 10 percent. The active
  change remains inconclusive after extension and its effect is too small
  relative to variance to justify a much larger field. Exact v15 behavior was
  restored; `andre-battleroyale:v38` stays uploaded but unsubmitted, and
  champion `andre-battleroyale:v15` remains live.

### Trial 36: center search while an unarmed hunter sees no gun

- Idea: Same-field replay extraction from the newest 10 exact-v15 Trial 35
  controls shows Andre scoring 179.00 while aosgoods scores 201.80 and richard
  scores 200.40. Andre's mean radius during the first 90 seconds is 699.93
  pixels and only 38.59 percent of alive samples are within 480 pixels of the
  ring center, versus 310.93 and 92.03 percent for aosgoods and 568.68 and
  52.61 percent for richard. Andre's first gun arrives at tick 1192.57, versus
  962.00 and 917.62. First-gun pickup radii are 513.25, 398.85, and 696.22,
  respectively, so the shared signal is active inward discovery rather than a
  fixed pickup radius. The submitted fallback instead holds the outer 0.85
  band whenever no eligible gun is currently visible.
- Change: Only for the default Hunter while unarmed, outside ring safety and
  the existing four-player endgame, with no valid committed gun trip and no
  newly visible safe gun inside the submitted 240-pixel detour cap, navigate
  toward the ring center instead of the submitted 0.85 passive band. A visible
  eligible gun still takes priority. The exact submitted ring safety, late
  close, gun selection and trip rules, armed movement, pursuit, combat,
  firing, items, and all other doctrines are unchanged. Active fallback
  samples emit `center_search` and `search_center_gun`.
- Isolation: The doctrine source-contract suite and `nim check` pass. The
  Linux amd64 production startup reports `ffaHunterCenterSearch=true` while
  preserving the submitted `ffaPassiveBand=0.85`, 240-pixel arm cap, 60-tick
  ring unstick, and all other v15 settings. All 10 hosted artifacts per arm
  are valid. Candidate records 4,834 `search_center_gun` samples versus zero
  in exact control, and candidate sampled armed fraction is 0.7594 versus
  0.3106 in control, so the changed branch fired and altered the intended
  state. These are coverage diagnostics, not score.
- Artifact: Local linux/amd64 `andre-battleroyale:candidate-36`, digest
  `sha256:e886c53329ea131ea697f11fb75bb6487e67f0377d74674db94541c35171160f`.
  Uploaded unsubmitted as `andre-battleroyale:v37`; exact v15 control and
  candidate clones are `andre-trial-36:v1` and `andre-trial-36:v2`.
- XP id: Baseline `xreq_36c71215-03cf-41ee-bdf8-48a6a60f64fc` and candidate
  `xreq_a4758084-920b-4769-ab3a-2afc6d3cc400`, both requested at 10 hosted
  episodes. The 20-per-arm exact same-field extension is baseline
  `xreq_f88fc756-e8a3-4064-bb60-a44aedfec217` and candidate
  `xreq_d267aece-f852-4d9e-afda-fe34d5c59fd9`.
- Opponents: Frozen outside-top-three field at request creation: Andre #14 at
  1414.54 MMR versus nearest unique other players ravidear5-code at 1415.51
  (`shade-doctrine-v1:v1`), NishadIota at 1370.38
  (`nishad-battleroyale-baseline:v1`), and softmaxwell at 1370.00
  (`Picasso:v63`). Both arms use this exact roster and ordering.
- Verdict: Revert. Both initial exact requests and both extensions completed
  without failure. The initial 10-per-arm comparison was control 217.00 versus
  candidate 190.10, difference -26.9000, 95 percent Welch CI [-112.0643,
  58.2643], p=0.514183. Exact replay extraction found candidate first gun tick
  625.11 versus 1016.20, 1.10 versus 0.20 kills, and placement 1.80 versus
  1.90, while every roster member had materially shorter survival in the
  candidate request, so the exact field was extended. Across all 30 hosted
  episodes per arm, control mean is 167.0333 and candidate mean is 144.0000,
  difference -23.0333, 95 percent CI [-72.0013, 25.9347], Welch p=0.350256.
  The dashboard reports the same 167.03 versus 144.00. The active mechanism
  remains inconclusive and trends worse after extension, so center search is
  rejected. Working source is exact v15; `andre-battleroyale:v37` remains
  uploaded but unsubmitted, and champion `andre-battleroyale:v15` remains
  live.

### Trial 35: pixel-accurate hunter ring-unstick clearance

- Idea: The newest 10 exact v15 controls contain two ring-like deaths. Both
  spend all 20 final retreat samples in `ring_unstick`, sustain 19 ring hits,
  and record zero path length or displacement. Replay-backed Nim extraction
  finds a falsely blocked coarse origin in 200 of 286 unstick samples while
  the actual player footprint is valid in every sample. At every one of the
  286 positions, at least one real movement octant is clear for 32 pixels.
  In one fatal episode the submitted `ButtonUp` fallback is blocked in all 88
  samples while right is clear in all 88; in the other, up is blocked in all
  101 while down-left and down are clear in all 101. Use the exact collision
  map already available to the policy instead of guessing from a rejected
  coarse origin cell.
- Change: Only for the default Hunter's existing ring-unstick direction
  selection, test the unchanged five candidates with pixel-accurate player-
  footprint clearance instead of the eight-pixel nav grid. Candidate order,
  32-pixel probe, preferred side, 20-frame stuck trigger, 60-tick burst,
  repeated rearming, normal ring retreat, combat, arming, hold band, and every
  non-Hunter behavior are unchanged. A burst whose selected movement bits
  differ from exact v15 emits `ring_unstick_fine_ray`.
- Isolation: `nim check` passes for the policy and replay extractor, the
  doctrine source-contract suite passes, and the Linux amd64 production build
  passes. Production startup reports `ffaHunterRingUnstickFineRay=true` while
  retaining Hunter, the 60-tick ring unstick, 240-pixel arm cap, 30-second arm
  deadline, 80-pixel arm safety margin, zero ring margin, and 0.85 hold band.
  Exact replay reconstruction predicts different movement bits in 97 of 286
  newest-control unstick samples, reducing the coarse selector's 203 fallbacks
  to 106 without changing its five candidate directions. Eighty-four of those
  predicted differences occur in one fatal zero-motion ring episode. This is
  pre-CPUX behavior isolation, not score; hosted branch coverage is pending.
- Artifact: Local linux/amd64 `andre-battleroyale:candidate-35`, digest
  `sha256:10771195b95d74a81c4eebd32e5592ac78a1b87a3e4f900fd246292b29777c3f`.
  Uploaded unsubmitted as `andre-battleroyale:v36`; exact v15 control and
  candidate images are `andre-trial-35:v1` and `andre-trial-35:v2`.
- XP id: Baseline `xreq_d873f708-a1bb-442a-a5c9-ae671926af6c` and candidate
  `xreq_322bf754-9512-45a7-8f97-efdbf310584c`, both complete at 10 hosted
  episodes with zero failures.
- Opponents: Frozen outside-top-three field at request creation: Andre #10 at
  1493.11 MMR versus nearest unique other players aosgoods at 1490.81
  (`eatth-battleroyale-decision-stack-v29:v1`), richard at 1505.15
  (`co-gas-battleroyale-baseline-richard:v3`), and relh at 1532.00
  (`co-gas-battleroyale-baseline-relhalpha:v7`). Both arms use this exact
  roster and ordering.
- Verdict: Revert. All 10 hosted artifacts per arm are valid. The candidate
  records 422 `ring_unstick_fine_ray` ticks versus zero in exact control, so
  the isolated branch fired. Baseline mean is 179.0000 versus candidate
  180.0000, difference +1.0000, Welch 95 percent CI [-42.9579, 44.9579],
  p=0.962187. The completed hosted result is decisively inconclusive and the
  point estimate is negligible, so it does not merit a same-field extension.
  Exact v15 behavior was restored; `andre-battleroyale:v36` remains uploaded
  but unsubmitted.

### Trial 34: throw already-carried grenades at safe visible targets

- Idea: Replay-backed Nim extraction over the newest 10 exact v15 controls
  finds three incidental grenade pickups in three files and zero throws. The
  Hunter carried a grenade for 443 replay ticks and 23 artifact samples; 21
  carried samples had a visible target and 19 were in safe throw range. FFA
  direct grenade damage is four HP, one fifth of the ordinary 20-HP pool and
  more than a low- or mid-tier gun hit. Isolate the unused weapon without
  changing how grenades are acquired.
- Change: Only for the default Hunter that already carries a grenade, charge
  and throw it at a visible target between the existing conservative 78-pixel
  self-safety floor and 240-pixel maximum range. The turret tracks the target
  during charge; seeing no target retains the last safe aim until release.
  Ring safety still owns navigation, and a charge already started may finish
  while retreating. Grenade pickup, navigation, arming, hold band, ring
  retreat, ring unstick, target selection, ordinary aim and firing, and every
  non-Hunter doctrine are unchanged. Active stages emit `aim_grenade`,
  `charge_grenade`, and `throw_grenade`.
- Isolation: `nim check` passes for the policy and grenade-opportunity
  extractor, and the doctrine source-contract suite and Linux amd64 production
  build pass. Production startup reports `ffaHunterGrenadeThrow=true` only in
  the candidate while retaining Hunter, the 60-tick ring unstick, 240-pixel
  arm cap, 30-second arm deadline, 80-pixel arm safety margin, zero ring
  margin, and 0.85 hold band. All 10 hosted artifacts and replays per arm are
  valid. Replay extraction finds two incidental candidate pickups followed by
  two grenade throws, versus one control pickup and zero throws. The candidate
  therefore exercised the isolated behavior; this coverage is not score.
- Artifact: Local linux/amd64 `andre-battleroyale:candidate-34`, digest
  `sha256:98b2e10c2b402e5627392a12e6fda57a37f37d95e639cc24923583f643ef2f7b`.
  Uploaded unsubmitted as `andre-battleroyale:v35`; immutable candidate
  `andre-trial-34:v1`; exact v15 control `andre-trial-34:v2`.
- XP id: Baseline `xreq_008e14ca-e63c-4bbc-a02c-5021fdc7097e` and candidate
  `xreq_ee2544d0-d76d-49c6-bd50-dcd5794f9156`, both requested at 10 hosted
  episodes.
- Opponents: Frozen outside-top-three field at request creation: Andre #14 at
  1382.71 MMR versus nearest unique other players ravidear5-code at 1382.25
  (`shade-doctrine-v1:v1`), Aaron at 1391.38 (`aaln-br-hunter:v2`), and
  aosgoods at 1365.67 (`eatth-battleroyale-decision-stack-v29:v1`). Both arms
  use this exact roster and ordering.
- Verdict: Revert. Baseline mean 184.3000 versus candidate 193.2000,
  difference +8.9000, Welch 95 percent CI [-64.0917, 81.8917], p=0.800684.
  The dashboard confirms 184.3 versus 193.2 and 60 versus 70 percent over the
  selected pairwise games, but the active change is far from significant and
  the interval is extremely wide. The weak evidence does not merit a large
  same-field extension. `andre-battleroyale:v35` remains uploaded but
  unsubmitted; champion `andre-battleroyale:v15` remains live.

### Trial 33: reactive turret scan after unseen damage

- Idea: The newest 10 exact v15 control artifacts record 69 non-ring sampled
  HP drops with zero opponent visibility. All four deaths occur while holding
  the passive band with zero visible opponents, including one heavy-gun and
  one two-damage terminal hit. Trial 32's damage-triggered navigation jink
  fired but trended worse, while broad proactive scans in Trials 24, 25, and
  30 were inconclusive. Preserve movement and scan only after evidence of an
  unseen attacker.
- Change: Only for the default Hunter, after actual HP loss with no visible
  opponent while existing ring safety is inactive, rotate the turret clockwise
  for 52 ticks, one full 256-brad revolution at the engine's five brads per
  tick, and emit `scan_damage`. Navigation, ring retreat, ring unstick, arming,
  hold band, target selection, aim and fire after contact, weapons, and every
  non-Hunter doctrine are unchanged. Seeing a target immediately restores the
  existing combat aim; ring safety suppresses the scan.
- Isolation: `nim check` and the doctrine source-contract suite pass.
  Production-image extraction confirms only the candidate adds
  `ffaHunterDamageScan=true` and `ffaHunterDamageScanTicks=52`; candidate and
  exact control retain Hunter, the 60-tick ring unstick, 240-pixel arm cap,
  30-second arm deadline, 80-pixel safety margin, zero ring margin, and 0.85
  hold band. All 10 hosted artifacts per arm are valid. The candidate records
  485 `scan_damage` ticks versus zero in control, so the isolated branch
  fired; artifact coverage is not score.
- Artifact: Local linux/amd64 `andre-battleroyale:candidate-33`, digest
  `sha256:8f833b8ff3b614d451123783a80986ee51b346373fa20e552027955bfd326f43`.
  Uploaded unsubmitted as `andre-battleroyale:v34`; immutable candidate
  `andre-trial-33:v1`; exact v15 control `andre-trial-33:v2`.
- XP id: Baseline `xreq_98135c80-02c9-4178-8d20-a6f71ac1fd1a` and candidate
  `xreq_18b73bdc-0401-4547-8913-4c8485181975`, both complete at 10 hosted
  episodes with zero failures.
- Opponents: Frozen outside-top-three field at request creation: Andre #10 at
  1547.12 MMR versus nearest unique other players softmaxwell at 1599.14
  (`Picasso:v63`), Ryan Schiller at 1602.50
  (`ryanschiller-br-v95edge:v1`), and richard at 1490.52
  (`co-gas-battleroyale-baseline-richard:v3`). Both arms use this exact roster
  and ordering.
- Verdict: Revert. Baseline mean 159.1000 versus candidate 182.4000,
  difference +23.3000, Welch 95 percent CI [-73.4221, 120.0221], p=0.606962.
  The active change is inconclusive with an extremely wide interval and weak
  evidence, so it is not a keep and does not merit a large same-field
  extension. `andre-battleroyale:v34` remains uploaded but unsubmitted;
  champion `andre-battleroyale:v15` remains live.

### Trial 32: reactive inward jink after non-ring damage

- Idea: A Nim extractor over 40 exact v15 controls from Trials 28 through 31
  finds 411 sampled HP drops. Existing ring safety identifies and excludes
  357 ring-associated drops, leaving 54 active non-ring damage samples. The
  newest exact replay field attributes five of eight deaths to guns, including
  four heavy-gun deaths. Proactive heavy-threat movement in Trials 10, 27,
  and 28 changed too much movement before a hit and failed; use actual HP loss
  as a narrow trigger instead.
- Change: Only for the default Hunter, after actual HP loss while existing ring
  safety is inactive, navigate 120 pixels inward for 24 ticks and emit
  `jink_damage`. Target selection, aim, firing, weapons, arming, pursuit, hold
  band, ring retreat, ring unstick, and every non-Hunter doctrine are
  unchanged. Ring safety remains outer priority and suppresses the jink.
- Isolation: `nim check` and the doctrine suite pass. Production-image startup
  extraction confirms the candidate alone has
  `ffaHunterDamageJink=true`, `ffaHunterDamageJinkTicks=24`, and
  `ffaHunterDamageJinkDistance=120.0`; all existing v15 doctrine settings
  match the exact control. All 10 hosted artifacts per arm are valid. The
  candidate records 1,448 `jink_damage` ticks versus zero in control, so the
  isolated branch fired materially; artifact coverage is not score.
- Artifact: Local linux/amd64 `andre-battleroyale:candidate-32`, digest
  `sha256:179168ae02975e384c5aa5543d96436f3b2759d7194724744f3004d61bfa2c60`.
  Uploaded unsubmitted as `andre-battleroyale:v33`; immutable candidate
  `andre-trial-32:v1`; exact v15 control `andre-trial-32:v2`.
- XP id: Baseline `xreq_e5b09b07-e2c8-4826-9fe0-219896123f05` and candidate
  `xreq_e1efe6a4-d5dc-4b6c-a813-30bd67df0cc3`, both complete at 10 hosted
  episodes with zero failures.
- Opponents: Frozen outside-top-three field at request creation: Andre #17 at
  1348.76 MMR versus nearest unique other players David Greis at 1356.82
  (`Battle Royale Baseline:v1`), Aaron at 1386.03 (`aaln-br-hunter:v2`), and
  sivannn at 1405.80 (`sivan-br-ringsurfer:v1`). Both arms use this exact
  roster and ordering.
- Verdict: Revert. Baseline mean 188.5000 versus candidate 170.2000,
  difference -18.3000, Welch 95 percent CI [-103.7736, 67.1736], p=0.652011.
  This is inconclusive with a negative point estimate, so it is not a keep and
  does not merit a same-field extension. `andre-battleroyale:v33` remains
  uploaded but unsubmitted; champion `andre-battleroyale:v15` remains live.

### Trial 31: nearby safe shield for an unarmed hunter

- Idea: Across the newest 30 exact v15 controls from Trials 28 through 30,
  replay resimulation finds 22 deaths without a shield and only three
  incidental shield pickups. A conservative Nim extractor counts only
  present shields at least 80 pixels inside the ring and rejects a shield if
  any living opponent is closer. It finds 17 unarmed opportunity windows in
  eight of 30 files within 160 pixels, totaling 1,805 ticks. The submitted
  Hunter ignores shields even while unarmed, despite a shield absorbing three
  damage before base HP.
- Change: Only for the default Hunter while unarmed and not already carrying
  a shield, detour to the nearest protocol-visible shield within 160 pixels
  when it is inside the existing 80-pixel safety margin and no visible
  opponent is closer to it. Ring safety still has outer priority. Gun
  selection, combat, firing, pursuit, hold band, ring unstick, armed movement,
  and every non-Hunter doctrine are unchanged. Active movement emits
  `shield_trip` and `move_shield`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterShieldDetour=true` and a 160-pixel radius only in the candidate,
  while candidate and exact submitted control retain Hunter, the 60-tick
  ring unstick, 240-pixel arm cap, 30-second arm-trip cap, 80-pixel safety
  margin, zero ring margin, and 0.85 hold band. Hosted startup logs confirm
  the candidate flag and radius. Behavioral coverage failed: all 10 candidate
  artifacts are valid but contain zero `shield_trip` and `move_shield`
  actions, as do all 10 controls. The frozen field did not expose a
  qualifying protocol-visible shield to the candidate.
- Artifact: `andre-battleroyale:candidate-31`, Linux amd64 image digest
  `sha256:7f4e0ca0152cc0531a649ed5f341c018c4ade2f6230650f3cbd98e04396de8e2`.
  Uploaded unsubmitted as `andre-battleroyale:v32`; exact candidate and
  submitted-control images are `andre-trial-31:v1` and
  `andre-trial-31:v2`.
- XP id: Baseline `xreq_2d0e82c7-858d-4898-b052-7833949663a6` and candidate
  `xreq_b597e2c1-7889-4eb7-a945-ffde406f9f83`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #17 at 1348.76. The nearest other
  players are David Greis (`Battle Royale Baseline:v1`, 1356.82), Aaron
  (`aaln-br-hunter:v2`, 1386.03), and sivannn
  (`sivan-br-ringsurfer:v1`, 1405.80).
- Verdict: Reverted. All 10 episodes per arm completed without failure. The
  exact submitted control scores 167.0000 and the candidate 164.7000, a
  -2.3000 delta with 95% CI [-58.8481, 54.2481] and Welch p=0.932607. The
  result is inconclusive and the changed branch was inactive, so shield
  detouring was removed without an extension. `andre-battleroyale:v32`
  remains uploaded but unsubmitted; the submitted champion remains v15.

### Trial 30: scan only while armed hunter holds

- Idea: Broad hold scanning in Trial 24 increased fight ticks from 363 to 670
  and had a +24.90 hosted score trend, while the 30-episode unarmed-only scan
  in Trial 25 finished at only +4.57. The newest exact v15 control contains
  104 armed-visible samples but only 70 fight ticks, and a dedicated extractor
  finds zero unused mid/heavy targets beyond the current 520-pixel fire gate.
  Isolate better armed contact acquisition without changing movement, weapon
  reach, or unarmed loot discovery.
- Change: Only for the default Hunter while armed, holding with action
  `hold_band`, and seeing no opponent, rotate the turret clockwise
  continuously and emit `scan_armed_band`. Unarmed holds, movement, band
  location, ring retreat, unstick, arming, target selection, pursuit, aim
  after contact, firing, and every non-Hunter behavior are unchanged.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterArmedScanBand=true` only in the candidate, while candidate and
  exact submitted control retain Hunter, the 60-tick ring unstick, 240-pixel
  arm cap, 30-second arm deadline, 80-pixel arm safety margin, zero ring
  margin, and 0.85 hold band. All 10 hosted candidate artifacts are valid and
  contain 3,519 `scan_armed_band` ticks versus zero in control, proving the
  isolated branch fired. Candidate artifacts contain 241 fight ticks versus
  182 in control, but only 0.2158 sampled armed fraction versus 0.3777 and five
  death events versus two. These diagnostics prove behavior, not score.
- Artifact: `andre-battleroyale:candidate-30`, Linux amd64 image digest
  `sha256:2bfb8e9166dac1d7c59d5a306fd1a25df64abbe9c352502effa1396fa8d66b2a`.
  Uploaded unsubmitted as `andre-battleroyale:v31`. Parallel immutable uploads
  assigned the candidate to `andre-trial-30:v1` and exact submitted control
  to `andre-trial-30:v2`; the manifests use those verified labels.
- XP id: Baseline
  `xreq_9b8f7e49-b9bb-4ca7-bd06-924b9fa7ab81`; candidate
  `xreq_f31d96d3-4b53-49d1-9227-8f25e7417b0f`. Both exact same-field
  requests have 10 episodes.
- Opponents: At field freeze Andre is #16 at 1342.34. The nearest other
  players are Kenny Sheftel (`kenshef-my-player:v1`, 1326.99), David Greis
  (`Battle Royale Baseline:v1`, 1302.89), and Aaron
  (`aaln-br-hunter:v2`, 1398.72).
- Verdict: Reverted. All 10 episodes per arm completed without failure. The
  exact submitted control scores 189.7000 and the candidate 185.7000, a
  -4.0000 delta with 95% CI [-68.6600, 60.6600] and Welch p=0.895977. The
  result is inconclusive and trends worse, so armed-only hold scanning was
  removed. `andre-battleroyale:v31` remains uploaded but unsubmitted; the
  submitted champion remains v15.

### Trial 29: cycle repeated hunter ring-unstick candidates

- Idea: After correcting the hosted ring extractor from 120 to the Coworld's
  actual 24 FPS, 50 recent exact v15 controls contain 10 ring-like deaths.
  Nine were completely stationary throughout the final 10 seconds, with all
  20 samples in `ring_unstick`. Trial 16's two-side retry alternation reduced
  fatal-retreat stationary steps from 96.7 to 13.7 percent and ring-like
  deaths from four to two, but remained inconclusive at 10 episodes per arm.
  Extend that real-motion feedback beyond the two tangents by cycling through
  the existing five clearance candidates on successive stuck retries.
- Change: During one continuous default-Hunter ring retreat, leave the first
  stuck-triggered unstick selection exactly submitted, then rotate which of
  the existing five candidates is checked first on each repeated stuck retry.
  The candidate vectors, their base order, 32-pixel probe, preferred initial
  side, 20-frame stuck trigger, 60-tick burst, ordinary ring retreat, arming,
  combat, hold band, and every non-Hunter behavior are unchanged. Repeated
  cycled bursts emit `ring_unstick_cycle`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterRingUnstickCycle=true` only in the candidate, while candidate and
  exact submitted control retain Hunter, the 60-tick ring unstick, 240-pixel
  arm cap, 30-second arm deadline, 80-pixel arm safety margin, zero ring
  margin, and 0.85 hold band. Across 10 hosted artifacts per arm, the
  candidate records 4,407 `ring_unstick_cycle` action ticks versus zero in
  the exact control, proving the repeated-retry change fired.
- Artifact: `andre-battleroyale:candidate-29`, Linux amd64 image digest
  `sha256:8d8e08ef68f4638d2d942a62655aad5dfc365c16bbeebee9982977062a670b74`.
  Uploaded unsubmitted as `andre-battleroyale:v30`; exact submitted control
  and candidate images are `andre-trial-29:v1` and `andre-trial-29:v2`.
- XP id: Baseline
  `xreq_b40e6899-f2bc-4de1-a3e4-24b9c5bd3ac3`; candidate
  `xreq_b25cbc13-95ac-4488-bda9-763f887b3cb4`. Both exact same-field
  requests have 10 episodes.
- Opponents: At field freeze Andre is #16 at 1396.80. The nearest other
  players are b4kng2dkg5-sudo (`starter-baseline:v1`, 1399.43), sivannn
  (`sivan-br-ringsurfer:v1`, 1422.78), and Kenny Sheftel
  (`kenshef-my-player:v1`, 1350.95).
- Verdict: Reverted. All 10 episodes per arm completed without failure. The
  exact submitted control scores 207.6000 and the candidate 159.1000, a
  -48.5000 delta with 95% CI [-101.1964, 4.1964] and Welch p=0.068826.
  Inconclusive is not a keep, and the candidate trends strongly worse while
  recording six death events versus one in control. `andre-battleroyale:v30`
  remains uploaded but unsubmitted; the submitted champion remains v15.

### Trial 28: armed-only inward heavy-gun strafe

- Idea: Trial 27 proved the lateral branch fired, but 15 of its 33 sampled
  heavy-threat decisions occurred while unarmed and the candidate's mean
  armed fraction fell from 0.5144 to 0.2116. At the same time, its hosted
  damage events fell from 131 to 88. Test whether limiting the same inward
  lateral response to already-armed Hunter states preserves opening weapon
  trips while retaining a possible combat benefit.
- Change: Only for an already-armed default Hunter, when a visible heavy-gun
  actor is within 400 pixels and existing ring safety is inactive, move 240
  pixels perpendicular to the threat bearing on the side whose target is
  closer to the arena center, then clamp it inside the existing 80-pixel safe
  margin. Unarmed movement, target selection, aim, firing, pursuit, arming,
  hold band, ring priority, 60-tick unstick, late close, and every non-Hunter
  doctrine are unchanged.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterArmedHeavyStrafe=true`, a 400-pixel range, and a 240-pixel step
  only in the candidate, while candidate and exact submitted control retain
  Hunter, the 60-tick ring unstick, 240-pixel arm cap, 30-second arm deadline,
  80-pixel arm safety margin, zero ring margin, and 0.85 hold band. Across 10
  hosted artifacts per arm, the candidate records 315
  `strafe_armed_heavy` action ticks and 26 sampled
  `armed_heavy_threat_lateral` decisions versus zero in the exact control,
  proving the isolated change fired.
- Artifact: `andre-battleroyale:candidate-28`, Linux amd64 image digest
  `sha256:a02830155c898f056151927bd9363259725bada140d0f24f545210a9215cf32d`.
  Uploaded unsubmitted as `andre-battleroyale:v29`; exact submitted control
  and candidate images are `andre-trial-28:v1` and `andre-trial-28:v2`.
- XP id: Baseline
  `xreq_2d9507eb-4ea9-4d5a-ad16-2b1fcc4d613f`; candidate
  `xreq_e71d18ce-9ffc-45cd-af8d-538eaf2da216`. Both exact same-field
  requests have 10 episodes.
- Opponents: At field freeze Andre is #15 at 1363.67. The nearest other
  players are sivannn (`sivan-br-ringsurfer:v1`, 1368.46), Kenny Sheftel
  (`kenshef-my-player:v1`, 1304.37), and b4kng2dkg5-sudo
  (`starter-baseline:v1`, 1429.78).
- Verdict: Reverted. All 10 episodes per arm completed without failure. The
  exact submitted control scores 182.5000 and the candidate 155.9000, a
  -26.6000 delta with 95% CI [-89.4252, 36.2252] and Welch p=0.373417.
  Inconclusive is not a keep. `andre-battleroyale:v29` remains uploaded but
  unsubmitted; the submitted champion remains v15.

### Trial 27: inward lateral heavy-gun strafe

- Idea: Exact replay attribution across the newest 20 submitted-v15 controls
  finds 17 deaths: nine to heavy guns, four to the ring, two to mid guns, one
  to a fist, and one to spray. Trial 10's direct-away heavy evade fired for
  5,996 ticks but left non-ring deaths unchanged at 13 per arm and tripled
  ring deaths from three to nine; its final hosted delta was -5.4667, 95% CI
  [-41.1700, 30.2367]. Direct-away motion also preserves the attacker's
  bearing, offering little angular displacement against hitscan aim. Test a
  lateral dodge that explicitly chooses the inward side instead.
- Change: Only for the default Hunter, when a visible heavy-gun actor is
  within 400 pixels and existing ring safety is not active, move 240 pixels
  perpendicular to the threat bearing on the side whose target is closer to
  the arena center, then clamp it inside the existing 80-pixel safe margin.
  Target selection, aim, firing, pursuit, arming, hold band, ring priority,
  60-tick unstick, late close, and every non-Hunter doctrine are unchanged.
  Active movement emits `heavy_strafe`, `strafe_heavy`, and
  `heavy_threat_lateral`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterHeavyStrafe=true`, a 400-pixel range, and a 240-pixel step only in
  the candidate while candidate and exact submitted control retain Hunter,
  the 60-tick ring unstick, 240-pixel arm cap, 30-second arm deadline,
  80-pixel arm safety margin, zero ring margin, and 0.85 hold band. Across 10
  hosted artifacts per arm, the candidate records 432 `heavy_strafe` action
  ticks and 33 sampled `heavy_threat_lateral` decisions versus zero in the
  exact control, proving the isolated change fired.
- Artifact: `andre-battleroyale:candidate-27`, Linux amd64 image digest
  `sha256:0e134ff747b8791d50fb00ed5864c4595a951025589eb821fcd3dc57305a35d3`.
  Uploaded unsubmitted as `andre-battleroyale:v28`; exact submitted control
  and candidate images are `andre-trial-27:v1` and `andre-trial-27:v2`.
- XP id: Baseline
  `xreq_e7772554-d908-4a5b-8d20-4436f7d50b58`; candidate
  `xreq_f5777d41-7d0b-4e1b-bbcb-c0221eb0208e`. Both exact same-field
  requests have 10 episodes.
- Opponents: At field freeze Andre is #16 at 1368.83. The nearest other
  players are Kenny Sheftel (`kenshef-my-player:v1`, 1370.51), sivannn
  (`sivan-br-ringsurfer:v1`, 1378.78), and Aaron
  (`aaln-br-hunter:v2`, 1435.28).
- Verdict: Reverted. All 10 episodes per arm completed without failure. The
  exact submitted control scores 166.6000 and the candidate 144.6000, a
  -22.0000 delta with 95% CI [-98.9697, 54.9697] and Welch p=0.555268.
  Inconclusive is not a keep, and the candidate trends worse while reducing
  mean armed fraction from 0.5144 to 0.2116. `andre-battleroyale:v28` remains
  uploaded but unsubmitted; the submitted champion remains v15.

### Trial 26: skip a falsely blocked ring-unstick origin cell

- Idea: In the newest 20 exact v15 controls, two deaths followed 19 ring hits
  each and spent 99.5 percent of their final retreat samples in
  `ring_unstick`, with 99.0 percent stationary steps. A replay-backed Nim
  extractor reconstructed all 20 hosted maps and found 319 of 525 sampled
  unstick positions in a coarse eight-pixel nav cell marked blocked, across 12
  episodes, while the player's actual footprint was valid in every sample.
  The current clearance ray tests that false coarse origin before every
  direction, rejects all candidates, and falls back to fixed `ButtonUp`.
- Change: Only for the default Hunter's existing 32-pixel ring-unstick
  clearance ray, ignore the single coarse origin cell when it is marked
  blocked but the player is already occupying a valid actual position. Every
  later cell in the ray must remain walkable. Candidate order, probe length,
  preferred side, 20-frame trigger, 60-tick burst, ordinary ring retreat,
  arming, combat, hold band, and every other behavior are unchanged. Bursts
  that use the corrected origin semantics emit `ring_unstick_origin_clear`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterRingUnstickSkipBlockedOrigin=true` only in the candidate while
  candidate and exact submitted control retain Hunter, the 60-tick ring
  unstick, 240-pixel arm cap, 30-second arm deadline, 80-pixel arm safety
  margin, zero ring margin, and 0.85 hold band. Hosted branch coverage passed:
  all 10 candidate artifacts are valid and contain 506
  `ring_unstick_origin_clear` ticks, while all 10 controls contain zero.
  Candidate artifacts contain 1,501 ordinary `ring_unstick` ticks versus
  3,382 in control. These diagnostics prove the corrected branch fired; they
  are not score.
- Artifact: `andre-battleroyale:candidate-26`, Linux amd64 image digest
  `sha256:c1df0ac0f0c811018ead51fa42f650108c95f9bcf422f16e5f06878284b4186b`.
  Uploaded unsubmitted as `andre-battleroyale:v27`; exact submitted control
  and candidate images are `andre-trial-26:v1` and `andre-trial-26:v2`.
- XP id: Baseline `xreq_fcfcec1d-b7ac-4f07-8000-17f4ba845c15` and candidate
  `xreq_3be1ff00-6e8a-41f5-9a1e-bcdf323d0322`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #16 at 1369.43. The nearest other
  players are NanosaurusX (`nancy-br:v1`, 1404.98), sivannn
  (`sivan-br-ringsurfer:v1`, 1405.88), and David Greis
  (`Battle Royale Baseline:v1`, 1327.16).
- Verdict: Reverted. Baseline mean 209.30, candidate mean 194.70, difference
  -14.60, 95% CI [-128.3584, 99.1584], Welch p=0.782228. The active change is
  inconclusive and trends worse, so the submitted origin-cell semantics were
  restored. `andre-battleroyale:v27` remains uploaded but was not submitted.

### Trial 25: scan only while unarmed hunter holds

- Idea: Trial 24's broad hold scan was inconclusive, but its candidate started
  1.5 loot trips per episode versus 0.8 in control while also increasing
  engage ticks from 363 to 670. Restricting the same vision sweep to unarmed
  holds may preserve weapon discovery without changing armed hold visibility
  or inviting the extra armed contacts measured by the broad scan.
- Change: Only for the default Hunter while unarmed, holding with action
  `hold_band`, and seeing no opponent, rotate the turret clockwise continuously
  and emit `scan_unarmed_band`. Armed holds, movement, band location, ring
  retreat, unstick, arming selection, target selection, pursuit, aim after
  contact, firing, and every other behavior are unchanged.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports only the new
  `ffaHunterUnarmedScanBand=true` flag while retaining Hunter, the 60-tick ring
  unstick, 240-pixel arm cap, 30-second arm deadline, 80-pixel arm safety
  margin, zero ring margin, and 0.85 hold band. Hosted behavioral coverage is
  passed: all 10 candidate artifacts are valid and contain 7,216
  `scan_unarmed_band` ticks, while all 10 control artifacts contain zero.
  Candidate artifacts reached 42.05 percent sampled armed state versus 31.77
  percent in control, started 1.4 loot trips per episode versus 0.5, and
  recorded 152 engage ticks versus 100. These diagnostics prove the behavior
  fired; they are not score. All 20 extension candidate artifacts are also
  valid and contain 13,945 `scan_unarmed_band` ticks, while the 20 extension
  controls contain zero. Extension armed state is 51.50 percent in candidate
  versus 46.14 percent in control, with 1.1 versus 1.0 loot trips per episode
  and 915 versus 375 engage ticks. These remain coverage diagnostics only.
- Artifact: `andre-battleroyale:candidate-25`, Linux amd64 image digest
  `sha256:f506ee59d6487244430f84bc97a3ed6071d6f7a03dc1852366dd62598cb33162`.
  Uploaded unsubmitted as `andre-battleroyale:v26`; exact submitted control
  and candidate images are `andre-trial-25:v1` and `andre-trial-25:v2`.
- XP id: Baseline `xreq_081acbae-4435-43ef-9b3b-f6439227fefa` and candidate
  `xreq_da9cb010-0a79-494b-9c91-a24a0eb9e0e0`, 10 hosted episodes per arm.
  The exact same-field 20-episode extension is baseline
  `xreq_c9be6f0d-4e85-495b-b4c5-20fdfdf8e200` and candidate
  `xreq_b7a8fb0e-2c6a-41a1-b419-1cd57f73d740`.
- Opponents: At field freeze Andre is #13 at 1408.17. The nearest other
  players are sivannn (`sivan-br-ringsurfer:v1`, 1401.61), b4kng2dkg5-sudo
  (`starter-baseline:v1`, 1430.17), and softmaxwell
  (`Picasso:v63`, 1383.99).
- Verdict: Reverted. The initial 10 episodes per arm were inconclusive at
  +52.80, 95% CI [-10.0882, 115.6882], Welch p=0.094424. Across the exact
  same-field 30 episodes per arm, baseline mean is 144.3667 and candidate mean
  is 148.9333, difference +4.5667, 95% CI [-31.0363, 40.1696], Welch
  p=0.798101. The active change is conclusively unproven after extension, so
  the working source remains the submitted v15 behavior.
  `andre-battleroyale:v26` remains uploaded but was not submitted.

### Trial 24: scan while hunter holds the band

- Idea: Across the newest 40 exact submitted-control artifacts from Trials 20
  through 23, Hunter spends 95,069 action ticks holding its passive band but
  only 1,007 action ticks engaging. When no opponent is visible, FFA aim points
  at the navigation target, so a Hunter holding its band does not deliberately
  sweep the fog-of-war vision cone. A turret-only scan can find contacts while
  preserving the survival behavior that dominates the submitted policy.
- Change: Only for the default Hunter while its action is `hold_band` and no
  opponent is visible, rotate the turret clockwise continuously and emit
  `scan_band`. Movement, band location, ring retreat, unstick, arming, target
  selection, pursuit, aim after contact, firing, and every other behavior are
  unchanged.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports only the new
  `ffaHunterScanBand=true` flag while retaining Hunter, the 60-tick ring
  unstick, 240-pixel arm cap, 30-second arm deadline, 80-pixel arm safety
  margin, zero ring margin, and 0.85 hold band. Hosted behavioral coverage
  passed: all 10 candidate artifacts are valid and contain 19,293 `scan_band`
  ticks, while all 10 control artifacts contain zero. Candidate artifacts
  record 670 engage ticks versus 363 in control, but these diagnostics prove
  that scanning changed contact behavior; they are not score.
- Artifact: `andre-battleroyale:candidate-24`, Linux amd64 image digest
  `sha256:70910c6979a038c06bce1f39a105f9edfc7d3e5e587c39ff6b632c6456624d04`.
  Uploaded unsubmitted as `andre-battleroyale:v25`; exact submitted control
  and candidate images are `andre-trial-24:v1` and `andre-trial-24:v2`.
- XP id: Baseline `xreq_7fb9389b-63c9-4e40-b542-d4f496d16481` and candidate
  `xreq_b5c32bda-3e1a-477a-be07-b16ac2a236e8`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #13 at 1407.86. The nearest other
  players are Aaron (`aaln-br-hunter:v2`, 1415.98), softmaxwell
  (`Picasso:v63`, 1398.07), and ravidear5-code
  (`shade-doctrine-v1:v1`, 1439.06).
- Verdict: Reverted. Baseline mean 190.30, candidate mean 215.20, difference
  +24.90, 95% CI [-72.5153, 122.3153], Welch p=0.596338. The completed hosted
  result is inconclusive, so deliberate hold scanning was removed.
  `andre-battleroyale:v25` remains uploaded but was not submitted.

### Trial 23: cap hunter ring-unstick self-rearming

- Idea: Across the newest three exact submitted-control fields, unstick ticks
  correlate negatively with hosted score at Pearson r=-0.5039, -0.5737, and
  -0.4430. The latest ring fatality spent all 100 final retreat samples in
  `ring_unstick` without moving at all. Although the kept Trial 14 behavior is
  specified as a 60-tick burst, the shared 21-tick stuck detector can fire
  during that burst and extend `jinkUntil` by another 60 ticks repeatedly, so
  one failed direction can remain active until death.
- Change: Only while the submitted Hunter's 60-tick ring-unstick burst is
  already active, suppress a repeated stuck trigger instead of extending and
  reselecting the burst. Once the original burst expires, the unchanged
  20-frame detector may start another burst. Direction order, preferred side,
  32-pixel probe, 60-tick duration, normal ring retreat, arming, combat, hold
  band, and every other behavior remain unchanged. Suppressed self-rearms emit
  `ring_unstick_no_rearm`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports only the new
  `ffaHunterRingUnstickNoRearm=true` flag while retaining Hunter, the 60-tick
  ring unstick, 240-pixel arm cap, 30-second arm deadline, 80-pixel arm safety
  margin, zero ring margin, and 0.85 hold band. Hosted behavioral coverage
  passed: all 10 candidate artifacts are valid and contain 38
  `ring_unstick_no_rearm` ticks, while all 10 control artifacts contain zero,
  so the changed branch fired only in the candidate. Candidate artifacts also
  recorded 1,872 ordinary unstick ticks versus 3,166 in control; these
  diagnostics prove behavior, not score.
- Artifact: `andre-battleroyale:candidate-23`, Linux amd64 image digest
  `sha256:0a49d9de6ce46c51d19bcf244a5c85acbd1ffb9e589046024ca3f3c298dc89b0`.
  Uploaded unsubmitted as `andre-battleroyale:v24`; exact submitted control
  and candidate images are `andre-trial-23:v1` and `andre-trial-23:v2`.
- XP id: Baseline `xreq_316c67f5-a7d5-4b40-9264-7070a14e71d6` and candidate
  `xreq_d76278fe-3fed-46a2-96c8-00d4f96e5fd4`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #9 at 1473.85. The nearest other players
  are NanosaurusX (`nancy-br:v1`, 1471.80), Kenny Sheftel
  (`kenshef-my-player:v1`, 1445.58), and sivannn
  (`sivan-br-ringsurfer:v1`, 1442.27).
- Verdict: Reverted. Baseline mean 203.80, candidate mean 172.20, difference
  -31.60, 95% CI [-71.1644, 7.9644], Welch p=0.110024. The completed hosted
  result is inconclusive and trends worse, so active-burst self-rearm
  suppression was removed. `andre-battleroyale:v24` remains uploaded but was
  not submitted.

### Trial 22: bounded low-health hunter healing

- Idea: Hosted artifact-to-score joins on the two newest exact champion fields
  show heal events positively correlated with score in both fields, Pearson
  r=0.4098 and r=0.8938. In the latest field, the 18 heal events were
  concentrated in four longer-lived episodes. The submitted Hunter inherits
  Passive movement and never intentionally targets a medkit, so every heal is
  incidental. A short safe detour may turn a visible heal into survival without
  broadening combat or navigation.
- Change: Only for the default Hunter below the existing six-HP retreat
  threshold, move to the nearest visible medkit within 180 pixels when it is
  inside the existing 80-pixel ring-safe margin and no visible opponent is
  closer to it. Existing ring safety remains higher priority. Pursuit, firing,
  arming, hold band, unstick, targeting, and every other behavior remain
  unchanged. Active detours emit `move_medkit_hunter`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports bounded Hunter
  healing only in candidate and confirms the candidate retains Hunter, the
  60-tick ring unstick, 240-pixel arm cap, 30-second arm deadline, 80-pixel arm
  safety margin, zero ring margin, and 0.85 hold band. Hosted behavioral
  coverage failed: all 10 candidate artifacts are valid but contain zero
  `move_medkit_hunter` and `heal_trip` ticks. Candidate recorded 24 incidental
  heal events versus 12 in control, but the changed movement branch never
  caused a detour, so those diagnostics are not a strategy measurement.
- Artifact: `andre-battleroyale:candidate-22`, Linux amd64 image digest
  `sha256:7acfebf9ac217bafd8bb78935f430eb19f44cb9412d0daff660f532de78420b5`.
  Uploaded unsubmitted as `andre-battleroyale:v23`; exact submitted control
  and candidate images are `andre-trial-22:v1` and `andre-trial-22:v2`.
- XP id: Baseline `xreq_697a7c4e-bb14-48bb-b524-d257ff2d8e3e` and candidate
  `xreq_db14cf3f-a746-41d7-a45b-7847de99bb9b`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #13 at 1438.70. The nearest other
  players are NanosaurusX (`nancy-br:v1`, 1443.93), Kenny Sheftel
  (`kenshef-my-player:v1`, 1432.26), and David Greis
  (`Battle Royale Baseline:v1`, 1431.24).
- Verdict: Reverted. Baseline mean 197.30, candidate mean 192.10, difference
  -5.20, 95% CI [-53.1966, 42.7966], Welch p=0.820313. The result is
  inconclusive and trends worse, but more importantly the changed branch was
  inactive. Bounded Hunter healing was removed; `andre-battleroyale:v23`
  remains uploaded but was not submitted.

### Trial 21: inward-first hunter ring unstick

- Idea: The newest 10 exact submitted-control artifacts contain four deaths,
  all while unarmed. Two are ring-cadence fatalities. Unstick occupied 97.5
  percent of their final retreat samples and 93.8 percent of sampled steps
  were stationary. One fatal escape still moved 165 pixels but sustained 19
  ring hits because the submitted selector checks both pure tangents before
  either inward diagonal. Escaping an obstacle without gaining inward
  clearance can still lose the ring race.
- Change: Reorder only the default Hunter ring-unstick clearance candidates so
  the preferred and opposite inward diagonals are checked before the two pure
  tangents. Preferred-side selection, 32-pixel probe, 20-frame stuck trigger,
  60-tick burst, direct-inward fallback, normal ring retreat, arming, combat,
  hold band, and every other behavior remain unchanged. A burst emits
  `ring_unstick_inward_first` only when the new order selects different
  movement bits than the submitted order.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports inward-first
  selection only in candidate and confirms the candidate retains Hunter, the
  32-pixel probe, 60-tick burst, 240-pixel arm cap, 30-second arm deadline,
  80-pixel arm safety margin, zero ring margin, and 0.85 hold band. Hosted
  behavioral coverage passed: all 10 candidate artifacts are valid and contain
  1,257 `ring_unstick_inward_first` ticks, while control contains zero, so the
  reordered selector chose different movement bits in the frozen field.
- Artifact: `andre-battleroyale:candidate-21`, Linux amd64 image digest
  `sha256:a1aa88662df5f09f435a36a48be204c7f526bf1b433a616584430058df159fd9`.
  Uploaded unsubmitted as `andre-battleroyale:v22`; exact submitted control
  and candidate images are `andre-trial-21:v1` and `andre-trial-21:v2`.
- XP id: Baseline `xreq_40a0df70-b0ce-470c-83a9-42c3f1962b73` and candidate
  `xreq_fd1d7b03-d7e0-404a-ada1-34c771e01caf`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #12 at 1458.72. The nearest other
  players are NanosaurusX (`nancy-br:v1`, 1481.65), aosgoods
  (`eatth-battleroyale-decision-stack-v29:v1`, 1489.89), and softmaxwell
  (`Picasso:v63`, 1495.10).
- Verdict: Reverted. Baseline mean 167.80, candidate mean 170.40, difference
  +2.60, 95% CI [-55.5885, 60.7885], Welch p=0.926191. The active change is
  inconclusive with a near-zero effect, so tangent-first candidate order was
  restored. `andre-battleroyale:v22` remains uploaded but was not submitted.

### Trial 20: longer ring-unstick clearance probe

- Idea: The corrected hosted ring extractor uses the policy death tick rather
  than the later match end. Across the newest 30 exact v15 controls it finds
  three ring deaths. All three were unarmed; unstick occupied 91.9 percent of
  their final retreat samples, but 85.6 percent of sampled steps were
  stationary and one fatal retreat remained completely stationary. The
  submitted 32-pixel ray can accept a direction that is locally open but
  blocked before a 60-tick burst clears the obstacle.
- Change: Increase only the default Hunter ring-unstick clearance probe from
  32 to 96 pixels. Tangential candidate order, preferred side, 20-frame stuck
  trigger, 60-tick burst, normal ring retreat, arming, combat, hold band, and
  every other behavior remain unchanged. A burst emits
  `ring_unstick_long_probe` only when the 96-pixel probe selects different
  movement bits than the submitted 32-pixel probe.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports the 96-pixel
  probe only in candidate and confirms candidate and exact submitted control
  retain Hunter, the 60-tick unstick burst, 240-pixel arm cap, 30-second arm
  deadline, 80-pixel arm safety margin, zero ring margin, and 0.85 hold band.
  Hosted behavioral coverage passed: all 10 candidate artifacts are valid and
  contain 18 `ring_unstick_long_probe` ticks, while control contains zero, so
  the longer probe selected a different direction in the frozen field.
- Artifact: `andre-battleroyale:candidate-20`, Linux amd64 image digest
  `sha256:80b06f74f104c2c8f9a304fd16eb0b84d35b4de153f23a13c95040d31668ebc8`.
  Uploaded unsubmitted as `andre-battleroyale:v21`; exact submitted control
  and candidate images are `andre-trial-20:v1` and `andre-trial-20:v2`.
- XP id: Baseline `xreq_40ac0f1f-6d40-46f5-934d-b367105a0682` and candidate
  `xreq_fe3e6f2f-e0a8-4810-99e3-9e065c37f09c`, 10 hosted episodes per arm.
- Opponents: At field freeze Andre is #9 at 1463.65. The nearest other
  players are daveey (`daveey-br-hunter:v1`, 1458.39), NanosaurusX
  (`nancy-br:v1`, 1452.16), and aosgoods
  (`eatth-battleroyale-decision-stack-v29:v1`, 1442.61).
- Verdict: Reverted. Baseline mean 227.30, candidate mean 173.30, difference
  -54.00, 95% CI [-143.2562, 35.2562], Welch p=0.212048. The active change is
  inconclusive and trends worse, so the submitted 32-pixel probe was restored.
  `andre-battleroyale:v21` remains uploaded but was not submitted.

### Trial 19: prefer the nearest safe opening gun

- Idea: The corrected hosted-death extractor finds 11 deaths across the newest
  30 exact v15 control artifacts. Nine deaths occurred unarmed, including all
  three ring deaths, while only two occurred with even a low-tier gun. Hunter
  was unarmed for 65.47 percent of sampled live state. Its current bounded
  selector always chooses the highest visible tier before distance, so it may
  pass a nearby low gun for a farther high-tier gun inside the same 240-pixel
  cap. Prefer quicker initial arming without widening reach or adding trips.
- Change: Only for the default Hunter's initial unarmed gun selection, prefer
  the nearest eligible gun before tier. Exact-distance ties still prefer the
  higher tier and stable position. The existing 240-pixel cap, 30-second
  deadline, 80-pixel safe margin, opponent-closer rejection, ring behavior,
  pursuit, firing, hold band, and every other doctrine remain unchanged.
  Selections that differ from submitted tier-first choice emit
  `loot_nearest_gun` and `move_gun_nearest`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterNearestGun=true` only in the candidate and confirms candidate and
  exact submitted control retain Hunter, the 240-pixel cap, 30-second
  deadline, 80-pixel arm safety margin, 60-tick ring unstick, zero ring
  margin, and 0.85 hold band. Hosted behavioral coverage failed: all 10
  candidate artifacts are valid but contain zero `loot_nearest_gun` and
  `move_gun_nearest` ticks. The nearest-first selector never chose a different
  gun in the required field, so its score delta is not a valid strategy
  measurement.
- Artifact: `andre-battleroyale:candidate-19`, Linux amd64 image digest
  `sha256:48e31433dfd0387c786fcf341a58f43f0e7d7b5e68e2ed2bb795126082ca140b`.
  Uploaded unsubmitted as `andre-battleroyale:v20`; exact control and
  candidate images are `andre-trial-19:v1` and `andre-trial-19:v2`.
- XP id: Baseline `xreq_b81cba2c-0402-4b96-aeec-6938257f4204` and candidate
  `xreq_93196311-8dc0-47fa-b9a8-8c521dc55995`, 10 hosted episodes per arm.
- Opponents: At launch Andre is #13 at 1419.14. The frozen nearest other
  players are softmaxwell (`Picasso:v63`, 1434.94), David Greis
  (`Battle Royale Baseline:v1`, 1401.18), and NanosaurusX (`nancy-br:v1`,
  1395.23).
- Verdict: Reverted. Baseline mean 142.40, candidate mean 189.70, difference
  +47.30, 95% CI [-9.1039, 103.7039], Welch p=0.094781. The result is
  inconclusive, and the changed selection branch was inactive, so more
  episodes cannot validate this strategy on the frozen field. Tier-first
  selection was restored; `andre-battleroyale:v20` remains uploaded but was
  not submitted.

### Trial 18: shorten hunter arm-trip radius

- Idea: The submitted Hunter started 101 arm trips across 60 hosted v15
  artifacts, but 53 sampled trips aborted, 50 returned directly to passive
  hold, and median duration was 0.1 seconds. Widening reach from 240 to 480
  pixels in Trial 4 increased loot activity and armed time but remained
  inconclusive at +5.10 after 30 episodes per arm. Persisting more trips in
  Trial 15 also trended worse. Across 80 exact champion episodes, passive-hold
  ticks have a consistently strong positive score correlation. Reject more
  marginal trips while retaining nearby safe arming.
- Change: Set only the default Hunter initial arm-trip detour radius from 240
  to 120 pixels. The existing gun tier choice, 30-second deadline, 80-pixel
  ring margin, opponent-closer guard, ring safety, pursuit, firing, hold band,
  and all other behavior are unchanged. When an otherwise eligible gun exists
  only in the submitted 120-to-240-pixel interval, passive holding emits
  `hold_far_gun`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction confirms the candidate
  uses a 120-pixel radius versus 240 in exact submitted control while both
  retain the 30-second deadline, 80-pixel safety margin, pursuit, 60-tick
  unstick, and 0.85 hold band. Hosted artifact coverage passed: all 10
  candidate artifacts are valid and contain 93 `hold_far_gun` ticks, while
  control contains zero, so the shortened-radius branch fired. The 20-episode
  extension adds 725 candidate `hold_far_gun` ticks and zero in control.
  Initial candidate armed sampled state was 12.05 percent versus 8.85 percent
  in control, with two loot trips versus six; these artifact diagnostics are
  not score.
- Artifact: `andre-battleroyale:candidate-18`, Linux amd64 image digest
  `sha256:5e4aa0d88dbe6bf66b7d0c49e7c3159b8d35c49ea7ce7c3308c468871976d361`.
  Uploaded unsubmitted as `andre-battleroyale:v19`; exact control and
  candidate images are `andre-trial-18:v1` and `andre-trial-18:v2`.
- XP id: Baseline `xreq_26a9e197-159e-46bc-9e4c-3eac6c704776` and candidate
  `xreq_35fd3484-2df3-4b06-bfe4-e41575a69699`, 10 hosted episodes per arm.
  The exact same-field 20-episode extension is baseline
  `xreq_2007988f-6d59-4bed-ab78-a40e1253e4d4` and candidate
  `xreq_55213f6c-de23-49cb-af23-6648da7261e2`.
- Opponents: At launch Andre is #12 at 1431.09. The frozen nearest other
  players are Aaron (`aaln-br-hunter:v2`, 1420.22), ravidear5-code
  (`shade-doctrine-v1:v1`, 1415.86), and softmaxwell
  (`Picasso:v63`, 1408.68).
- Verdict: Reverted. The initial 10-per-arm result was inconclusive: baseline
  mean 146.40, candidate mean 164.00, difference +17.60, 95% CI [-68.6018,
  103.8018], Welch p=0.672784. After extending the exact field to 30 per arm,
  baseline mean was 183.8333 and candidate mean was 166.4667, difference
  -17.3667, 95% CI [-63.0186, 28.2853], Welch p=0.448425. The shortened
  radius remains inconclusive and trends worse, so the default returned to
  240 pixels. `andre-battleroyale:v19` remains uploaded but was not submitted.

### Trial 17: disable normal hunter pursuit movement

- Idea: `tools/correlate_xp_artifacts.nim` joined hosted scores to all 80
  exact current-champion artifacts from Trials 14 through 16. Passive-hold
  ticks were the strongest positive score correlate in all three frozen
  fields, with Pearson r values 0.7878, 0.8278, and 0.5796. Damage taken was
  negative in every field, at -0.1523, -0.3219, and -0.3479. The 60-episode
  field contained 933 normal fight ticks, while current Hunter can still fire
  at visible in-range targets without pursuing them. Isolate chase movement
  from the broader Passive doctrine that failed Trial 7.
- Change: Set only normal Hunter weak-target pursuit movement off by default.
  Safe initial arming, weapon-range firing, aiming, the 0.85 hold band, ring
  safety, 60-tick unstick, four-player late close, and every other submitted
  behavior are unchanged. When an otherwise pursuable weak target is declined,
  passive holding emits `hold_no_pursuit` and `pursuit_disabled`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction confirms pursuit is
  false only in candidate while both images retain Hunter, safe arming,
  weapon-range firing, 60-tick unstick, zero ring margin, and 0.85 hold band.
  Hosted behavioral coverage failed: all 10 candidate artifacts are valid but
  contain zero `hold_no_pursuit` and `pursuit_disabled` ticks. Candidate has
  zero normal fight ticks, while control has only 21 fight ticks and two
  sampled `pursue_weak` rows, so the required field never exercised the
  disabled-chase branch.
- Artifact: `andre-battleroyale:candidate-17`, Linux amd64 image digest
  `sha256:3c97c94d6ca52dd654e3c1693cc7be934d26215f9224ba423a5e61ef32c7cc94`.
  Uploaded unsubmitted as `andre-battleroyale:v18`; exact control and
  candidate images are `andre-trial-17:v1` and `andre-trial-17:v2`.
- XP id: Baseline `xreq_456a079c-44da-4004-80d3-513205bc86fc` and candidate
  `xreq_ae965246-3d0c-4d42-b3f0-3aa945b7d16e`, 10 hosted episodes per arm.
- Opponents: At launch Andre is #13 at 1416.70. The frozen nearest other
  players are b4kng2dkg5-sudo (`starter-baseline:v1`, 1421.69), David Greis
  (`Battle Royale Baseline:v1`, 1422.31), and Aaron
  (`aaln-br-hunter:v2`, 1402.76).
- Verdict: Reverted. Baseline mean 183.00, candidate mean 167.80, difference
  -15.20, 95% CI [-68.4058, 38.0058], Welch p=0.555676. The result is
  inconclusive and trends worse, but more importantly the changed branch was
  inactive, so the XP delta is not a valid strategy measurement. Pursuit was
  restored; `andre-battleroyale:v18` remains uploaded but was not submitted.

### Trial 16: alternate repeated ring-unstick sides

- Idea: The corrected `tools/summarize_ring_retreats.nim` includes both
  normal retreat and the submitted `ring_unstick` action. Across all 60
  hosted v15 artifacts it found nine ring-cadence fatalities. Unstick occupied
  84.3 percent of their final retreat samples, but 81.3 percent of consecutive
  positions were effectively stationary. Several fatalities spent 96 to 100
  samples in unstick while remaining 98 to 99 percent stationary. The current
  selector retries every 21 stationary ticks but keeps the same preferred
  tangential side for up to 120 ticks, repeatedly choosing a locally clear
  32-pixel probe that can still be globally blocked.
- Change: Only during the submitted Hunter ring-safety unstick, alternate the
  preferred tangential side on every repeated stuck retry within one continuous
  ring retreat. The existing candidate order, 32-pixel clearance probe,
  20-frame stuck threshold, 60-tick burst, inward fallbacks, ring alarm,
  looting, combat, and all other behavior are unchanged. A second-side retry
  emits `ring_unstick_flip`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction confirms candidate and
  exact submitted control retain the Hunter doctrine, 60-tick unstick,
  240-pixel detour, zero ring margin, and 0.85 hold band. Hosted artifact
  coverage passed: all 10 candidate artifacts are valid and contain 720
  `ring_unstick_flip` ticks, while control contains zero, so repeated-side
  alternation fired. In fatal-retreat diagnostics, stationary steps fell from
  96.7 percent in control to 13.7 percent in candidate and ring-like deaths
  fell from four to two; these diagnostics are not score.
- Artifact: `andre-battleroyale:candidate-16`, Linux amd64 image digest
  `sha256:de4cca39ad24c3ee7898873e4ad62d763225e0e6d148b43a39c69f0d88939754`.
  Uploaded unsubmitted as `andre-battleroyale:v17`; exact control and
  candidate images are `andre-trial-16:v1` and `andre-trial-16:v2`.
- XP id: Baseline `xreq_b90bf022-6eea-4633-8367-7bb861db576c` and candidate
  `xreq_a8fb0180-a7d4-4f72-a72f-b17958fcb551`, 10 hosted episodes per arm.
- Opponents: At launch Andre is #16 at 1327.52. The frozen nearest other
  players are b4kng2dkg5-sudo (`starter-baseline:v1`, 1337.38), NanosaurusX
  (`nancy-br:v1`, 1382.00), and David Greis
  (`Battle Royale Baseline:v1`, 1405.42).
- Verdict: Reverted. Baseline mean 187.50, candidate mean 180.20, difference
  -7.30, 95% CI [-62.6011, 48.0011], Welch p=0.781234. The result is
  inconclusive and trends worse, so repeated-side alternation was removed.
  `andre-battleroyale:v17` remains uploaded but was not submitted.

### Trial 15: remember a fog-hidden gun trip

- Idea: Across all 60 hosted v15 artifacts, Hunter was unarmed in 67.34
  percent of sampled live state and started 101 trips. The corrected
  `tools/summarize_loot_trips.nim` found 29 sampled successes and 53 aborts;
  50 aborts returned directly to passive hold, only three were ring retreats,
  and median sampled run duration was 0.1 seconds. Coworld's observation code
  states that a fixed pickup is emitted only while present and inside the
  seat's real vision, but Hunter currently treats any absent gun sprite as
  claimed or stale. Preserve the safe commitment through a fog gap.
- Change: Only for the default Hunter with an active gun trip, allow the
  committed target to remain valid while its sprite is fog-hidden and the bot
  is still more than the existing 32-pixel pickup radius away. At or within
  32 pixels, an absent gun still aborts. The existing 240-pixel detour,
  30-second deadline, 80-pixel ring margin, opponent-closer guard, ring
  safety, target selection, combat, and every other doctrine are unchanged.
  Fog-memory movement emits `loot_memory_trip` and `move_gun_memory`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production extraction reports
  `ffaHunterRememberFoggedGun=true` only in the candidate and confirms both
  images retain the submitted Hunter doctrine, 60-tick ring unstick,
  240-pixel detour, zero ring margin, and 0.85 hold band. Hosted artifact
  coverage passed: all 10 candidate artifacts are valid and contain 33
  `loot_memory_trip` and `move_gun_memory` ticks, while control contains zero,
  so the branch fired. Candidate unarmed sampled state was 53.93 percent
  versus 45.24 percent in control; this diagnostic is not score.
- Artifact: `andre-battleroyale:candidate-15`, Linux amd64 image digest
  `sha256:1db6ac8e281eebe210072c10da80fecdd2f3a78ca0a1853b6eb219fe44545a27`.
  Uploaded unsubmitted as `andre-battleroyale:v16`; exact control and
  candidate images are `andre-trial-15:v1` and `andre-trial-15:v2`.
- XP id: Baseline `xreq_423a2e60-59e7-4dd5-ac2a-18f3dbf11d39` and candidate
  `xreq_d0238825-ab5c-4905-9575-30204767e6c9`, 10 hosted episodes per arm.
- Opponents: At launch Andre is #16 at 1301.86. The frozen nearest other
  players are ravidear5-code (`shade-doctrine-v1:v1`, 1367.33), NanosaurusX
  (`nancy-br:v1`, 1375.82), and Aaron (`aaln-br-hunter:v2`, 1396.77).
- Verdict: Reverted. Baseline mean 177.00, candidate mean 171.20, difference
  -5.80, 95% CI [-72.9056, 61.3056], Welch p=0.857494. The result is
  inconclusive and trends worse, so the fog-memory behavior was removed.
  `andre-battleroyale:v16` remains uploaded but was not submitted.

### Trial 14: persistent hunter ring unstick

- Idea: `tools/summarize_ring_retreats.nim` found 11 ring-cadence fatalities
  across 50 exact submitted-Hunter artifacts from Trials 4, 11, and 13. About
  76 percent of sampled retreat steps were effectively stationary, 10 of 11
  deaths had at most 24 pixels of net movement during the final 10 seconds,
  and no opponent was visible in those retreat windows. The existing stuck
  fallback issues only one direct-center input before returning to the same
  blocked path. Persist a short tangential escape long enough to clear it.
- Change: Only for the default Hunter while its existing 80-pixel ring-safety
  retreat is active, after the existing 20-frame stuck threshold choose an
  open tangential direction, hold it for 60 ticks, and invalidate the nav goal
  for a repath. Normal ring retreat, alarm distance, hold band, looting,
  combat, targeting, firing, all other stuck cases, and every other doctrine
  are unchanged. Active bursts emit `ring_unstick`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production startup matches every submitted
  Hunter setting and reports `ffaHunterRingUnstickTicks=60`. All 10 initial
  candidate artifacts are valid and contain 2,871 `ring_unstick` ticks, so the
  branch fired. Candidate ring-like fatal retreats had 11.1 percent stationary
  steps versus 60.8 percent in control; this diagnostic is not score.
- Artifact: `andre-battleroyale:candidate-14`, Linux amd64 image digest
  `sha256:2f1536a688b3dcfbad572bd21a7d830d1a7627e5d290f036faeb2d426414f30a`.
  Uploaded unsubmitted as `andre-battleroyale:v15`; exact control and
  candidate images are `andre-trial-14:v1` and `andre-trial-14:v2`.
- XP id: Initial baseline `xreq_a171357f-ea77-4538-adc4-b60eb50f96c0` and
  candidate `xreq_493e7dcf-2487-49f0-9f10-cb94430d77ce`, 10 hosted episodes
  per arm. The same-field 20-episode extension is baseline
  `xreq_36e1e696-45f8-489e-941f-7825e1cebbd6` and candidate
  `xreq_93c33f27-cc64-4b31-82ce-ded852922c5f`. At 30 per arm the difference
  was +32.3667, 95% CI [-0.1187, 64.8521], Welch p=0.050812. The second
  extension is baseline `xreq_7d8674e2-cd03-43dd-909a-295357314533` and
  candidate `xreq_c174e404-21c6-4ae1-89db-482016e691ff`. At 40 per arm the
  difference was +24.3500, 95% CI [-2.4177, 51.1177], Welch p=0.073957. The
  third extension is baseline `xreq_f6a1fa2e-abfc-4129-b400-895d6c2fde01`
  and candidate `xreq_4d1a774b-8912-4e21-b856-f05b815fa663`, 20 episodes per
  arm.
- Opponents: At launch Andre is #16 at 1261.91. The frozen nearest other
  players are Aaron (`aaln-br-hunter:v2`, 1333.14), aosgoods
  (`eatth-battleroyale-decision-stack-v29:v1`, 1376.08), and NanosaurusX
  (`nancy-br:v1`, 1406.29).
- Verdict: Kept. Across all 60 hosted episodes per arm, baseline mean was
  159.6500 and candidate mean was 192.2667, improvement +32.6167, 95% CI
  [10.2746, 54.9587], Welch p=0.004598. The Softmax XP dashboard also reports
  candidate 192.27 and 64% +/- 7% versus control 159.65 and 49% +/- 7%.
  Submitted `andre-battleroyale:v15` as the new champion with submission
  `sub_b6881599-8a5b-428b-b970-de03f8e7b703` and active membership
  `lpm_40b8d55d-c55f-437d-98d5-04a5ba6b0c45`.

### Trial 13: extended heavy-gun arm reach

- Idea: The broad 480-pixel Trial 4 arm radius raised submitted-Hunter armed
  time from 31.49 to 49.82 percent and produced 481 sampled heavy-gun ticks
  versus zero in control. It also increased trips from 22 to 82 and aborts
  from 3 to 28, masking that useful heavy-gun subeffect in an inconclusive
  final delta of 5.10. Isolate the heavy pickup without widening low/mid trips.
- Change: Only for an unarmed default Hunter, allow a ring-safe,
  opponent-aware heavy gun out to 480 pixels while low and mid guns retain the
  submitted 240-pixel cap. The 30-second deadline, 80-pixel safe margin,
  target selection, pursuit, aiming, firing, hold band, and all other
  doctrines are unchanged. Extended trips emit `heavy_loot_trip` and
  `move_heavy_extended`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production startup preserves the submitted
  240-pixel normal radius and reports the isolated 480-pixel heavy radius.
  Hosted behavioral coverage failed: all 10 candidate artifacts contain zero
  `heavy_loot_trip` and `move_heavy_extended` ticks. Candidate mean armed
  fraction was 0.3688 with 1.4 loot trips, versus control 0.5134 with 0.8
  trips, but these artifact diagnostics are not score.
- Artifact: `andre-battleroyale:candidate-13`, Linux amd64 image digest
  `sha256:37f653afd3f64e1cb9de52624aa815e2deb6d00cd6df6a7ba10ff171425fbdb2`;
  uploaded unsubmitted as `andre-battleroyale:v14`; exact control and candidate
  images are `andre-trial-13:v1` and `andre-trial-13:v2`.
- XP id: Baseline `xreq_23e52035-9b1a-4e28-8b41-45bd935d4d9a` and candidate
  `xreq_656c7b1a-958b-4fec-8533-f05594ff30ba`, 10 hosted episodes per arm.
- Opponents: At launch Andre is #16 at 1268.53. The frozen nearest other
  players are Aaron (`aaln-br-hunter:v2`, 1289.86), NanosaurusX
  (`nancy-br:v1`, 1380.89), and sivannn (`sivan-br-ringsurfer:v1`, 1397.83).
- Verdict: Reverted. Baseline mean 171.30, candidate mean 151.70, difference
  -19.60, 95% CI [-93.1792, 53.9792], Welch p=0.582570. The result is
  inconclusive and trends worse, while the changed extended-heavy branch was
  inactive in every hosted artifact. `andre-battleroyale:v14` remains
  uploaded but was not submitted.

### Trial 12: earlier hunter ring alarm

- Idea: Across 70 exact submitted-hunter control replays from Trials 9-11,
  ring damage caused 21 documented fatalities. The latest exact-field Hunter
  spent 10,939 ticks in ring retreat and lost four of six deaths to the ring.
  The existing alarm waits until 80 pixels from the continuously shrinking
  boundary. Test an earlier alarm without changing the Hunter hold target.
- Change: Only for the default `FfaHunter` doctrine, begin the existing
  centerward ring retreat at a 160-pixel margin instead of 80 pixels. The
  0.85 hold band, hold target, arming, pursuit, target selection, aiming,
  firing, and all other doctrines are unchanged. Only the added 80-pixel
  interval emits `safe_zone_early`, `retreat_ring_early`, and `ring_early`.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  amd64 production build pass. Production and hosted startup report the
  submitted Hunter settings with `ffaHunterRingSafetyMargin=160`. All 10
  candidate artifacts are valid and contain 9,690 `safe_zone_early`,
  `retreat_ring_early`, and `ring_early` ticks, so the branch fired.
- Artifact: `andre-battleroyale:candidate-12`, Linux amd64 image digest
  `sha256:bb21dea81cdb9291c7b61c488cb1881faf1d5862089a451b1a5002653e8d7e08`.
  Uploaded unsubmitted as `andre-battleroyale:v13`; exact control and
  candidate images are `andre-trial-12:v1` and `andre-trial-12:v2`.
- XP id: Baseline `xreq_9ec1c567-c2d5-4243-a1a7-e49fcf58533c` and candidate
  `xreq_2cdc4912-cb48-4173-b529-8c7dea58cc65`, 10 hosted episodes per arm.
- Opponents: Frozen outside-top-three nearest-MRR field at launch: Aaron
  (`aaln-br-hunter:v2`), NanosaurusX (`nancy-br:v1`), and b4kng2dkg5-sudo
  (`starter-baseline:v1`).
- Verdict: Reverted. Baseline mean 188.40, candidate mean 180.90, difference
  -7.50, 95% CI [-48.6252, 33.6252], Welch p=0.705966. The active change is
  inconclusive and trends worse. `andre-battleroyale:v13` remains uploaded but
  was not submitted.

### Trial 11: rush doctrine default

- Idea: Against the stronger Trial 10 field, the exact submitted hunter
  averaged 145.50 score, 0.23 kills, 7.87 damage, and place 2.73. Ryan
  Schiller's current policy averaged 209.17 score, 1.47 kills, 30.33 damage,
  and place 1.63, with 160 of 203 gun hits coming from heavy guns. The existing
  rush doctrine goes to center/highest-tier visible gear and engages contacts.
  Test whether that combat economy can outperform fringe hunter survival.
- Change: When `CTF_BOT_FFA_DOCTRINE` is unset, select the existing `FfaRush`
  doctrine instead of `FfaHunter`. No rush, hunter, combat, item, navigation,
  ring, aiming, or firing parameter changes.
- Isolation: Production amd64 image startup reports `ffaDoctrine=rush`.
  All 10 hosted candidate artifacts report the rush doctrine and aggregate
  4,606 `rush_arm`, 6,328 `converge`, and 1,967 `fight` ticks.
- Artifact: `andre-battleroyale:v12` and isolated `andre-trial-11:v2`, image
  digest `sha256:9fedb633a90665e587e7d10fc0ad55aea1056ecd81ad8c509418ab17ed42339e`.
- XP id: Baseline `xreq_d70bcadd-c1c1-4ae7-a6a6-409d5bf738c1` and candidate
  `xreq_9b2441b8-fc23-4f1d-87b5-1b31610fd280`, 10 hosted episodes per arm.
- Opponents: Frozen outside-top-three nearest-MRR field at launch: Aaron
  (`aaln-br-hunter:v2`), David Greis (`Battle Royale Baseline:v1`), and
  softmaxwell (`Picasso:v63`).
- Verdict: Reverted. Baseline mean 201.40, candidate mean 82.60, difference
  -118.80, 95% CI [-216.2395, -21.3605], Welch p=0.019623. Rush is a
  statistically significant regression. `andre-battleroyale:v12` remains
  uploaded but was not submitted.

### Trial 10: kite nearby heavy-gun threats

- Idea: Exact submitted-champion replays across 30 hosted episodes attribute
  11 of its 21 deaths to heavy guns. The champion averages 3,067.50 survival
  ticks and place 2.10, but only 6.10 damage. Its locked gun aim is already
  within 1.59 brads of the inferred target at release, and compensating for
  shooter motion improves only 12.50 percent of shots. Preserve firing and
  convert the survival leak by kiting the weapon that causes most deaths.
- Change: Only under the submitted hunter doctrine, when a visible heavy-gun
  actor is within 400 pixels and ring safety is not already active, move 240
  pixels directly away and clamp the escape target inside the existing
  80-pixel safe margin. Target selection, aim, firing, pursuit, arming, hold
  band, ring alarm, and every non-hunter doctrine are unchanged. The branch
  emits `heavy_evade`, `evade_heavy`, and `heavy_threat` for isolation.
- Isolation: `nim check`, the doctrine source-contract suite, and the Linux
  AMD64 production build passed. The binary contains all three isolation
  markers. All 10 candidate hosted artifacts are valid and contain 5,345
  `heavy_evade` and `evade_heavy` ticks. The branch fired; the 30 control
  replays, aim geometry, and artifacts are diagnostics, not score.
- Artifact: `andre-battleroyale:candidate-10`, Linux AMD64 image
  `sha256:bbc73281a3950a0a6bfef78d5b70f2d1fe3cf129718b1186ce269ac164bf8577`.
  Uploaded unsubmitted as `andre-battleroyale:v11`; exact control and
  candidate images are `andre-trial-10:v1` and `andre-trial-10:v2`.
- XP id: Baseline `xreq_bbf56c6a-f847-4b17-9c7b-62ab6d7b68c6` and
  candidate `xreq_6df98b33-2021-466f-b4f2-e251d8ac81fb`, 10 hosted episodes
  per arm. Same-field extensions are baseline
  `xreq_9acfb878-4d0f-4302-ba9f-2aae833f9025` and candidate
  `xreq_c744b910-3b98-4d13-bbe2-d9d56f4e7409`, 20 hosted episodes per arm.
- Opponents: At launch Andre is #7 at 1547.61. The frozen nearest other
  players are Aaron (`aaln-br-hunter:v2`, 1576.23), Ryan Schiller
  (`ryanschiller-br-v46:v1`, 1610.52), and relh
  (`co-gas-battleroyale-baseline-relhalpha:v7`, 1630.91).
- Verdict: Revert. Initial 10 per arm was inconclusive. Baseline mean 126.3000,
  candidate mean 163.0000, difference 36.7000, two-sided 95 percent Welch CI
  [-49.2647, 122.6647], p=0.372069. At 30 per arm, baseline mean was 145.5000
  and candidate mean was 140.0333, difference -5.4667, CI
  [-41.1700, 30.2367], p=0.759632. This remains inconclusive and trends worse.
  Restored the submitted hunter behavior; uploaded `andre-battleroyale:v11`
  was not submitted.

### Trial 9: safe hunter weapon upgrades

- Idea: The exact submitted hunter artifacts contain 5,472 unarmed samples,
  2,072 low-tier samples, 509 mid-tier samples, and zero heavy-tier samples.
  Hunter already has a bounded, ring-safe, opponent-aware higher-tier gun
  selector, but returns before using it after initial arming. Safe upgrades may
  convert more of its weapon-range contacts without increasing trip reach.
- Change: Let an armed, non-pursuing hunter use the existing gun selector only
  for a strictly higher weapon tier. The 240-pixel detour cap, 80-pixel ring
  safety margin, 30-second deadline, enemy avoidance, bands, pursuit, firing,
  and all other behavior are unchanged. Upgrade movement emits
  `upgrade_trip` and `move_upgrade` for isolation.
- Isolation: `nim check` and the doctrine source-contract suite pass.
  Production startup extraction matches every submitted hunter setting, and
  the production binary contains both upgrade telemetry markers. All 10
  initial candidate artifacts were valid and recorded 38 `upgrade_trip` and
  `move_upgrade` ticks. The branch fired; diagnostics are not score.
- Artifact: `andre-battleroyale:candidate-9`, Linux AMD64 image
  `sha256:1b1d831c9fd60e597592309afc61a648720fe44f16a4197925e29581bee76fe4`.
  Uploaded unsubmitted as `andre-battleroyale:v10`; exact control and
  candidate images were uploaded as `andre-trial-9:v1` and
  `andre-trial-9:v2`.
- XP id: Baseline `xreq_835e6afc-41ed-4a3f-bd2e-467c47f8d4e0` and
  candidate `xreq_5897dfe3-eee9-48f3-b1dd-7d2a95d19e87`, 10 hosted episodes
  per arm. Same-field extensions are baseline
  `xreq_0f4416f4-4bf4-4760-8fbf-3f6e118366c4` and candidate
  `xreq_fbfd2628-a349-48d7-b949-dde0cdef6000`, 20 hosted episodes per arm.
- Opponents: Andre remains #9 at 1466.38. The frozen nearest other players at
  launch will be softmaxwell (`Picasso:v62`, 1425.82), NanosaurusX
  (`nancy-br:v1`, 1355.24), and David Greis
  (`Battle Royale Baseline:v1`, 1330.31).
- Verdict: Revert. Initial 10 per arm was inconclusive: baseline mean
  174.7000, candidate mean 192.0000, difference 17.3000, two-sided 95 percent
  Welch CI [-37.3482, 71.9482], p=0.510652. At 30 per arm the baseline mean
  was 177.5333 and candidate mean 189.2333, difference 11.7000, CI
  [-22.7784, 46.1784], p=0.499519. This remains inconclusive. Restored
  initial-arming-only behavior; uploaded `andre-battleroyale:v10` was not
  submitted.

### Trial 8: vulnerable hunter target selection

- Idea: The submitted hunter always aims at the nearest visible actor, so its
  weak-target pursuit is blocked whenever that nearest actor is strong even if
  a vulnerable opponent is also visible. The exact submitted artifacts contain
  only five sampled `pursue_weak` rows across 30 episodes. Selecting the nearest
  pursuable opponent may convert more vulnerable sightings into eliminations.
- Change: Only for eligible hunter pursuit, replace the normal nearest target
  with the nearest unsupported opponent that is unarmed or has lower HP and is
  inside the safe ring. All movement, firing, arming, bands, ring behavior,
  health thresholds, and support radius are unchanged. Replacement cases emit
  `pursue_vulnerable` for isolation.
- Isolation: `nim check` and the doctrine source-contract suite passed.
  Production startup extraction matched the submitted hunter settings, and
  the binary contained exactly one `pursue_vulnerable` marker. None of the 10
  candidate hosted artifacts emitted that marker, while ordinary
  `pursue_weak` appeared in 18 samples. The replacement branch did not fire.
- Artifact: `andre-battleroyale:candidate-8`, Linux AMD64 image
  `sha256:85d94425bccbf88e1ce3119bafe8efe5146aa80b8f90aa5278e092899c6fa508`.
  Uploaded unsubmitted as `andre-battleroyale:v9`; exact control and candidate
  images were uploaded as `andre-trial-8:v1` and `andre-trial-8:v2`.
- XP id: Baseline `xreq_bc643679-8a69-4d1b-b995-0125aa1726cf` and
  candidate `xreq_5b54981f-311f-4576-8401-7664b4b0e309`, 10 hosted episodes
  per arm.
- Opponents: Andre remains #9 at 1466.38. The frozen nearest other players at
  launch will be softmaxwell (`Picasso:v62`, 1425.82), NanosaurusX
  (`nancy-br:v1`, 1355.24), and David Greis
  (`Battle Royale Baseline:v1`, 1330.31).
- Verdict: Revert. Baseline mean 154.3000, candidate mean 202.9000,
  difference 48.6000, two-sided 95 percent Welch CI [-28.1790, 125.3790],
  p=0.200157. The result is inconclusive and the changed branch was inactive.
  Restored nearest-target selection; uploaded `andre-battleroyale:v9` was not
  submitted.

### Trial 7: passive doctrine default

- Idea: The live 24-hour dashboard reports two passive policies near 63 percent
  win rate, while the submitted hunter is near 53 percent. Hosted artifacts
  also show that the hunter spends most of its live time in the passive hold
  branch. Removing hunter-only arm trips, pursuit, fire-range expansion, and
  four-player late close may preserve more survival and podium score.
- Change: When `CTF_BOT_FFA_DOCTRINE` is unset, select `FfaPassive` instead of
  `FfaHunter`. No passive, hunter, ring, arming, or combat parameter changes.
- Isolation: Native binary settings passed. `tools/extract_doctrine.nim`
  compared the exact submitted control at `ffaDoctrine=hunter` with the
  candidate at `ffaDoctrine=passive`; all printed bands, arming, pursuit, and
  ring settings match. Production image extraction passed the same assertions.
  All 10 initial candidate hosted logs contain `ffaDoctrine=passive`. Their
  artifacts contain 26,480 `passive_band` hold actions and zero hunter-only
  loot trips, proving the doctrine change fired. Diagnostics are not score.
- Artifact: `andre-battleroyale:candidate-7`, Linux AMD64 image
  `sha256:f91240b1d83820abd61af5e530e1d3e8d1022f4612077dbd410f6943b7c3135e`.
  Uploaded unsubmitted as `andre-battleroyale:v8`; the exact submitted control
  and candidate images were also uploaded as immutable XP policies
  `andre-trial-7:v1` and `andre-trial-7:v2`.
- XP id: Baseline `xreq_ff913c8c-526a-487c-a228-168c50829e4f` and
  candidate `xreq_84edd7d4-5907-40f3-8f3a-e1f363e40d32`, 10 hosted episodes
  per arm. Same-field extensions are baseline
  `xreq_1a122e5f-74dd-4c8e-85eb-052abc29c29d` and candidate
  `xreq_38381691-6988-4a65-92b5-7a5799d240a1`, 20 hosted episodes per arm.
- Opponents: At launch Andre remains #9 at 1466.38. The frozen nearest other
  players are softmaxwell (`Picasso:v62`, 1425.82), NanosaurusX
  (`nancy-br:v1`, 1355.24), and David Greis
  (`Battle Royale Baseline:v1`, 1330.31).
- Verdict: Revert. Initial 10 per arm was inconclusive: baseline mean
  192.6000, candidate mean 194.8000, difference 2.2000, two-sided 95 percent
  Welch CI [-80.6707, 85.0707], p=0.956134. At 30 per arm the baseline mean
  was 194.7333 and candidate mean 171.8667, difference -22.8667, CI
  [-58.5045, 12.7711], p=0.203874. This remains inconclusive and trends worse.
  Restored `FfaHunter`; uploaded `andre-battleroyale:v8` was not submitted.

### Trial 6: interior hunter hold band

- Idea: The exact 30 submitted-hunter artifacts contain 69,232 passive-hold
  ticks and 21,343 ring-retreat ticks. Sampled reasons contain 6,082 holds and
  1,767 ring retreats. Holding at 85 percent of the continuously shrinking
  safe radius spends too much time crossing the fixed 80-pixel alarm and
  retreating. A 60-percent band should reduce that churn and keep the hunter
  closer to contact without changing its ring alarm.
- Change: Set only `FfaPassiveBandDefault` from `0.85` to `0.60`. Under the
  submitted hunter doctrine this is its normal hold radius. Arming, pursuit,
  firing, late-close, ring alarm, and all other settings are unchanged.
- Isolation: Native binary settings passed. `tools/extract_doctrine.nim`
  compared the exact submitted control image at `ffaPassiveBand=0.85` with the
  candidate at `0.6`; their combat, arming, support, detour, and ring settings
  match. Production image extraction and a hosted startup log passed the same
  assertions. All 10 candidate artifacts exercised the navigation change with
  2,484 sampled `0.600` band rows. This diagnostic is not used as score.
- Artifact: Production image `andre-battleroyale:candidate-6`, Linux AMD64,
  command `/bin/baseline`, digest
  `sha256:dc358fc6948f1a4230d48604be1cac341b384277a37337c275fd982601cd1aed`.
  Uploaded as unsubmitted candidate `andre-battleroyale:v7`; exact binary
  clones are `andre-trial-6:v1` and `andre-trial-6:v2`.
- XP id: Baseline `xreq_ecd96c93-4e50-48dc-ba1f-941ebf5b05c4`;
  candidate `xreq_4e9c91e4-86e3-48e3-b4a8-8cddb24c16f6`. The 20-episode
  extension uses baseline `xreq_eb7b47cc-e364-4da9-84f4-1f60a906a2e0` and
  candidate `xreq_2a1c6c2e-f57f-4cd2-9ce3-832dd68bb16e`.
- Opponents: At launch Andre remains #9 at 1466.38. The frozen nearest other
  players are softmaxwell (`Picasso:v62`, 1425.82), NanosaurusX
  (`nancy-br:v1`, 1355.24), and David Greis
  (`Battle Royale Baseline:v1`, 1330.31).
- Verdict: Reverted. The first 10 hosted episodes per side were inconclusive.
  Candidate minus baseline was `5.9000`, with a two-sided 95 percent Welch
  interval `[-70.6125, 82.4125]` and `p=0.869076`. Twenty more hosted episodes
  per side used the same frozen field. Across all 30 episodes per side,
  candidate minus baseline was `-11.6000`, with a two-sided 95 percent Welch
  interval `[-56.4935, 33.2935]` and `p=0.606563`. This remains inconclusive,
  so the default returned to `0.85`; `andre-battleroyale:v7` remains
  unsubmitted.

### Trial 5: pursue equal-HP solo opponents

- Idea: `tools/download_xp_artifacts.nim` and
  `tools/summarize_artifacts.nim` aggregated the exact 30 Trial 4 control
  artifacts, which are the submitted hunter. They contain 69,232 passive-hold
  ticks but only 42 fight ticks. Sampled engage reasons contain 6,082 holds and
  only five `pursue_weak` ticks. The current hunter rejects a healthy armed
  opponent unless its HP is strictly lower, so the common equal-health duel
  never becomes a pursuit.
- Change: Add only `CTF_BOT_FFA_HUNTER_PURSUE_EQUAL`, enabled by default. An
  armed hunter at or above the existing six-HP threshold may pursue an
  equal-HP armed opponent. The existing 300-pixel support rejection, ring
  safety, arming, fire-range, and weak-target behavior are unchanged.
- Isolation: Native binary settings passed. `tools/extract_doctrine.nim`
  compared the exact submitted control image with the candidate. The control
  retains its prior hunter behavior; the candidate reports
  `ffaHunterPursueEqual=true`. Their pursuit, six-HP threshold, 300-pixel
  support rejection, 240-pixel arm detour, and ring settings match. Production
  image extraction passed the same assertions. Hosted startup logs also
  confirmed `ffaHunterPursueEqual=true`, but behavioral coverage failed: all
  10 candidate artifacts contain zero sampled `pursue_equal` activations and
  only one sampled `pursue_weak` tick.
- Artifact: Production image `andre-battleroyale:candidate-5`, Linux AMD64,
  command `/bin/baseline`, digest
  `sha256:a6c02280b56463e8c6d92c63957ecf4703390aee17ad0353cec72678af5ff463`.
  Uploaded as unsubmitted candidate `andre-battleroyale:v6`; exact binary
  clones are `andre-trial-5:v1` and `andre-trial-5:v2`.
- XP id: Baseline `xreq_f723f86c-e236-4d83-bd64-fb8e56c0d6ec`;
  candidate `xreq_dfff8be7-f991-4864-8e41-59702ab302a6`.
- Opponents: At launch Andre remains #9 at 1466.38. The frozen nearest other
  players are softmaxwell (`Picasso:v62`, 1425.82), NanosaurusX
  (`nancy-br:v1`, 1355.24), and David Greis
  (`Battle Royale Baseline:v1`, 1330.31).
- Verdict: Reverted. The required hosted field did not exercise the intended
  equal-HP pursuit branch, so its score delta cannot be trusted. The 10 hosted
  episodes per side were also inconclusive: candidate minus baseline was
  `1.5000`, with a two-sided 95 percent Welch interval
  `[-50.1207, 53.1207]` and `p=0.951291`. The equal-HP feature was removed;
  `andre-battleroyale:v6` remains unsubmitted.

### Trial 4: wider safe hunter arm detour

- Idea: `tools/summarize_artifacts.nim` aggregated all 10 Trial 3 candidate
  artifacts. Because `pact_converge` never fired, their navigation is
  equivalent to the submitted hunter. Mean armed fraction was only `0.4496`:
  22,706 ticks were spent holding the passive band and 8,815 retreating from
  the ring, versus 1,313 gun-trip ticks. On the huge map, the 240-pixel gun
  cap is preventing safe arming opportunities. A 480-pixel cap should improve
  armed time while retaining the existing ring-safe, opponent-closer, and
  30-second trip guards.
- Change: Set only `FfaHunterArmTripMaxDetourRadiusDefault` from `240.0` to
  `480.0`.
- Isolation: Passed locally. `tools/extract_doctrine.nim` compared the exact
  submitted control at `240.0` with the candidate at `480.0`; both start as
  hunter and their other printed doctrine settings are unchanged. The
  extractor also asserted the production Docker image. Hosted logs confirmed
  240 in control episode request
  `ereq_f31facac-f594-400f-aa70-e1c7d405bcdd` and 480 in candidate request
  `ereq_075eee63-fc5a-4dec-853b-63c759e68c9f`. Their artifacts confirmed the
  behavior fired: the control stayed unarmed with one gun-trip tick, while the
  candidate reached armed fraction `0.1474` through six trips and 107 gun-trip
  ticks. This diagnostic is not used as score.
- Artifact: Production image `andre-battleroyale:candidate-4`, Linux AMD64,
  command `/bin/baseline`, digest
  `sha256:a07a81f930209baa1d0e30683a5bdb0f31bec3c88bdccabebf7a1ccefbd67ade`.
  Uploaded as unsubmitted candidate `andre-battleroyale:v5`; exact binary
  clones are `andre-trial-4:v1` and `andre-trial-4:v2`.
- XP id: Baseline `xreq_20f9ec0a-b835-4425-8279-e55cc31b5c4c`;
  candidate `xreq_3a955072-9763-42a7-8412-fc7bbf877ea4`. The 20-episode
  extension uses baseline `xreq_25147606-5ff3-4602-9603-67f7acaefa85` and
  candidate `xreq_2107680c-82fc-4ed6-a167-835e4fe1458e`.
- Opponents: At launch Andre is #9 at 1466.38. The frozen nearest other players
  are softmaxwell (`Picasso:v62`, 1425.82), NanosaurusX (`nancy-br:v1`,
  1355.24), and David Greis (`Battle Royale Baseline:v1`, 1330.31).
- Verdict: Reverted. The first 10 hosted episodes per side were inconclusive.
  Candidate minus baseline was `19.8000`, with a two-sided 95 percent Welch
  interval `[-46.0627, 85.6627]` and `p=0.527068`. Twenty more hosted episodes
  per side used the same frozen field. Across all 30 episodes per side,
  candidate minus baseline was `5.1000`, with a two-sided 95 percent Welch
  interval `[-25.1892, 35.3892]` and `p=0.736958`. This remains inconclusive,
  so the default returned to `240.0`; `andre-battleroyale:v5` remains
  unsubmitted.

### Trial 3: pact doctrine default

- Idea: Coworld v0.1.13 added the pact doctrine and alliance broadcast cue.
  Pact retains hunter arming, pursuit, combat, and late-close behavior, but in
  the opening 35 percent of ring shrink it detects a nearby two-player brawl,
  focuses the weaker participant, and temporarily avoids targeting the other.
  That should reduce early two-front fights while preserving hunter behavior
  when no pact opportunity exists.
- Change: When `CTF_BOT_FFA_DOCTRINE` is unset, select `FfaPact` instead of
  `FfaHunter`. No pact or hunter parameter is changed.
- Isolation: Failed behavioral coverage. `tools/extract_doctrine.nim` compared
  the exact
  current-champion commit with the candidate: the control starts as `hunter`,
  the candidate starts as `pact`, and their printed hunter arming, pursuit,
  detour, and ring controls are identical. The extractor also asserted the
  production Docker image directly. Hosted logs confirmed `ffaDoctrine=pact`,
  but `tools/extract_artifact_objective.nim` found zero `pact_converge`
  activations across all 10 candidate artifacts. The required field never
  exercised the strategy branch.
- Artifact: Production image `andre-battleroyale:candidate-3`, Linux AMD64,
  command `/bin/baseline`, digest
  `sha256:9973a7615cb590828cc6523ae5f3bd21e8cef015e1c34a8886da5106176289d3`.
  Uploaded as unsubmitted candidate `andre-battleroyale:v4`; exact binary
  clones are `andre-trial-3:v1` and `andre-trial-3:v2`.
- XP id: Baseline `xreq_2ae41f83-9cdc-4cc5-83de-93031a66ee7b`;
  candidate `xreq_140f031d-481e-4059-ba60-f60593ce3ec5`.
- Opponents: At launch Andre is #9 at 1414.73. The frozen nearest other players
  are softmaxwell (`Picasso:v62`, 1383.44), NanosaurusX (`nancy-br:v1`,
  1377.97), and aosgoods (`eatth-battleroyale-decision-stack-v29:v1`,
  1364.67).
- Verdict: Reverted. The 10 hosted episodes per side gave candidate minus
  baseline `23.2000`, with two-sided 95 percent Welch interval
  `[-28.0189, 74.4189]` and `p=0.353880`, which is inconclusive. More
  importantly, no hosted candidate artifact exercised `pact_converge`, so the
  delta cannot be trusted as a strategy measurement. The default returned to
  hunter; `andre-battleroyale:v4` remains unsubmitted.

### Trial 2: conservative hunter ring margin

- Idea: The hunter artifact spent 298 ticks retreating to the safe zone and
  switched objectives 219 times while holding the ring boundary. Keeping its
  radial band 80 pixels inside the safe radius should reduce boundary churn
  and late ring exposure without changing combat, looting, or pursuit.
- Change: Set only `FfaHunterRingMarginDefault` from `0.0` to `80.0`.
- Isolation: Passed locally. `tools/extract_doctrine.nim` asserted that the
  current champion starts with `ffaHunterRingMargin=0.0` and the candidate
  starts with `ffaHunterRingMargin=80.0`; both start with the hunter doctrine
  and the other printed doctrine parameters are unchanged. Hosted logs passed
  the same assertions: baseline episode request
  `ereq_435ab7d1-5684-4311-b2af-0d4595703a40` reported margin `0.0`, while
  candidate episode request `ereq_66344e74-8c68-4aba-a4b0-31d5b052489b`
  reported margin `80.0`. Their artifacts also show the navigation path fired:
  the control logged 490 `retreat_ring` ticks and 253 objective edges, while
  the candidate logged 136 retreat ticks and 193 objective edges. This
  one-episode diagnostic is not used as score.
- Artifact: Production image `andre-battleroyale:candidate-2`, Linux AMD64,
  command `/bin/baseline`. Uploaded as candidate `andre-battleroyale:v3`,
  policy version `ff38a716-95eb-4bc6-af35-e18e1897c31f`. Exact binary clones
  were uploaded as isolated `andre-trial-2:v1` and `andre-trial-2:v2`.
- XP id: Baseline `xreq_ba1db1dd-c9e2-4fca-b716-05a95c557053`;
  candidate `xreq_5378d2a7-2120-454f-8f44-ebacc53d6047`.
- Opponents: At Andre's #12 MMR of 1338.99, the three nearest other players
  are David Greis (`Battle Royale Baseline:v1`, 1332.13), softmaxwell
  (`Picasso:v62`, 1353.03), and NanosaurusX (`nancy-br:v1`, 1426.65).
- Verdict: Reverted. The first 10 hosted episodes per side were inconclusive.
  Candidate
  minus baseline was `18.4000`, with two-sided 95 percent Welch interval
  `[-26.9607, 63.7607]` and `p=0.404339`. Twenty more hosted episodes per side
  on the same frozen field used baseline
  `xreq_74812ceb-51ef-484c-80fe-e5254d6b62c8` and candidate
  `xreq_106bc2fb-8a0d-4cea-88a1-09cfea7a8dff`. Across all 30 episodes per
  side, candidate minus baseline was `6.1667`, with two-sided 95 percent Welch
  interval `[-28.6703, 41.0036]` and `p=0.724373`. This is inconclusive, so the
  default returned to `0.0`; `andre-battleroyale:v3` remains unsubmitted.

### Trial 1: hunter doctrine default

- Idea: The newly added hunter doctrine should outperform the legacy example
  by arming early, pursuing weaker targets, and closing sooner in the late game.
- Change: When `CTF_BOT_FFA_DOCTRINE` is unset, select `FfaHunter` instead of
  `FfaLegacy`. No hunter parameter is changed.
- Isolation: Passed. `tools/extract_doctrine.nim` ran the compiled policy with
  the doctrine environment variable removed and captured
  `ffaDoctrine=hunter`, `ffaHunterArm=true`, and `ffaHunterPursuit=true`.
  `tools/extract_hosted_doctrine.nim` then confirmed `ffaDoctrine=legacy` in
  the clean v1 hosted log and `ffaDoctrine=hunter` in the clean v2 hosted log.
- Artifact: `andre-battleroyale:v2`, policy version
  `6e71ddba-557d-4f19-861e-3add5441f0d9`.
- XP id: Baseline `xreq_dcc0888b-4175-4fbd-9a17-1dd04dcc48d5`;
  candidate `xreq_8a17f619-bfc0-432c-a4da-4df7fbb5af4d`. Those names also
  appeared in unrelated requests, so their aggregate dashboard bands are not
  a valid verdict. Exact binary clones were uploaded as isolated
  `andre-trial-1:v1` (`7c854c18-a236-4c02-96be-c473e75e6aba`) and
  `andre-trial-1:v2` (`43769fa5-2407-46d3-a811-54c16968a206`). Their clean
  baseline XP is `xreq_0cdfdd6c-a6a3-4b83-ae56-bf5bd0b6cbc0`; their clean
  candidate XP is `xreq_add55551-afc6-4947-b615-ba887b99b0da`.
- Opponents: At Andre's #11 MMR of 1435, the three nearest other players were
  David Greis (`Battle Royale Baseline:v1`, 1441), sivannn
  (`sivan-br-ringsurfer:v1`, 1470), and NanosaurusX (`nancy-br:v1`, 1479).
  Both requests pin this exact field, use four agents, rotate seats, and run 10
  hosted episodes.
- Verdict: Kept. The first clean 10 episodes per side were inconclusive, so the
  same field was extended by 20 episodes per side with baseline XP
  `xreq_f59f6778-4940-4ceb-8062-cd72b8d56909` and candidate XP
  `xreq_a334c9cc-21f9-4fec-a992-8a21a4260e1e`. Across all 30 hosted episodes
  per side, `tools/compare_xp_scores.nim` found a candidate score improvement
  of 62.30 with a two-sided 95 percent Welch interval of 13.59 to 111.01 and
  `p=0.013249`. The interval clears zero, so the candidate is significantly
  better on the exact frozen field. Submitted as champion with submission
  `sub_8830f756-8b27-4e9f-ae85-073e21ca9fb9` and active membership
  `lpm_824d7092-f9c1-4bd5-8f39-1d3e492284be`.

### Bootstrap 0: current example champion

- Idea: Establish a working submitted champion before experiments.
- Change: No behavior change. Build the current upstream
  `players/baseline/baseline.nim` example with its default legacy FFA doctrine.
- Artifact: `andre-battleroyale:v1`, policy version
  `ecaaf746-1b7c-46f8-a66b-746bd192be7a`, submission
  `sub_6df85778-353f-4e4c-baac-9b8b20af7019`.
- XP id: N/A. There is no submitted policy to use as a baseline.
- Opponents: N/A. The initial champion is the explicit no-submission bootstrap.
- Verdict: Kept as the initial champion. The submission placed successfully and
  its league membership is active.
