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

## One post-delay registration sample (October 6, 2026)

Based on production source `762d5fe17`, under the existing
`KEYPATH_TAP_TIMEOUT_EXPERIMENT` flag only. The prior measured 1.003625125-second
inline stall established a delay, not an OS disable; repeating it without more
observation would not answer that gap.

The existing startup registration now retains the owned tap's Quartz ID, options,
mask, enabled state and min/average/max latency in microseconds. After the admitted
sleep and its returned-receipt attempt, the hook arms one observation request. The
next existing timer tick first preserves the environment, Secure Input and owner
exit guards, then consumes the request before any diagnostic query and takes one
`CGGetEventTapList(128, ...)` snapshot restricted to the same ID, worker PID and
session tap point. There is no polling or retry. The timestamp is uptime nanoseconds
immediately before the query, using the same clock as the delay receipts. Permission
fields in both snapshots remain the original startup facts, not fresh permission
measurements. Startup admission still uses only the existing registration outcome,
mask and enabled checks; post-delay data makes no admission or recovery decision.

Enumeration resets min/max latency statistics for **all** enumerated taps, not just
the retained owned row. This is a bounded call count and buffer size, **not a
wall-clock deadline**: Quartz provides no cancellable/deadline form of this
synchronous API. No query runs inside the delayed callback. Invalid/nonfinite OS
latencies omit the timing metadata rather than breaking report publication. If
startup timing is absent, there is no ID-bound post-delay query. If a fatal callback,
Secure Input/environment check, owner exit or other termination wins before the
next timer tick, a post-delay snapshot may be absent. Existing cleanup is never
delayed to wait for a diagnostic sample, except for the single synchronous query
when that timer tick does run first.

Two saturating raw counters record real `.tapDisabledByTimeout` and
`.tapDisabledByUserInput` notifications before the existing tagged-output filter.
They contain no key/event payload and change no callback handling. A counter is a
raw notification observation; timer-only `tap-disabled-observed` remains distinct.
The command schema, one-shot admission, requested sleep ceiling, receipt behavior,
tag filtering, fatal exits, output release and parent supervision are unchanged.

New report fields are optional and old reports still decode. Ordinary builds emit
none of these experimental observations. The standalone schema and existing hook
admission tests pass (15 adverse commands refused; unarmed hook never sleeps or
requests a query). A temporary extraction compiled the actual classifier and its
existing test body against the SDK, proving same-ID selection, foreign-PID refusal,
latency/options retention, nonfinite omission, failure classification and ABI.
Worker/helper/report/test source parses with the flag ON and OFF. Logs and binaries:
`/private/tmp/keypath-production-timeout-validation/`. The initial extraction could
not import Swift Testing outside SwiftPM; its failed log is retained, and the second
extraction runs the actual precondition-based classifier test directly. Full AppKit
integration/typecheck, signing and live timeout acceptance remain pending.

A future admitted live trial must bind the new signed binary/configuration and
compare the entered/returned delay receipts, the two same-ID samples, raw disabled
counters, terminal cause and independent held-key release/restart evidence. A high
latency or a disabled registration alone is not proof of a timeout callback. This
source change is observation only, not release qualification or authorization to
run another physical trial.
