# TODO: Self-Hosted GitHub Actions Runner on Mac Mini

## Goal

Run CI builds on the local Mac Mini instead of GitHub-hosted runners to eliminate queue wait times and leverage warm SwiftPM caches. Builds that take 8-10 minutes on GitHub should complete in 3-5 minutes locally.

## What to set up

1. **Install the GitHub Actions runner** on the Mac Mini
   - Follow https://github.com/actions/runner — download, configure, install as a LaunchDaemon
   - Register with the `malpern/KeyPath` repo (Settings → Actions → Runners → New self-hosted runner)
   - Use labels like `self-hosted`, `macOS`, `arm64`

2. **Update CI workflows** to prefer the self-hosted runner
   - In `.github/workflows/ci.yml`, change `runs-on: macos-15` to `runs-on: [self-hosted, macOS, arm64]`
   - Same for `publish-dry-run.yml` and any other workflows that build Swift
   - Consider keeping GitHub-hosted as a fallback: `runs-on: [self-hosted, macOS, arm64]` with a timeout

3. **SwiftPM cache persistence**
   - The runner keeps `~/Library/Caches/org.swift.swiftpm/` and `.build/` between runs
   - This is the biggest speed win — no re-downloading dependencies each build
   - Consider a periodic cleanup cron to prevent unbounded growth

4. **Security considerations**
   - Self-hosted runners execute code from PRs — for a personal repo this is fine
   - If the repo ever goes public or accepts external PRs, restrict runner access to protected branches only
   - The runner runs as your user, so it has access to everything on the Mac Mini

5. **Monitoring**
   - The runner shows up in repo Settings → Actions → Runners with online/offline status
   - If the Mac Mini sleeps or reboots, the runner goes offline — configure Energy Saver to prevent sleep
   - LaunchDaemon ensures the runner starts on boot

## Current CI workflows that would benefit

| Workflow | File | Current runner | Notes |
|----------|------|---------------|-------|
| KeyPath CI | `.github/workflows/ci.yml` | `macos-15` | Main build + test, longest job |
| Publish Dry-Run | `.github/workflows/publish-dry-run.yml` | `macos-15` | Help publish validation |
| Claude Code Review | `.github/workflows/claude-review.yml` | `ubuntu-latest` | No Swift, keep on GitHub |

## Expected improvement

- **Queue time**: 30-120s → 0s (runner is always available)
- **SwiftPM resolve**: 60-90s → 0s (cached)
- **Build**: ~4 min → ~2 min (M-series vs GitHub Intel/M1)
- **Total**: 8-10 min → 2-3 min
