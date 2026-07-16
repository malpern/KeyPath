# Self-Hosted CI Runner — Mac Mini Setup

**Status:** Implemented (2026-05-17)
**Hardware:** Mac Mini (arm64, macOS 26.3.1, Xcode 26.2)
**Runner name:** `keypath-mini`
**SSH:** `ssh macmini` (user `clawd@openclaw.local`, key `~/.ssh/id_ed25519`)

## Why

GitHub-hosted `macos-latest` runners are slow and expensive:
- 10x cost multiplier vs Linux runners
- Cold `.build` directory every run (~10-15min builds)
- Must install Kanata via Homebrew each time
- Can't run event tap / accessibility tests (`SKIP_EVENT_TAP_TESTS=1`)

A persistent Mac Mini cuts CI wall time to ~2-3min and enables the full test suite.

## What Was Done

### Mac Mini Preparation
- [x] macOS 26.3.1, Xcode 26.2, Swift 6.2.3 — all pre-installed
- [x] Kanata 1.11.0 installed via Homebrew
- [x] SwiftLint 0.63.2 and SwiftFormat 0.61.1 pre-installed
- [x] SSH access verified (key-based, no password)
- [x] 926GB disk, 167GB free

### GitHub Actions Runner
- [x] Runner agent v2.323.0 installed at `~/actions-runner`
- [x] Registered with labels: `self-hosted`, `macOS`, `ARM64`, `keypath`
- [x] Installed as launchd service (auto-starts on boot)
- [x] Status: **online** in GitHub

### Workflow Updated (`.github/workflows/ci.yml`)
- [x] Both jobs: `runs-on: macos-latest` → `runs-on: [self-hosted, macOS, keypath]`
- [x] Both jobs: Added `echo "/opt/homebrew/bin" >> $GITHUB_PATH` step
- [x] `build-and-test`: Removed 3 cache steps (swift packages, build artifacts, homebrew)
- [x] `build-and-test`: Removed Kanata install step, replaced with version check
- [x] `build-and-test`: Timeout 20min → 10min
- [x] `code-quality`: Removed SwiftLint/SwiftFormat install step
- [x] `code-quality`: SwiftLint/SwiftFormat now only lint changed files (not entire codebase)

The build-and-test timeout was raised from 10 to 25 minutes on July 15, 2026.
Warm runs still complete in roughly 2-3 minutes, but cold Kanata and Swift test
rebuilds reached both the 10- and 15-minute caps while compilers were actively
making progress. In the measured 15-minute run, setup and Kanata took about 3
minutes and Swift had compiled 1,380 of 1,457 test-build steps when GitHub
cancelled it. Twenty-five minutes preserves a finite failure bound while leaving
room to link and execute the tests after a healthy cold rebuild.

On macOS 27, SwiftPM binary-artifact requests crash in AppSSO when they run from
the boot-available `keypath-mini` LaunchDaemon. The interactive
`keypath-mini-2` LaunchAgent is the proven SwiftPM execution context and carries
the `swiftpm-safe` label. Build, cache-warm, and coverage workflows require that
label; code-quality and health checks may still use either runner. See
`docs/bugs/2026-07-16-headless-swiftpm-appsso-trap.md`.

### Security
- [x] Fork PR approval set to "Require approval for all external contributors"
- [x] Zero existing forks on the repo
- [ ] Consider: runner runs as `clawd` (admin user) — could create a dedicated non-admin CI user

## Expected Improvement

| Metric | GitHub-hosted | Self-hosted Mini |
|--------|--------------|-----------------|
| Queue time | 30-120s | 0s |
| SwiftPM resolve | 60-90s | 0s (cached) |
| Build | ~4 min | ~2 min |
| Total | 8-10 min | 2-3 min |

## Workflows

| Workflow | Runner | Notes |
|----------|--------|-------|
| KeyPath CI | `self-hosted, macOS, keypath` | Main build + test |
| Claude Code Review | `ubuntu-latest` | No Swift, stays on GitHub |

## Still TODO

- [ ] Consider enabling event tap tests (remove `SKIP_EVENT_TAP_TESTS=1`) — requires granting Accessibility permission to the runner process in System Settings
- [ ] Set up a cron job to clean old `.build` artifacts weekly
- [ ] Configure Energy Saver to prevent Mac Mini from sleeping
