# Driverless update cleanup

Sparkle's postponed-install continuation previously called an installer operation that the session backend rejects, then continued installation even when cleanup failed. The session app must stop through its existing ServiceLifecycleCoordinator and verify held-output/Caps recovery before invoking the continuation.

UpdateService now uses the injected runtime stop owner. The coordinator rejects Start, Restart and automatic resume while preparation/installation is active and invalidates already queued starts. Failed cleanup pauses installation, releases this admission, and exposes an actionable error in About; Check for Updates retries the retained continuation. Abort releases admission and invalidates the continuation. A replacement handler receives fresh preparation after any suspended old attempt completes. Successful installation keeps admission until abort or process exit.

Nine focused tests cover cleanup ordering/refusal/retry, suspended aborts, replacement after abort, queued/manual/automatic starts and recovery-refusal persistence. Final logs: `/private/tmp/keypath-session-update-build-v5/`. Accessibility379 and whitespace checks passed; independent source review found no remaining blocker in this scope. Build used the established verified cached Metal artifact with the plugin restored byte-for-byte, not a fresh Metal compilation.

## Remaining release gate

Sparkle does not promise to call shouldPostponeRelaunchForUpdate for every installation, including some termination-time paths. This change validates the postponed continuation, not universal update cleanup. Test and resolve update-on-quit with preserved configuration and Caps recovery before release. Normal app Quit must remain usable during retained uncertainty; do not cancel every Quit and impede system reboot. No signed live updater acceptance or production release is claimed here.
