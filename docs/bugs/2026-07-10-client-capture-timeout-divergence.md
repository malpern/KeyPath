# Client capture timeout divergence

## Symptom

The main window and installation wizard each wrapped `SystemValidator` with a
separate 12-second watchdog. A timeout therefore produced client-specific state:
the main window preserved its previous context, while the wizard synthesized a
new result from whichever fields happened to be available. Other consumers had
no timeout at all.

## Root cause

Capture timeout policy lived in presentation clients instead of the canonical
system-evidence owner. `SystemSnapshotCaptureStatus.timedOut` existed, but
`SystemValidator` did not emit it for an overall capture deadline.

## Fix

- `SystemValidator.checkSystem()` now bounds every canonical capture and returns
  an unavailable snapshot with `.timedOut` evidence when the deadline wins.
- Cancellation returns the distinct `.cancelled` capture status.
- The main window and wizard no longer race their own watchdogs; both project
  the same snapshot and timeout issue through `SystemContext`/`SystemInspector`.
- The race cancels its losing operation and resumes exactly once, including when
  cancellation arrives before task setup completes.

## Regression coverage

`SystemValidatorTests` covers completion, timeout, cancellation, and prompt
return at the deadline. `SnapshotConsumerLintTests` prevents presentation-layer
capture watchdogs from being reintroduced.
