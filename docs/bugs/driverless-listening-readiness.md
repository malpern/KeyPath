# Driverless keyboard readiness requires ListenEvent and PostEvent

October 5, 2026. Experimental branch only; guest validation of this correction is pending.

A normal macOS 26 guest with Accessibility granted and Input Monitoring denied reported
AX/PostEvent granted. The session capability probe used PostEvent as effectiveInputAccess,
so PermissionOracle reported system ready. The actual worker's registered modifying tap
contained mask4096 (flagsChanged), missing keyboard down/up from requested7168. The
worker correctly refused startup. Normal Input Monitoring consent and Quit & Reopen
produced mask7168 and passed physical q→a before and after a normal app restart.
Evidence: `/private/tmp/keypath-restart-simple-01/startup-reason-result.json` and
`permission-runtime-observe-result.json`; durable restart receipt in the permission
footprint branch at `docs/testing/evidence/2026-10-05-normal-restart.json`.

The Oracle now requires current-process AX, ListenEvent and PostEvent for session
readiness. Missing, unknown or error authorization never counts as granted. The existing
PermissionSet inputMonitoring field represents combined input/output readiness for the
session worker; provenance identifies `current-process.apple-api.listen-and-post-event`.
Raw ListenEvent and PostEvent remain separately obtained by the Oracle for experimental
tap diagnostics. No UI or lifecycle class reads permission APIs directly.

Missing worker permissions produce instructions to enable Accessibility and Input
Monitoring for KeyPath and quit/reopen it. The service page retains the coordinator's
failure detail. Existing app and Kanata permission identifiers remain distinct in wizard
messages. This fixes readiness and error reporting, without redesigning onboarding.

The earlier AX/PostEvent-only hypothesis in
`docs/testing/session-active-tap-authorization-candidate.md` is superseded by these
measured results. Historical evidence and signed artifacts remain unchanged.

Source verification: canonical Xcode27 incremental build and focused tests passed:
15 XCTest cases (wizard service evaluation and permission evidence) plus two Swift
Testing cases (64 AX/Listen/Post combinations, session snapshot readiness and typed
report decoding). Accessibility check and diff whitespace checks passed. Independent
Sol review passed after corrections. Test log:
`/private/tmp/keypath-readiness-focused-tests-v2.log`. The earlier failed test log is
preserved; it contained an incorrect expectation that a stopped process was failed.
These are source checks, not fresh signed-artifact or guest acceptance.
