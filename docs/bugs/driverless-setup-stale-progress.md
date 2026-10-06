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

## Follow-up functional review (2026-10-06)

The initial busy-state fix did not cover non-cooperative checks. A standalone
reproduction of the task-group timeout delivered a 50 ms deadline only after
746 ms: leaving a task group waits for its children, including the child awaiting
an independently created task. Cancelling the group does not cancel that task.

The wizard operation manager now waits through an AsyncThrowingStream. Completion,
failure, cancellation, and the deadline terminate the stream; termination cancels
both the inspection task and timer. A dependency that ignores cancellation may
finish later, but it cannot retain the UI's busy state or deliver a late callback.
This bounds the UI wait; it does not forcibly terminate arbitrary underlying work.

State detection now returns a snapshot instead of mutating WizardStateMachine
before the manager checks request ownership. Initial, manual, and background
checks apply accepted snapshots through updateWizardState, preserving snapshot
metadata and version tracking. Delayed communication retries and permission follow-ups retain the original
inspection request identity, so they cannot supersede a newer check even before
its result arrives. Permission follow-ups also reject superseded snapshot versions. Failed checks clear validation and expose an explicit Retry action;
refresh no longer erases existing issues before a replacement snapshot arrives.

Driverless runtime status uses the current session report. Historical privileged
daemon logs are consulted only for the privileged backend. Automatic page changes
also no longer mark the user as having manually navigated.

Regression coverage includes deadline delivery while work is still suspended,
cancellation without a late callback, out-of-order inspection completion, failure
cleanup, and automatic versus manual navigation. The auto-fix recipe timeout helper
is outside this change: recipes can mutate system state and need their own
cancellation contract before permitting overlapping retries.

Validation: 129 focused tests passed before the final delayed-retry guard; the
final broad run passed 5,378 tests with no compiler warnings (snapshot image tests
were disabled). Accessibility identifiers passed across 380 files. Independent
read-only review passed after the delayed-retry correction. Logs:
`/private/tmp/keypath-onboarding-review-full.log` and
`/private/tmp/keypath-onboarding-review-full-runner.log`.
These changes have not yet received a fresh signed-app onboarding run.
