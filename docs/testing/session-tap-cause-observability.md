# Session tap failure cause observability (experimental)

Base: frozen product6a35b48dd1c5895a572414d0453594c14e8f7f58. This isolated
revision changes only the worker's existing failure strings at three exits:

| Observation | Terminal failure |
| --- | --- |
| Actual Quartz callback `.tapDisabledByTimeout` | `tap-disabled-by-timeout` |
| Actual Quartz callback `.tapDisabledByUserInput` | `tap-disabled-by-user-input` |
| Timer observes missing/disabled tap | `tap-disabled-observed` |

Only the actual registered callback path reports a timeout cause. Timer evidence
is not classified as a timeout. Existing failed state, output release, final
report, process exit, parent supervision, explicit restart, Secure Input recovery
and permissions remain unchanged. Consumers do not branch on the old generic
failure string; startup diagnostics display the report's failure as before.
No new report fields, sequence/timing receipt, synthetic callback, test hook,
callback delay, launch flag or event injection is introduced.

Verification is scoped to syntax, pinned formatter lint, consumer inspection and
diff review. No additional unit test mirrors the three diagnostic strings, and
existing ledger/report/lifecycle tests do not prove an actual OS timeout. The
canonical session process launcher already refuses unit-test hosts before
NSWorkspace operations. This source pass runs no app/unit target, product launch,
build/signing, guest, network, credential or physical-input operation.

Actual OS timeout and the later acceptance packet remain untested. A timer-first
exit provides only observed-disable evidence. Independent source review, focused
regressions, a new signed frozen artifact and separate physical execution release
remain required; an instrumented result cannot be attributed to the base binary.
