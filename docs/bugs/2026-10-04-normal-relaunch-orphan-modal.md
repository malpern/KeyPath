# Normal relaunch falsely opens orphan cleanup during bootstrap

`MainAppStateController.configure` called `OrphanDetector.checkForOrphans`
synchronously during `CompositionRoot.bootstrap`, before the application
delegate received `configureForLaunch`. The detector treats two ordinary user
data paths older than the current process as evidence of a deleted app. Those
paths also exist on every normal relaunch. Its synchronous `NSAlert.runModal`
can therefore hold bootstrap until someone dismisses a false cleanup offer.

The disposable guest's failed parent 2278 reached controller configuration and
logged orphaned user files, but never logged `configureForLaunch`. That is
consistent with this source path; no stack sample was obtained for that parent.
The separate parent-identity transport deadline failure is not evidence of this
modal and must remain a separate infrastructure failure.

The experimental fix removes the automatic startup check. Existing user data
is preserved; the legacy detector and cleanup implementation are unchanged.
Deferring the dialog or suppressing only headless launches would retain the
false classification on ordinary launches.

Validation: the complete experimental app compiled with Xcode 27 in 15.48 s,
reusing the previously verified Metal library because the local Metal compiler
is unavailable. The build-only plugin override was restored bytewise. A tiny
Foundation regression compiled verbatim old and new configure methods against
inert dependencies: the old method fails precisely the two no-cleanup-call
assertions; the new method passes. Dependency/callback assignment, repeated
configuration and monitoring branches remain covered. This is not a full test
suite, the repository's pinned Xcode 26.6 gate, or live acceptance of a rebuilt
signed guest app.

Retained evidence: `/private/tmp/keypath-orphan-startup-removal-review/` and
`/private/tmp/keypath-orphan-configure-regression/`. Next live validation must
show ordinary first launch and relaunch reach delegate configuration/runtime
without this dialog. Keyboard event delivery, actual OS tap timeout recovery
and console transitions remain separate acceptance work.
