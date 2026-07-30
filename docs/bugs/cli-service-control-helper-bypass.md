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
enabled state. The helper contract advanced to 1.3.1 so installations cannot retain the earlier
behavior while reporting the helper as fresh. A lifecycle lint test preserves the required
disable-before-kill and enable-before-kickstart ordering; installed-app acceptance verifies the
real launchd transition.
