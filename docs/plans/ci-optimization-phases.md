# CI & Build Optimization — Phased Plan

**Status:** Phase 2 complete
**Created:** 2026-05-17
**Prereq:** Self-hosted Mac Mini runner is live (PR #360, merged)
**PR:** #361 (Phases 1+2)

## Phase 1: Quick Wins ✅

### 1a. Lighten the pre-push hook ✅
**Done:** Replaced `swift test` (~80s) with `swift build` (~8s) in `.git/hooks/pre-push`.

### 1b. Remove no-op CI steps ✅
**Done:** Removed 3 stub scripts and their CI steps from `ci.yml`. Also cleaned up `publish-dry-run.yml` references.

### 1c. Fix the flaky ActionDispatcher test ✅
**Done:** Root cause was `TestEnvironment.isRunningTests` not detecting `swiftpm-testing-helper` (Swift Testing runner process). Also removed `#if DEBUG` guard from `diagnosticActionsEnabled` since SPM doesn't define `DEBUG`.

## Phase 2: Parallel CI ✅

### 2a. Register a second runner on the Mini ✅
**Done:** `keypath-mini-2` installed at `~/actions-runner-2` with LaunchAgent. Both runners online with labels `self-hosted,macOS,ARM64,keypath`. Verified: `build-and-test` (2m7s) and `code-quality` (11s) run in parallel on separate runners.

### 2b. Add concurrency control to ci.yml ✅
**Done:** Added `concurrency: group: ci-${{ github.event.pull_request.number || github.ref }}, cancel-in-progress: true`. Verified: stale runs get cancelled on rapid pushes.

## Phase 3: Remote Builds — SKIPPED

**Decision:** Not worth it. Incremental local builds (~15s) are fast enough that rsync overhead (~5-10s each way) eats most of the gain. Also breaks Poltergeist's ~2s auto-deploy loop and adds code-signing complexity. Same reasoning as skipping remote tests.

## Phase 4: Release Builds on Mini — DEFERRED

**Decision:** High setup cost (keychain/signing/notarization export) for a workflow that runs a few times a month. ROI improves when release cadence picks up. Revisit when Phase 5 is done.

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
| 2026-05-17 | Phase 1+2 shipped (PR #361) | Pre-push hook 80s→8s, no-op steps removed, flaky test fixed, parallel runners, concurrency control |
| 2026-05-17 | publish-dry-run.yml broken (pre-existing) | References `publish-help-to-web.sh` deleted in 2da6b5f62 — needs separate fix |
| 2026-05-17 | Skip Phase 3 (remote builds) | Incremental builds too fast (~15s) to justify rsync overhead + signing complexity |
| 2026-05-17 | Defer Phase 4 (release on Mini) | High setup cost for infrequent releases — revisit when cadence picks up |
