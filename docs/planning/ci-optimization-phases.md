# CI & Build Optimization — Phased Plan

**Status:** Done
**Created:** 2026-05-17
**Completed:** 2026-05-17
**Prereq:** Self-hosted Mac Mini runner is live (PR #360, merged)
**PR:** #361 (merged) — Phases 1, 2, 5. Phases 3, 4 skipped/deferred.

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

## Phase 5: Polish & Monitoring ✅

### 5a. Build cache warming ✅
**Done:** Added `cache-warm.yml` — runs `swift build` on push to master, keeping `.build` cache warm for PR jobs.

### 5b. Disk cleanup cron ✅
**Done:** Weekly LaunchAgent (`com.keypath.runner-cleanup`) on Mini prunes `.build` dirs older than 7 days and test artifacts older than 3 days. Runs Sundays at 3am.

### 5c. Runner health monitoring ✅
**Done:** Added `runner-health.yml` — scheduled every 6 hours, reports hostname, uptime, disk, Swift version, Kanata version. Also manually triggerable.

### 5d. Remove obsolete publish pipeline ✅
**Done:** Deleted `publish-help-docs.yml`, `publish-dry-run.yml`, and `check-publish-deps.sh`. The entire pipeline was broken (referenced deleted scripts) and obsolete (help content is edited directly on gh-pages). Cleaned up stale paths-ignore entry in `ci.yml`.

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
| 2026-05-17 | Phase 5 shipped (PR #361) | Removed broken publish pipeline, added cache warming + health checks + disk cleanup |
