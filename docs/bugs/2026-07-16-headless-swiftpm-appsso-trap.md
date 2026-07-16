# Headless SwiftPM AppSSO trap on macOS 27

## Symptom

`swift build --build-tests` can exit 133 while SwiftPM materializes Sparkle's
binary artifact on the macOS 27 Mini. No KeyPath source has compiled yet. The
crash is `EXC_BREAKPOINT / SIGTRAP` in `swift-package`.

## Root cause

The failure follows the runner execution context, not the commit or hardware.
Two failed PR attempts ran on `keypath-mini`, a system LaunchDaemon. The same
commits passed unchanged when rerun on `keypath-mini-2`, a LaunchAgent in the
logged-in `clawd` GUI session.

The macOS crash reports show this stack on an `NSURLSession` worker:

```text
_xpc_api_misuse
xpc_connection_set_target_uid
SOServiceConnection
SOConfigurationClient
AppSSO::shouldManageURL
NSURLSession
```

macOS 27 AppSSO is attempting an invalid target-UID handoff for the headless
system launch domain. `libxpc` deliberately traps. Sparkle is only the trigger:
its SwiftPM binary target causes the URLSession request that reaches AppSSO.

The failing attempts were GitHub Actions run `29520333429` attempt 1 and run
`29521172200` attempt 1. Their unchanged attempt 2 reruns passed on the
interactive runner. The corresponding crash reports on the Mini are
`swift-package-2026-07-16-103852.ips` and
`swift-package-2026-07-16-105007.ips`.

## Containment

- Only the interactive `keypath-mini-2` registration carries the custom
  `swiftpm-safe` label.
- Workflows that invoke `swift build` or `swift test` require that label.
- Lightweight jobs such as code quality and runner health remain eligible for
  either runner.
- The boot-available headless runner remains registered, but must not receive
  the `swiftpm-safe` label while this macOS behavior persists.
- The scheduled runner-health workflow audits the live GitHub runner labels
  every six hours and fails if that boundary drifts. Runner labels are GitHub
  registration metadata, not local LaunchDaemon configuration, so the service
  installer also preserves an explicit warning at the point of maintenance.

This makes scheduling fail closed: if the logged-in runner is unavailable, a
SwiftPM job queues instead of running in a context known to crash.

Serializing SwiftPM work onto one runner is an accepted temporary capacity
tradeoff. The second runner still handles lightweight work in parallel; adding
`swiftpm-safe` to the headless runner merely to regain throughput is unsafe.

## Re-enable criteria

Do not return SwiftPM jobs to the headless runner based on a warm-cache pass.
On a newer macOS seed, run a cold probe that removes only the probe's disposable
scratch directory and materializes Sparkle from `Package.resolved`. Re-enable
the label only after that probe passes repeatedly without an AppSSO crash
report. Preserve the crash reports for an Apple Feedback Assistant report.
