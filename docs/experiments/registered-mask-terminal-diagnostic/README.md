# Registered-mask terminal startup diagnostic

This source-only experiment records the worker report that the parent already
reads when startup is refused, immediately before `stopSessionRuntime()` removes
the nonce-scoped report directory. It does not change admission, readiness,
failure handling, held-output recovery, or cleanup. The log is diagnostic
evidence only.

The experimental `SessionRuntimeReport.experimentalTerminalStartupDiagnosticJSON`
formatter returns `nil` unless the report is a fresh failed startup for the exact
nonce, worker PID, and UID, with a report age from zero through two seconds,
zero input/output counts, and no held outputs. The envelope schema is
`keypath.session-start-terminal.v1`; it contains parent PID, worker PID, UID,
launch generation, exact nonce, capture time, report age, a bounded failure
summary, and the complete validated report object. The report schema contains
permission and tap-registration facts, not captured event contents. The JSON is
capped at 16 KiB.

## Capture during guest acceptance

After the parent reports a startup refusal, read the actual log file from the
same guest user account:

```text
~/Library/Logs/KeyPath/keypath-debug.log
~/Library/Logs/KeyPath/keypath-debug.log.1
~/Library/Logs/KeyPath/keypath-debug.log.2
```

Find the line beginning `SESSION_TERMINAL_STARTUP ` and parse the following JSON.
Correlate its parent PID, worker PID, UID, launch generation, and exact nonce
with the one start attempt. Validate `capturedAtUnixMilliseconds` and
`reportAgeMilliseconds`; the time the harness later reads the log is not the
report's freshness time. A missing, malformed, stale, foreign, or non-idle report
intentionally produces no diagnostic line. Absence of this diagnostic is not a
startup pass or a failure classification.

`AppLogger.log()` formats the timestamp and message before asynchronously
enqueuing its direct file append. This is not held in the periodic five-second
message buffer, but the append is still asynchronous; acceptance tooling must
poll and read the file after the parent returns. The logger rotates at 5 MiB and
keeps three files, and its logs can be explicitly cleared, so capture the line
promptly. A parent-process crash before its queued append completes can lose the
line; this experiment does not provide an independent collector or prove missing
reports.

No TCC or other permission API is called by the parent diagnostic formatter.

The formatter has a narrow standalone inert runner at
`Scripts/test-session-terminal-diagnostic.sh`. It compiles only the Foundation
report model and formatter contract runner, without linking KeyPath or calling
product/permission APIs. This candidate's runner has not yet been executed; root
should run it before treating these checks as passing.
