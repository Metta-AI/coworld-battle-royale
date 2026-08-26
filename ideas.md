# Battle Royale climb

## Current state

- League: Battle Royale, Coworld `battleroyale` v0.1.13.
- Player: Andre von Houck (`ply_607f17a2-3acf-405b-91fe-d12ef1001c00`).
- Submitted policy: `andre-battleroyale:v15`.
- Upstream policy base: `a39eb196131ac0083506bb344130359de1c2d9c8`.

## Backlog

- Switch only the FFA doctrine from legacy to hunter.
- Add only a conservative hunter ring-safety margin.
- Allow only safe hunter pursuit against equal-HP opponents.
- Move only the hunter hold band deeper inside the safe radius.
- Prefer only a vulnerable hunter target over a closer strong opponent.
- Allow only safe hunter upgrades after initial arming.
- Persist only a safe hunter gun trip while its target is fog-hidden.
- Kite only visible nearby heavy-gun threats while preserving hunter fire.
- Start only the hunter ring-retreat alarm one margin earlier.
- Add only a persistent tangential unstick burst during hunter ring retreat.
- Lengthen only the hunter ring-unstick clearance probe.
- Prefer only inward-diagonal hunter ring-unstick candidates before pure
  tangents.
- Add only a bounded low-health Hunter medkit detour.
- Extend only the hunter heavy-gun arm reach.
- Shorten only the hunter opening arm-trip deadline.
- Reduce only the hunter arm-trip detour radius.
- Prefer only the nearest safe opening gun over the highest-tier safe gun.
- Switch only the FFA doctrine from legacy to passive.
- Switch only the submitted hunter doctrine to passive.
- Switch only the submitted hunter doctrine to rush.
- Switch only the FFA doctrine from legacy to shade.
- Switch only the FFA doctrine from legacy to pact.
- Inspect hosted artifacts for avoidable unarmed time, ring damage, and
  target-contact gaps, then add one evidence-backed idea at a time.

## Trial log

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
- Isolation: Pending checks, production extraction, and hosted behavioral
  coverage.
- Artifact: Pending CPUX build and upload.
- XP id: Pending exact same-field hosted requests.
- Opponents: Pending the nearest-MRR live field at XP launch.
- Verdict: Pending hosted significance.

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
