# Driverless Setup retained progress after the runtime became ready

Observed on the MacBook Air on October 6, 2026, with the signed770 runtime.
After resetting old rules, fresh configuration generation succeeded and the
owned runtime became ready at15:26:56. Main validation reported active with
zero blocking issues, but Setup retained “Processing…” and an earlier
“Start driverless remapping” failure. The runtime report independently showed
Accessibility/input access granted, an active tap, balanced input/output counts
and no held output.

Two independent UI lifetime problems explain the mismatch:

- `WizardAsyncOperationManager` kept a completed check in `runningOperations`
  while awaiting its success callback. The initial callback clears validating
  state and then awaits permission reconciliation, so the generic operation
  overlay can remain visible and background monitoring skips the wizard.
- The service page combined a fresh running-runtime observation with old wizard
  issues. Its earlier start instruction could override running status, and the
  page did not refresh when authoritative wizard state/issues changed.

Completed operations now retire before their callbacks. Generation ownership
prevents a late old cleanup or progress update from modifying a newer operation
with the same identifier. Cancellation clears current ownership synchronously.
Service evaluation drops the obsolete daemon start/access-check instruction when a
fresh runtime is running and the captured wizard state was service-not-running;
permission and actual capture-failure issues remain blocking. State/issue
changes trigger a new service-page status observation.

Regression coverage checks suspended callbacks, same-identifier replacement,
stale start instructions, and retention of actual capture failures. This change
does not qualify genuine OS timeout recovery or broader keyboard compatibility.
