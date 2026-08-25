# Battle Royale climb

## Current state

- League: Battle Royale, Coworld `battleroyale` v0.1.13.
- Player: Andre von Houck (`ply_607f17a2-3acf-405b-91fe-d12ef1001c00`).
- Submitted policy: `andre-battleroyale:v2`.
- Upstream policy base: `a39eb196131ac0083506bb344130359de1c2d9c8`.

## Backlog

- Switch only the FFA doctrine from legacy to hunter.
- Add only a conservative hunter ring-safety margin.
- Shorten only the hunter opening arm-trip deadline.
- Reduce only the hunter arm-trip detour radius.
- Switch only the FFA doctrine from legacy to passive.
- Switch only the FFA doctrine from legacy to shade.
- Switch only the FFA doctrine from legacy to pact.
- Inspect hosted artifacts for avoidable unarmed time, ring damage, and
  target-contact gaps, then add one evidence-backed idea at a time.

## Trial log

### Trial 3: pact doctrine default

- Idea: Coworld v0.1.13 added the pact doctrine and alliance broadcast cue.
  Pact retains hunter arming, pursuit, combat, and late-close behavior, but in
  the opening 35 percent of ring shrink it detects a nearby two-player brawl,
  focuses the weaker participant, and temporarily avoids targeting the other.
  That should reduce early two-front fights while preserving hunter behavior
  when no pact opportunity exists.
- Change: When `CTF_BOT_FFA_DOCTRINE` is unset, select `FfaPact` instead of
  `FfaHunter`. No pact or hunter parameter is changed.
- Isolation: Passed locally. `tools/extract_doctrine.nim` compared the exact
  current-champion commit with the candidate: the control starts as `hunter`,
  the candidate starts as `pact`, and their printed hunter arming, pursuit,
  detour, and ring controls are identical. The extractor also asserted the
  production Docker image directly. Hosted confirmation is pending.
- Artifact: Production image `andre-battleroyale:candidate-3`, Linux AMD64,
  command `/bin/baseline`, digest
  `sha256:9973a7615cb590828cc6523ae5f3bd21e8cef015e1c34a8886da5106176289d3`.
  Uploaded as unsubmitted candidate `andre-battleroyale:v4`; exact binary
  clones are `andre-trial-3:v1` and `andre-trial-3:v2`.
- XP id: Pending.
- Opponents: At launch Andre is #9 at 1414.73. The frozen nearest other players
  are softmaxwell (`Picasso:v62`, 1383.44), NanosaurusX (`nancy-br:v1`,
  1377.97), and aosgoods (`eatth-battleroyale-decision-stack-v29:v1`,
  1364.67).
- Verdict: Pending hosted XP significance.

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
