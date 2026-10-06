# Driverless installed-app verification

The release verifier required `system/com.keypath.kanata`, which the driverless
package deliberately omits. Release Doctor also reported registration and an
unowned TCP connect as independent runtime signals. Both now call the same
read-only `Scripts/verify-session-runtime.py`; no system service is required or
changed. Installed-app verification retains resource/rpath/CLI identity checks,
strict signature verification, Gatekeeper assessment and staple validation.
`CHECK_RUNTIME=0` remains trust-only and cannot qualify a running release.

The verifier matches exactly one parent and one worker of the selected app's
executable under the invoking non-root UID. macOS `proc_pidpath` and raw
`KERN_PROCARGS2` arguments preserve paths containing spaces and avoid treating a
name match as process identity. NSWorkspace launches workers through launchd;
the binding is the worker's `--session-owner`, not OS PPID. Nonce, report path
and port must match that launch. The report directory/file must be owned and
private (0700/0600), without a final symlink or hard-linked report. Reads are
bounded to the canonical 16 KiB limit. PID/UID/nonce and the Swift-reference-date
timestamp match `SessionRuntimeReport.isCurrent` (age at most two seconds,
future skew at most one). Running/tap/capability evidence is mandatory.

The loopback listener must belong to the exact worker, followed by a successful
TCP connect. Parent/worker identity and report readiness are rechecked afterward.
Wildcard and non-loopback listeners are refused. The checked-in Rust bridge
passes the numeric port through `SocketAddrWrapper`; the existing main-worktree
Kanata source at `79bd7fabb7bbb42315864dda7e364f5eafee2630` maps numeric ports to
`127.0.0.1`. The product gitlink `0853689f04d40f6b8d283fef80e34b3d53531b89`
is absent from that local submodule object store; exact pinned companion-source
provenance is not claimed and remains a full companion rebuild gate.
No process arguments, config contents or input/output events are printed. A
read-only QA script cannot introspect the UI coordinator's retained properties;
these checks bind the signed executable's cooperative worker launch and report,
and are not independent protection against a malicious process with the same UID.

Python 3 is an explicit developer-tool dependency (`KEYPATH_VERIFY_PYTHON` can
select a usable interpreter); `/usr/bin/python3` availability in a guest is not
assumed. macOS `lsof` is also required. Release Doctor warns on unverified runtime
before a build; installed-app verification fails closed after deployment.

## Remaining distribution gates

- The shipped `keypath-cli` still exposes legacy `service start/stop/restart` via
  `SystemFacade` and `KanataDaemonService`. Its status JSON/human output includes
  helper/Kanata/Karabiner fields and cannot retrieve the UI parent's retained
  session report. Config/simulator commands are separately useful; CLI service
  commands are not a substitute for this verifier. No CLI redesign is included.
- `build-and-sign.sh` builds KeyPath, CLI and Insights, and intentionally omits
  KeyPathHelper, the launcher and LaunchDaemon plists. Legacy helper authorization
  paths remain in source; package omission does not qualify every exposed CLI
  lifecycle command. Stable CLI signing identity is retained across replacement.
  Older installed-production migration remains outside this work.
- A read-only probe with the canonical Xcode 27 selection still reports
  `cannot execute tool 'metal' due to missing Metal Toolchain`. No component was
  installed. Existing cached metallib tests cannot prove fresh shader compilation;
  a fresh unmodified-plugin build remains required before distribution.
- The root's preserved accepted packaged bridge is a previously generated
  artifact. This work does not qualify a fresh Rust companion rebuild or exact
  pinned-source provenance for those bytes.
- No signed candidate was assembled, notarized, stapled, installed or launched in
  this workstream. Exact final signed app/session verification, signed UI/manual
  replacement acceptance, physical-input acceptance, final full gate and public
  release authorization remain separate gates.

## Validation

`python3 -m unittest Scripts.tests.test_verify_session_runtime -v` passes twelve
tests with synthetic owned-session/process/report/TCP fixtures and shell trust
command stubs. Adverse cases include missing/ambiguous/foreign processes,
wrong owner/nonce/port, numeric-width violations, duplicate arguments/JSON fields, stale/future/failed
reports, denied capability/inactive tap, unsafe metadata/symlinks/hardlinks,
oversized/non-regular reports, foreign/wildcard listeners, refused TCP, process/report changes during
verification, missing Python, no-evidence failure without success output,
trust-check failure and runtime failure propagation. Shell fixtures
assert the exact helper source path and SHA-256 of the imported tested helper.
`bash -n` and `git diff --check` pass. A read-only native process-path/raw-argv
probe passed against the Python test runner; the original sandboxed `ps` attempt
was refused and the scoped read-only retry was approved. No Swift build/test ran.

Canonical source inspected at product commit `762d5fe17`:

| Source | SHA-256 |
| --- | --- |
| `Sources/KeyPathCore/SessionRuntime/SessionRuntimeReport.swift` | `13ed44262bab04567f0932c065736738d01f59fe1daaa9acaa6154f1b889ea63` |
| `Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator+SessionRuntime.swift` | `b5b62c12ae53d8b158dc702c8fd89ef53b4726287f9bc457aa1cb63ffdbb0b24` |
| `Sources/KeyPathAppKit/Services/SessionRuntime/SessionRuntimeWorker.swift` | `e07403a8b380059981b4aa2b42b86387f80297bb6a14aee271b6ca3474d87e19` |
