# Startup preflight tap must not become the live tap

Managed-Caps startup explicitly disables its event tap while the synchronous
mapping lease is acquired. That transition can queue `tapDisabledByUserInput`.
Installing the same port as the live tap after re-enabling it delivers the old
notification, and the worker correctly retires with `tap-disabled-by-user-input`.
An unconditional startup disable also caused ordinary driverless configs to fail.

Ordinary startup now creates one live tap without explicitly disabling it.
Managed startup retains a disabled preflight tap during the owned acquisition
and both physical-all-up checks. After activation it invalidates that port, then
creates a fresh live tap before adding its run-loop source. The old port was never
registered with the run loop, and invalidation discards its queued notifications.
A failed fresh tap creation goes through the existing termination path, including
restoration of the owned mapping lease.

No notification is ignored, no tap is automatically recovered, and the live
callback still retires immediately on timeout or user-disable notifications.
The independent periodic enabled-state check is unchanged.

Acceptance requires ordinary startup to remain live, managed startup to restore
its mapping after a failed fresh tap creation, and real live-tap disable/timeout
faults to retire the worker. Syntax-only checks do not prove those macOS behaviors;
validate them with the signed isolated guest candidate.
