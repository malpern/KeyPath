# TCP configuration snapshot leak

## Symptom

After receiving a canonical `SystemSnapshot`, `MainAppStateController` read and
parsed the installed daemon plist again to decide whether the app was healthy.
That second observation could disagree with the snapshot used by the wizard,
installer planner, CLI, and menu surfaces.

## Root cause

`HealthStatus` captured TCP responsiveness but not whether the daemon was
configured to launch Kanata with a valid TCP port. Presentation code filled the
missing evidence with its own filesystem probe.

## Fix

- `HealthStatus.kanataTCPConfigured` now carries the raw optional fact.
- `SystemValidator` reads the active bundled daemon plist during canonical
  capture and validates that `--port` is followed by a numeric port in the
  valid range.
- Captured `false` configuration makes service health incomplete. Nil remains
  backward-compatible for older fixtures and unavailable fallback snapshots.
- `MainAppStateController` derives its published TCP status directly from the
  snapshot and no longer reads or parses the plist.

## Regression coverage

`SystemValidatorTests` covers valid, missing, malformed, and out-of-range TCP
arguments plus health classification. `SnapshotConsumerLintTests` prevents the
controller-level plist probe from returning.
