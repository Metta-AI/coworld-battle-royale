# Battle Royale climb

## Current state

- League: Battle Royale, Coworld `battleroyale` v0.1.13.
- Player: Andre von Houck (`ply_607f17a2-3acf-405b-91fe-d12ef1001c00`).
- Submitted policy: none.
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

### Bootstrap 0: current example champion

- Idea: Establish a working submitted champion before experiments.
- Change: No behavior change. Build the current upstream
  `players/baseline/baseline.nim` example with its default legacy FFA doctrine.
- XP id: N/A. There is no submitted policy to use as a baseline.
- Opponents: N/A. The initial champion is the explicit no-submission bootstrap.
- Verdict: Pending build, upload, and champion submission.
