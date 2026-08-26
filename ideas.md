# Battle Royale climb

## Current state

- League: Battle Royale, Coworld `battleroyale` v0.1.13.
- Player: Andre von Houck (`ply_607f17a2-3acf-405b-91fe-d12ef1001c00`).
- Submitted policy: `andre-battleroyale:v2`.
- Upstream policy base: `a39eb196131ac0083506bb344130359de1c2d9c8`.

## Backlog

- Switch only the FFA doctrine from legacy to hunter.
- Add only a conservative hunter ring-safety margin.
- Allow only safe hunter pursuit against equal-HP opponents.
- Move only the hunter hold band deeper inside the safe radius.
- Prefer only a vulnerable hunter target over a closer strong opponent.
- Allow only safe hunter upgrades after initial arming.
- Kite only visible nearby heavy-gun threats while preserving hunter fire.
- Shorten only the hunter opening arm-trip deadline.
- Reduce only the hunter arm-trip detour radius.
- Switch only the FFA doctrine from legacy to passive.
- Switch only the submitted hunter doctrine to passive.
- Switch only the FFA doctrine from legacy to shade.
- Switch only the FFA doctrine from legacy to pact.
- Inspect hosted artifacts for avoidable unarmed time, ring damage, and
  target-contact gaps, then add one evidence-backed idea at a time.

## Trial log

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
- Isolation: Pending production and hosted artifact checks. The 30 hosted
  control replays and the replay summarizer are diagnostics, not score.
- Artifact: Pending CPUX build and upload.
- XP id: Pending same-field hosted requests, at least 10 episodes per arm.
- Opponents: Pending a fresh nearest-MRR field at request launch.
- Verdict: Pending hosted significance.

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
