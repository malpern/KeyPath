# CLI service control bypassed the privileged helper

## Symptom

`keypath-cli service stop` failed for a normal user with `Not privileged to signal service`.
`service start` had the same authorization defect, and `service restart` composed both paths.

## Root cause

`SystemFacade` invoked `launchctl kill` and `launchctl kickstart` directly even though the
bundled CLI is an explicitly trusted client of KeyPath's privileged XPC helper. The commands
therefore depended on the caller already being root instead of using KeyPath's authorization
boundary.

## Resolution

The helper protocol now exposes narrowly scoped start and stop operations for the fixed
`system/com.keypath.kanata` service target. `SystemFacade` calls those operations and retains
its independent runtime postcondition checks. The helper contract version was advanced so an
older helper cannot be mistaken for a compatible one.

Lifecycle commands now bootstrap the same runtime dependencies as `service status`, invalidate
pre-transition health evidence, and poll fresh snapshots. Startup verification allows for the
LaunchDaemon's 10-second throttle interval. Without those pieces, the privileged operation could
succeed while the CLI falsely reported failure because it had no launchctl targets or reused a
pre-transition snapshot.

`CLIPrivilegeBoundaryLintTests` scans the CLI source surfaces for direct `launchctl`, `sudo`,
`osascript`, and generic privileged-command execution. Installer, repair, and uninstall remain
on the existing installer privilege broker.

## Verification

- The supported CLI lifecycle suite passes.
- The privilege-boundary lint passes.
- The installed normal-user CLI completes `service restart --json` without `sudo` and reports
  `{"restarted": true}`.
- The installed app returns to an operational state with a fresh helper, running Kanata, and
  healthy VirtualHID.

## KeepAlive follow-up

Local release acceptance found that routing stop through the helper was necessary but not
sufficient. The helper initially sent `SIGTERM` to the registered KeepAlive job. Launchd accepted
the signal and immediately respawned Kanata, so the CLI's stopped postcondition timed out and
reported `Could not stop Kanata service`.

The helper now disables `system/com.keypath.kanata` before signaling it. Start and restart
explicitly re-enable the job before kickstart, and an unexpected signal failure restores the
enabled state.

A second installed-app acceptance run exposed a launchd ordering detail: after `launchctl
disable`, `launchctl kill system/com.keypath.kanata` could no longer resolve the target even
though its existing process was still alive. The helper now captures the registered service PID
before disabling the job, then signals that exact PID after the disable succeeds. The helper
contract advanced to 1.3.2 so installations cannot retain either earlier behavior while
reporting the helper as fresh. A lifecycle lint test preserves the required
inspect-before-disable-before-signal and enable-before-kickstart ordering; installed-app
acceptance verifies the real launchd transition.

The next acceptance run proved that even direct PID signaling is insufficient: launchd respawns
an already loaded KeepAlive job after `launchctl disable`. The CLI lifecycle facade now uses the
same `SMAppService` register/unregister ownership path as the KeyPath UI. Stop unregisters the
daemon and verifies both registration and process removal, start registers it, and restart
performs those operations in order. If macOS leaves a stale job across an app replacement, stop
retries the owning API once before using the existing helper-backed privileged cleanup. The
helper remains the privilege boundary for operations that require root, but it no longer tries
to emulate the owning app's SMAppService lifecycle with launchctl signals.
