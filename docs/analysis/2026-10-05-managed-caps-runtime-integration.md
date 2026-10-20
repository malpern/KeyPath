# Managed Caps runtime integration — experimental

The driverless worker can now connect an owned device-scoped Caps→F18 mapping to
logical Caps input in the unchanged Kanata configuration. This adds no driver,
daemon, root helper or permission. Accessibility and Input Monitoring remain
required. The path is DEBUG-only opt-in and has not yet passed integrated physical
acceptance; ordinary launches retain raw Caps refusal.

## Selection and scope

Set `KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE` to JSON encoding the exact
`SessionCapsMappingPolicy.DeviceIdentity`, and
`KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18=1`. The existing lifecycle owner
passes only these experimental settings to its worker. The device registry ID
must identify the current event service, never its USB ancestor. The initial
prototype accepts exactly one eligible physical keyboard, with native F18
explicitly reserved. Another keyboard's F18 is indistinguishable in session
input; the setting is a test eligibility declaration, not attribution.

The canonical configuration validator first checks ordinary session eligibility.
Only a rejected ordinary profile with a valid experimental selection may request
the additive managed-Caps parser. Caps input is supported; Caps/F18 output,
native F18 input and unsupported source/repeat/override/chord paths refuse.
Switching either direction between ordinary and managed profiles restarts through
ServiceLifecycleCoordinator. Same-mode changes use ConfigReloadCoordinator's
existing validated TCP route. Successful mode changes require a current running,
active-tap, nonce-bound worker report.

## Startup, input and retirement

The main configuration digest is anchored before validation and checked after
validation and runtime construction. It is provenance for the main file, not a
claim to atomically attest included files. Startup requires representable keys up
and the Caps latch off. While the tap is disabled, the worker executes mapping
acquisition off-main synchronously; shutdown cannot reenter acquisition. Ownership
and the actual journal directory are retained before any write, including thrown
write/readback paths. A second all-up check precedes activation.

Only active managed F18 input becomes logical Caps, before mapped-key lookup and
held-input tracking. Repeat/release requires an admitted press from the same
lease generation. Raw Caps remains physical. The worker forbids generated Caps
and reserved F18 output. Ordinary native-F18 profiles keep their existing path.
Device/mapping verification runs off-main periodically; a lost instance or changed
mapping retires conservatively rather than guessing a reconnect identity.

Shutdown disables the tap, revokes ingress, releases generated keys, attempts
owner-bound mapping restoration, publishes the terminal report and acknowledges
power retirement. A surviving parent restores after worker death under the
existing lifecycle operation gate. A surviving worker handles parent exit. If
both owners died, next launch may recover only exact owned same-boot/device state.
Foreign edits, ambiguity, changed boot/device and reused live PIDs refuse recovery.

Every HID write now has a fsynced mutation-in-flight marker. The marker is removed
only after the transport confirms its child exited; a failed write still retains
intent. Forced death during a write can leave an orphan helper, so a surviving
marker refuses automatic recovery/restart. No elapsed-time or dead-owner heuristic
clears it. This case requires exact-writer reconciliation before any future manual
recovery mechanism; immediate restoration is not promised.

## Verification and remaining acceptance

Pure input generation cases, actual bridge admission, configuration mode-change
cases, lifecycle interleaving, report compatibility and journal/marker regressions
are tested without host HID writes. Independent source review found no remaining
blocker in this scope. The previous live mapping-only receipt does not verify this
integrated runtime.

Next signed guest acceptance: physical Caps tap/hold, normal stop and failed
activation, same-mode and mode-changing reloads, worker/parent and both-owner death,
Secure Input with Caps held, reconnect/reboot refusal, and forced death during
mutation retaining the marker. Secure resume still requires all keys released;
otherwise the existing lifecycle reports a refused start. General keyboard
support and onboarding UX remain later work. No current VM is owned.

Final focused actual-package run:82 passed, zero compiler/test/app warnings or
errors,26s incremental build and4s tests. Log
`/private/tmp/keypath-caps-runtime-final-tests-v2.log`. Durable lease/marker runner
passed in `/private/tmp/keypath-caps-runtime-marker-tests.log`; accessibility380
passed. Earlier integrated test runs exposed a missing enum argument label and an
actor-isolation annotation; both were corrected before this final run.
