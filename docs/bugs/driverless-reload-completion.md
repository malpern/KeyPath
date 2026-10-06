# Reload acceptance is not completion

The signed d293fe84e held-Caps trial exposed a false-success path. The server
accepted Reload(wait:true) at19:40:44.063, but25 interleaved repeat broadcasts
exhausted the client's read limit by19:40:46.101. The client then reported
success without ReloadResult. Actual ConfigFileReload appeared at19:40:50.582,
when the physical key was released.

Same-mode deferral while keys remain held is intentional Kanata behavior. Do
not force early release to satisfy the original experiment's mistaken gate.
Mode-change retirement remains a separate path and passed early Control release.

The client now separates unsolicited broadcasts from command responses, keeps
the absolute deadline, bounds broadcasts to512 lines/1MiB, and requires confirmed
completion. Missing completion fails and closes the connection. CurrentLayerName
is treated as unsolicited only within this reload wait, leaving other operations
unchanged. A timeout means completion was not confirmed; it does not cancel an
already queued engine reload.

Independent source review passed. All64 TCPClientRobustnessTests passed, including
four socket regressions for delayed completion after repeats, missing completion,
broadcast-limit exhaustion, and unsolicited layer notifications. Accessibility380
and whitespace checks passed. Final log: `/private/tmp/keypath-reload-wait-tests-final.log`.
The first63-case run passed before review follow-ups; an agent's intermediate
invocation failed before tests because nested SwiftPM sandboxing was unavailable.
Root's final approved runner executed all64 with zero warnings/errors.

Live verification of this correction is pending. Preserve the failed reload
receipt and require confirmed deferred completion, unchanged ownership/map/journal,
post-release state and a fresh physical remapping sample on the next signed build.
Raw trial: `/private/tmp/keypath-held-transition-d293-live-01`.
