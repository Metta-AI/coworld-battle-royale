---
name: deploying-battleroyale-coworld
description: Publish a certified battleroyale Coworld version and prove it runs in the battle-royale league, including canonical verification and a completed new-round check.
---

# Deploy the battle-royale Coworld

## Understand the deployment

Publish one `battleroyale` Coworld version. It serves the `br-12` and `br-16`
variants in the `battle-royale` league:

- League: `battle-royale`
- League ID: `league_b88a269b-0de7-4723-b1c7-06dab50fe61d`
- Division: `div_3081c20f-516e-4ff2-be40-fd97a7cdacbe`
- Baseline submission: `sub_15308443-cee2-465c-aa19-c0df9e04a173`
- Public page: https://softmax.com/battle-royale

Do not create or modify the league, division, submission, roster, or variants.

## Certify the source

Update `main` from `origin/main` and record its SHA:

```bash
git fetch origin
git merge --ff-only origin/main
git status --short
git rev-parse HEAD
```

Publish only when the `Github Actions` run for that exact SHA passes. Confirm
`main` still points to that SHA immediately before authentication and build.
The upload workflow performs the same freshness check and intentionally skips a
certified SHA that is no longer `origin/main` HEAD.

The repository workflow `.github/workflows/upload-coworld-battleroyale.yml`
contains this command sequence, but it requires the unset `SOFTMAX_TOKEN`
repository secret. Therefore perform the deployment manually with the
provisioned `SOFTMAX_USER_API_TOKEN`. Treat the workflow as the command-shape
source of truth and re-read it if it changes.

## Authenticate, build, and upload

Authenticate without printing the token:

```bash
uvx --from "coworld[auth]==0.1.34" softmax set-token "$SOFTMAX_USER_API_TOKEN"
```

Derive the version from the registry; never hand-pick it because other
publishers may advance the version:

```bash
VERSION=$(SOFTMAX_TOKEN="$SOFTMAX_USER_API_TOKEN" \
  python3 tools/ci/next_coworld_version.py battleroyale)
```

Build from the repository root:

```bash
uvx --from "coworld[auth]==0.1.34" coworld build \
  --version "$VERSION" \
  --project . \
  --compose compose.yaml \
  --template coworld_manifest_battleroyale.json \
  --output build/coworld-package/coworld_manifest.json
```

Upload with hosted smoke certification enabled:

```bash
uvx --from "coworld[auth]==0.1.34" coworld upload-coworld \
  build/coworld-package/coworld_manifest.json \
  --timeout-seconds 900 \
  --wait-hosted-smoke \
  --hosted-smoke-timeout-seconds 1800
```

## Prove the deployment

Verify the exact version independently:

```bash
uvx --from "coworld[auth]==0.1.34" coworld list --json --limit 500
```

Require a matching `battleroyale:$VERSION` row with `"canonical": true`.
Non-canonical means hosted smoke did not certify and the league will not
advance. Do not overwrite or delete older versions.

Then wait for a **new** league round. Inspect its episode records and require
`coworld_version` to equal `$VERSION`; exclude rounds already in flight on the
previous version. A completed proof should include the round ID, episode
count, episode ID when available, replay URL, last tick, survivors, total
kills, and whether the match ended by elimination or at the `8640`-tick cap.

`coworld_version` only proves the *package* changed. Then prove the *rules*
changed: read the `GameVersion` stamped in that round's replay headers and
run the ledger cross-check, per
`.agents/skills/verifying-hosted-league-version/SKILL.md`. Round and episode
records carry no GameVersion; the replay header is the only authority. Only
after both agree is the change live — and only then is it announced to
submitters, at that round boundary, never at the merge. (The 0.1.15 package
was published five hours before the GV46 commit; `main` said 46 and the board
served 45 for six days before anyone read a header.)

## Handle known deployment traps

- A first upload can fail with
  `Coworld replay viewer bundle must be uploaded first` (HTTP 400). Retry the
  exact upload command once. This race resolved on one retry during the
  `0.1.7` and `0.1.8` publications; do not retry indefinitely.
- On `0.1.6`, the CLI printed `Hosted certification: failed` after previously
  reporting hosted smoke passed and canonical, then its `coworld status` call
  returned 404. Do not re-upload for that contradiction alone: canonical
  status from `coworld list` and successful league execution are authoritative.
- Hosted certification probes the first broadcast frame for about 10 seconds.
  The initial `0.1.0` publication was rejected when FFA's 16-color art tinting
  made that frame take about 12 seconds. Treat a rendering change that slows
  first-frame generation as a deployment blocker, not merely a CI concern.
