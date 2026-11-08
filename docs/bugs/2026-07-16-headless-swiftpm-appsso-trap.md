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

## Update 2026-10-19: the swiftpm-safe runner is now a LaunchDaemon

`keypath-mini-2` was a LaunchAgent in a logged-in `clawd` GUI session. That
session has not existed since about 2026-10-15, so the agent never loaded and the
runner was offline until it was converted to the system LaunchDaemon
`com.keypath.ci-runner-2` (headless, `UserName=clawd`, `ProcessType=Standard`).
The containment above therefore no longer holds: both runners are headless.

Observed since: several cold builds on the daemon materialized Sparkle and
compiled without an AppSSO crash. The only `swift-package` reports on the Mini
were disk-write resource reports, not `_xpc_api_misuse` traps. That does
not yet meet the re-enable criteria above (a repeated cold probe). To reduce
exposure, `ci.yml` now keeps SwiftPM scratch per runner across jobs, so binary
artifacts are fetched only when that scratch is cold. If exit 133 / SIGTRAP in
`swift-package` returns, check `/Library/Logs/DiagnosticReports/swift-package*`
first; the fallback is restoring a logged-in `clawd` session for runner 2.

## Update 2026-11-08: the trap is back on both toolchains

On macOS 27.3 (`26C5035r`) the trap returned under the runner 2 daemon. Every
cold `swift-package` fetch of Sparkle's binary artifact trapped with the same
`_xpc_api_misuse` / `xpc_connection_set_target_uid` / `AppSSO::shouldManageURL`
stack, on release Xcode 27 (`27A266a`) and on Xcode-beta (`27A5194q`) alike.
`xcodebuild -downloadComponent MetalToolchain` traps the same way from the
daemon, because it also goes through `NSURLSession`. The same commands work over
ssh as `clawd`.

What avoids it: a scratch whose `workspace-state.json` already records the
artifact makes no request. `Scripts/ci/swiftpm-scratch.sh` keeps that state:

- `prepare` reuses `ci.yml`'s per-runner scratch. On a toolchain change or past
  the size cap it deletes only build products and keeps `workspace-state.json`,
  `artifacts`, `checkouts`, `repositories` and `prebuilts`. Verified locally:
  a different toolchain resolving kept state makes no fetch.
- `seed` copies that state into a fresh scratch and rewrites its absolute paths.
  `coverage.yml` seeds the checkout's `.build` from `ci.yml`'s scratch, since
  `actions/checkout` wipes `.build` every run. Coverage had not passed since
  October for two other reasons, fixed in the same change: its test bundles
  could not load `Sparkle.framework` (it now applies `run-tests-safe.sh`'s
  `PackageFrameworks` fix), and `generate-coverage.sh` looked only for the old
  single `KeyPathPackageTests` binary (it now reports across every test bundle).

A truly empty scratch (a new runner, or one whose scratch was deleted) still
fetches and traps. Warm it once as `clawd` over ssh, which does not trap:
`swift package resolve --scratch-path ~/actions-runner-2/_work/KeyPath/swiftpm-scratch`
from a KeyPath checkout.

Before changing the mini's Xcode, download that Xcode's Metal toolchain as
`clawd` over ssh (`xcodebuild -downloadComponent MetalToolchain`). A beta
Xcode's toolchain is a per-user download, so another account's copy does not
count, and the CI step that would fetch it traps.

### 2026-11-08: the switch to release Xcode 27.2

The mini now runs release Xcode 27.2 (`27B52`) at `/Applications/Xcode-27.app`.
It is an App Store install, and it updated itself from 27.0 that day. Its Metal
toolchain (`27B47`) installs as a system asset, downloaded as `clawd` over ssh.
The narrow coverage lane passed right away. The full lane failed with
`cannot execute tool 'metal' due to missing Metal Toolchain`. That had nothing
to do with AppSSO or with the toolchain being absent: `metal` ran fine under
the daemon, sandboxed or not. On 27.2, SwiftPM's own Metal build step reports
the toolchain missing whenever `SDKROOT` is set, and `Scripts/lib/xcode.sh`
exported it for every build. #1372 passes it only to cargo, through
`KEYPATH_SDKROOT`. If a future Xcode reports a missing Metal toolchain while
`xcrun -sdk macosx metal -v` works, check the environment for `SDKROOT` first.
