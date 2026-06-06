# Release Process

Use the narrowest workflow that matches the job. Most post-merge testing should
not run the full public distribution path.

## Local Development

For normal Swift/UI iteration:

```bash
swift build
./Scripts/quick-deploy.sh
```

`quick-deploy.sh` deploys to `/Applications/KeyPath.app`, re-signs locally, and
restarts KeyPath only if it was already running. It does not redeploy the
privileged helper unless `KEYPATH_DEPLOY_HELPER=1` is set.

Poltergeist is optional acceleration for focused single-agent UI/app iteration:

```bash
poltergeist start
# edit Swift files
poltergeist wait keypath
poltergeist stop
```

Do not leave Poltergeist running during parallel agent work, broad tests,
helper/service lifecycle work, or release builds. It can contend on SwiftPM locks
and restart the app unexpectedly.

## Release Candidate For Manual Testing

After a PR is merged and `/Applications/KeyPath.app` should match a real
Developer ID/notarized build:

```bash
./Scripts/release-candidate.sh
```

The release-candidate wrapper first runs:

```bash
./Scripts/release-doctor.sh --release-candidate
```

Then it delegates to `build-and-sign.sh` with fast release-candidate defaults:

- `SKIP_SNAPSHOTS=1`
- `SKIP_PEEKABOO=1`
- `SKIP_SPARKLE=1`
- `SKIP_WEBSITE=1`

It deploys to `/Applications/KeyPath.app` and runs
`./Scripts/verify-installed-app.sh` after the build.

Opt into slower work only when needed:

```bash
./Scripts/release-candidate.sh --with-snapshots
./Scripts/release-candidate.sh --with-sparkle
./Scripts/release-candidate.sh --with-website
```

Escape hatches for debugging the release scripts:

```bash
./Scripts/release-candidate.sh --no-doctor
./Scripts/release-candidate.sh --no-verify
SKIP_RELEASE_DOCTOR=1 ./Scripts/release-candidate.sh
```

## Installed App Verification

After signed/notarized deploys:

```bash
./Scripts/verify-installed-app.sh
```

This checks:

- code signature
- Gatekeeper assessment
- stapled notarization ticket
- KeyPath process
- `system/com.keypath.kanata` launchd job
- TCP readiness on `127.0.0.1:37001`

For non-notarized debug builds:

```bash
REQUIRE_NOTARIZED=0 REQUIRE_STAPLED=0 ./Scripts/verify-installed-app.sh
```

For trust-only diagnostics where KeyPath is not running yet:

```bash
CHECK_RUNTIME=0 ./Scripts/verify-installed-app.sh
```

## Public Distribution Release

Public releases are intentionally slower and should be explicit:

```bash
./Scripts/release-doctor.sh --ship
./Scripts/release.sh 1.0.0
```

Use `--dry-run` before an unfamiliar release:

```bash
./Scripts/release.sh --dry-run 1.0.0
```

The public release path may:

1. bump `CFBundleVersion` and `CFBundleShortVersionString`
2. build, sign, notarize, and staple the app
3. regenerate screenshots when not skipped
4. create Sparkle zip/appcast artifacts and a DMG
5. create a git tag and GitHub release
6. publish help content to the `gh-pages` worktree
7. update appcast/Homebrew release assets when the release script handles them

`Scripts/build-and-sign.sh` is the lower-level artifact builder used by the
release scripts. Prefer `release-candidate.sh` for post-merge manual testing and
`release.sh` for public distribution.

Releases must be notarized. Do not use `SKIP_NOTARIZE=1` or `--skip-notarize` for
public distribution; unnotarized apps trigger Gatekeeper warnings.

## Preflight Details

`release-doctor.sh` is read-only. It checks local prerequisites and state before
the expensive build starts:

- required tools (`swift`, `xcrun`, `codesign`, `security`, `git`, `gh`, `nc`)
- current git branch, dirty state, and master worktree ownership
- Developer ID signing identity
- notarytool keychain profile
- Sparkle `sign_update` when Sparkle artifacts are enabled
- `gh-pages` worktree state when website publishing is enabled
- currently installed KeyPath/Kanata runtime state
- whether Poltergeist is running

Warnings are informational by default. Use `--strict` when warnings should block:

```bash
./Scripts/release-doctor.sh --ship --strict
```

## Multi-Worktree Merge Safety

When multiple worktrees exist, `gh pr merge` may merge the PR on GitHub and then
fail locally while trying to switch to or delete a branch that another worktree
owns. Treat the local error as a prompt to verify GitHub state, not as proof the
merge failed.

Safer pattern:

```bash
gh pr merge <number> --repo malpern/KeyPath --merge --delete-branch
gh pr view <number> --repo malpern/KeyPath --json state,mergeCommit
git fetch --prune origin
```

Then deploy from the intended master worktree:

```bash
git checkout master
git pull --ff-only origin master
./Scripts/release-candidate.sh
```

If another worktree owns `master`, do the pull and deploy from that worktree.

## Sparkle Notes

Sparkle auto-update artifacts require an EdDSA signature. Public release builds
fail if `sign_update` cannot produce a signature, unless
`ALLOW_UNSIGNED_SPARKLE=1` is set for local-only testing.

Existing users get update notifications from `appcast.xml`. Release notes linked
from the appcast should remain readable in dark mode.
