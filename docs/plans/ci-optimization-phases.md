# CI & Build Optimization — Phased Plan

**Status:** Planning
**Created:** 2026-05-17
**Prereq:** Self-hosted Mac Mini runner is live (PR #360, merged)

## Phase 1: Quick Wins (same day)

Highest impact, lowest effort. Each can be a single PR.

### 1a. Lighten the pre-push hook
**Impact:** Save ~80s on every push. Eliminate `--no-verify` workarounds.
**Change:** Replace full `swift test` with `swift build` (catches compile errors only). CI on the Mini is the real safety net now.
**Risk:** Low — CI catches test failures within 2 minutes of push.
**Test:** Push a commit with a deliberate compile error (should block), push a passing commit (should be fast).

### 1b. Remove no-op CI steps
**Impact:** Cleaner logs, fewer steps, slightly faster runs.
**Change:** Remove `check-help-parity.sh`, `validate-screenshot-manifest.sh`, and `test-help-publish-regressions.sh` from `ci.yml` (all are stubs that echo and exit 0).
**Risk:** None — they do nothing today.
**Test:** CI passes without them.

### 1c. Fix the flaky ActionDispatcher test
**Impact:** Unblocks the pre-push hook from false positives.
**Change:** Investigate test ordering dependency in `ActionDispatcherTests` — "Dispatches repair helper action" passes in full suite but fails in isolation.
**Risk:** Low.
**Test:** `swift test --filter ActionDispatcherTests` passes consistently.

## Phase 2: Parallel CI (1-2 days)

### 2a. Register a second runner on the Mini
**Impact:** `build-and-test` and `code-quality` run simultaneously. Wall time drops from ~2.5min to ~2min.
**Change:** Install a second runner agent in `~/actions-runner-2` with a different name and the same labels. Each gets its own `_work` directory.
**Risk:** Medium — two concurrent Swift builds could compete for CPU/RAM. The Mini has plenty of both, but worth monitoring.
**Test:** Open a PR and verify both jobs start immediately and complete without errors.

### 2b. Add concurrency control to ci.yml
**Impact:** Prevents queued-up stale CI runs on rapid pushes to a PR.
**Change:** Add `concurrency: group: ci-${{ github.event.pull_request.number }}, cancel-in-progress: true` to the workflow.
**Risk:** None.
**Test:** Push twice quickly to a PR, verify the first run is cancelled.

## Phase 3: Remote Builds (3-5 days)

### 3a. Remote `quick-deploy` via SSH
**Impact:** Offload builds to the Mini. Laptop stays cool, builds are fast on dedicated hardware.
**Change:** Create `Scripts/remote-deploy.sh` that:
1. `rsync`s the repo to the Mini
2. SSHs in and runs `quick-deploy.sh`
3. `rsync`s the built `.app` back to local `/Applications`
**Risk:** Medium — requires syncing the full repo, handling `.build` caches, and dealing with code signing identity on the Mini.
**Prereqs:** Signing identity and developer certificates installed on the Mini.
**Test:** Run `remote-deploy.sh` and verify the app launches locally.

### 3b. Add "dd" / "df" remote variants
**Impact:** Same `dd`/`df` shortcuts but builds happen on the Mini.
**Change:** Add `dr` (deploy remote) shortcut that calls `remote-deploy.sh`.
**Risk:** Low once 3a works.
**Test:** Type `dr`, verify app deploys to local `/Applications`.

## Phase 4: Release Builds on Mini (1 week)

### 4a. Set up signing & notarization on the Mini
**Impact:** Release builds no longer block your laptop for 5-10 minutes.
**Change:**
1. Export signing identity and install on Mini's keychain
2. Set up notarization credentials (`xcrun notarytool store-credentials`)
3. Install Sparkle EdDSA key for appcast signing
**Risk:** High — code signing and notarization are fiddly. Test thoroughly before relying on it.
**Test:** Run `./build.sh` on Mini via SSH, verify the output is properly signed and notarized.

### 4b. CI-triggered release builds
**Impact:** Push a tag, Mini builds and publishes the release automatically.
**Change:** Add a `release.yml` workflow triggered on version tags that runs `release.sh` on the Mini.
**Risk:** High — automated releases need guardrails (dry-run first, confirmation step).
**Test:** Dry-run with `--dry-run` flag, then a real beta release.

## Phase 5: Polish & Monitoring (ongoing)

### 5a. Build cache warming
**Impact:** PR builds are incremental (just the diff), further reducing build time.
**Change:** Add a workflow that runs `swift build` on every push to master, keeping the Mini's `.build` cache warm.
**Risk:** Low.

### 5b. Disk cleanup cron
**Impact:** Prevent `.build` artifacts from filling the Mini's disk.
**Change:** Weekly cron job to prune old `.build` directories and runner work directories.
**Risk:** Low.

### 5c. Runner health monitoring
**Impact:** Know when the Mini goes offline before a PR gets stuck.
**Change:** Simple scheduled workflow that pings the runner and alerts (Slack/email) if offline.
**Risk:** Low.

### 5d. Move publish-dry-run to Mini
**Impact:** Skip zsh/Python install on every run.
**Change:** Switch `publish-dry-run.yml` to `runs-on: [self-hosted, macOS, keypath]`.
**Risk:** Low — the Mini already has Python and zsh.

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-05-17 | Self-hosted runner on Mac Mini | Cost, speed, warm caches |
| 2026-05-17 | Changed-files-only lint | SwiftLint was 5+ min on full codebase |
| 2026-05-17 | Fork approval for all external contributors | Security with self-hosted runner on public repo |
