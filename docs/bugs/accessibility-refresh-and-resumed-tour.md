# Accessibility refresh and resumed first-run tour

Observed October 16, 2026, in a clean macOS 26.5.2 public VM account.

## Evidence and cause

After normal Accessibility consent, the Settings toggle was ON and authentication
was dismissed. The existing app refreshed every second but AXIsProcessTrusted
continued to report denied. A normal quit/relaunch recovered runtime. This proves
that application snapshot invalidation alone did not solve the observed failure;
it does not establish why macOS retained that result.

Relaunch also skipped the tour: AppDelegate considered config + Welcome seen +
healthy runtime complete, so it never entered the wizard dismissal that owns tour
presentation. The persisted tour eligibility was correct but never consulted.

## Candidate fixes and limits

- Keep welcome-led onboarding pending until the tour is actually presented. All
  launch/reopen routes share this gate and retain the existing wizard handoff.
- When native AX trust is negative, try a bounded read of Finder's AX application
  role. Only successful external access counts; missing Finder or any AX error
  remains denied. Do not read user content, TCC databases, or infer Accessibility
  from Input Monitoring. The target is independent of focus. Raw runtime-report
  trust remains the native result; effective permission can reflect proven access.
- Positive native trust follows the existing policy; this change does not claim
  to solve stale-positive revocation. Runtime readiness still needs actual worker
  capture/output verification.

Apple documents the supported read API at
https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue
and trust API at
https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions.
Neither source promises that an alternative probe cures stale trust. This remains
an experimental fix until clean denial, normal live grant, focus changes and the
actual runtime/tour have passed in the VM.

Evidence before fix:
`/Users/malpern/keypath-review-evidence/20261016-replacement-qualification`.
Current run: `/private/tmp/keypath-oct17-onboarding`.

## October 17 candidate validation

The signed ARM64 candidate archive is `0035f96a35940353880a30740f46eb0e659b0f94dffca2aca459c68387d357ed`, executable `5ae3cb18f063e6ca9d4d04158ab8b506f3d880f47a27618b0f3bc9c9e68c8f32`. All 54 focused tests pass. On disposable macOS26.5.2 public account, original app PID2024 correctly reported both effectiveAX and rawAX denied before consent, displayed Welcome then Accessibility, and dismissed the launch splash. This is a functional replacement in an unused account, not a pristine-installer qualification. Normal Settings consent succeeded: the same app PID 2024 started worker 8112 and the runtime verifier passed without relaunch. The native AX trust result itself changed to granted on this run, so this is a normal-grant regression pass, not a reproduction proving the stale-negative fallback. The first-success tour appeared automatically. Remaining UI checks are in progress.

Parallels had updated to27.0.3; the old exact SDK pin correctly refused. A separately frozen controller passed static ABI review,15 offline tests and25 live transport calls. An install that lost its nativeCLI reply was proven complete from its original nonce-bound receipts and signed Python identity; it was not replayed. Check the current installed transport pair before future guest preparation.


### Findings during the live tour

- Reopening KeyPath while the tour was visible brought the floating keyboard above
  it. The candidate fix keeps the overlay gated while the tour owns focus and
  routes reopen back to that tour; live retest is pending.
- Applying the first Caps Lock lesson saved the rule but returned saved-not-active.
  The existing worker remained healthy. Read-only validation of the exact saved
  config against the installed managed-Caps bridge passed (bridge SHA256
  `a7c579664fd12fe72aa9503da763e037aa1499e2d3f0f5d5c9a37fbe12544f22`).
  This rules out that validator rejecting the saved rule; the exact reload failure
  is not present in the release log and remains under investigation.


### Follow-up fixes from the same UI pass

The guest inventory contains only the Parallels virtual keyboard, which the
physical Caps selection policy deliberately excludes. Preparation happens before
stopping the existing worker. A generation-bound failure reason now travels
through the reload result into the tour; no shared error is cleared or reused.
63 focused lifecycle/reload/tour tests pass. The ESP32 (serial 2884855553BC) initially belonged to another active lease.
It was attached only after independently observing it unassigned, then verifying
our exact VM UUID and the guest USB keyboard inventory.

A saved Caps rule then prevented startup on this keyboard. Settings previously
hid all rule controls while stopped, making recovery require manual file editing.
Rules now remain editable with their existing validation/ownership checks; an
ordinary edit still does not start a manually stopped runtime. The wizard also
ignored persisted Welcome completion when no helper was installed. It now uses
the existing Welcome gate, retaining fresh-install and explicit force behavior.
The combined focused suite passed 91 tests with zero Swift warnings (73 seconds build, 4 seconds tests). Combined candidate D live results are recorded below.


The General Settings window measured 680×630 points on a 1020×616-point guest
display, extending 44 points below the screen. Its contents already scroll; the
root's 550-point minimum plus toolbar chrome prevented fitting. The minimum is
now 400 points; live verification measured bounds [170, 30, 680, 480], fully inside the guest display.

For the resumed-tour test only, the stopped disposable app's
`onboarding_first_success_shown` preference was changed from true to false.
Welcome completion and normal Accessibility consent were preserved. This is an
explicit functional test fixture, not a second clean installation claim.

### Combined candidate D live checks

Archive `deca433f69f01585150cc77f7b94544b02eb56eb5f336fef211fdaf875c751c9`,
main executable `dee58d6babfd0fa5a411ae2ddbf853c17c4dac1c529bc7ea13eacb04c20b00d4`.
Guarded replacement verified, parent PID10089/worker10338 passed the owned runtime
verifier. The interrupted-tour fixture resumed at step1 without repeating Welcome.
Normal app reopen retained the tour in front. Caps lesson UI applied successfully
and exposed its practice button. ESP32 physical short tap produced exactly Escape
down/up (keycode53), no repeats/unmatched events, no held keys/modifiers, and an
empty worker output ledger. First long hold produced native Caps modifier65536.
Raw Jig evidence uses a sentinel expected text intentionally: its text mismatch
status is not the Caps oracle; the event sequence and physical all-up trace are.
Evidence: `caps-tap-1.json`, `caps-hold-1.json` in the run directory.
Second native hold returned modifier flags to zero. After the Hyper lesson applied,
a physical hold produced all four modifier bits (1966080) and released to zero,
with no held output ledger entries. Evidence: `caps-hold-2.json`,
`hyper-hold-1.json`. The launcher and remaining focused UI results follow below.

UI automation note: AXSetAttributeValue changed the launcher field display without
committing its SwiftUI model. Normal focused key entry committed the letter and
enabled Save; do not label the AX-only intermediate state a user-facing failure.
The lesson copy scrolls normally through the console, exposing the app/letter
controls. The keyboard camera intentionally focuses/crops around Caps Lock;
this visual crop alone is not a layout failure.


### Final focused acceptance results — 2026-10-17

- Physical Caps Lock + F after saving Finder in the tour changed the foreground
  application from the capture Jig to Finder. The fixture confirmed all keys up,
  and the same worker reported an empty held-output ledger (`launcher-f-1.json`).
- All four tour pages completed; Open Keyboard handed off to the overlay.
- Rules stayed editable with the runtime stopped. The macOS Function Keys toggle
  changed from 1 to 0 while the runtime verifier still found no worker. Restored
  the toggle and explicitly started via Status; owned runtime verification passed.
- Actual console clicks opened and closed the keyboard drawer.
- Graceful application termination drained the worker and plugins (~0.5 seconds
  from termination callback to will-terminate). Both parent and worker exited.
  Relaunch produced parent21705/worker21759, healthy owned runtime, saved Caps/Hyper
  configuration and the keyboard overlay, without repeating Welcome or the tour.
  Console Cmd-Q/menu attempts did not reach the termination callback; the confirmed
  test used NSRunningApplication's normal terminate request, not force-kill. Do not
  count the unconfirmed console attempts as a passed menu shortcut test.
- Air delivery was attempted but SSH timed out; no installer was copied.

Evidence is preserved under
`/Users/malpern/keypath-review-evidence/20261017-onboarding-final/ui-evidence`.
This is focused acceptance on macOS26.5.2 with one physical ESP32 keyboard, not an
exhaustive feature/platform qualification. The stale-negative Accessibility fallback
has unit coverage; this normal-consent run did not reproduce that stale-native-API
condition. Candidate D is Developer-ID signed but has not been notarized or released.
The native menu Quit interaction and final notarized distribution remain separate
checks; neither is inferred from process termination or a signed local archive.

### Release closure — 2026-10-17

The remaining native-menu Quit check passed on candidate D in disposable lease
`cbx_7d4e71c0a08a` (macOS 26.5.2, original QA account, fresh ungranted onboarding).
Opening the KeyPath menu, highlighting Quit with Up and confirming Return reached
`applicationShouldTerminate` at 08:56:40.152 and `applicationWillTerminate` at
08:56:40.165. The process disappeared and the console returned to Finder.
This completes the menu interaction check; the earlier granted-runtime test
separately verified worker drainage. Cmd-Q forwarding through Parallels was not
qualified. The lease was destroyed and independently absent from the VM inventory.

Apple accepted original candidate D ZIP `deca433f69f01585150cc77f7b94544b02eb56eb5f336fef211fdaf875c751c9`
(submission `12e7245b-360c-4b24-bd20-7aaee9c7fdd0`). The app was stapled,
packaged, and the signed installer was independently accepted (submission
`351bee1e-71e0-4fa8-9d3f-be81dc3329c5`). App and DMG staple validation and
Gatekeeper assessments passed with `Notarized Developer ID`. Main executable
SHA-256 remains `dee58d6babfd0fa5a411ae2ddbf853c17c4dac1c529bc7ea13eacb04c20b00d4`.

Final installer: `/Users/malpern/keypath-review-evidence/20261017-onboarding-final/release/KeyPath-20261017.dmg`.
Final stapled DMG SHA-256: `4a4b69896a206eeb15a686ae3a14b1ecfce78baa3282fcf8c0b1f5d966c3d62e`.
Release logs and Quit process evidence are beside it. No public release or host
installation occurred. The Air was offline at closure; delivery remains pending
and must be confirmed by matching the destination hash.


### Duplicate-copy status advisory — 2026-10-17

Air manual acceptance found a healthy runtime labelled “Setup Needed” solely
because Spotlight found two old unpacked evidence bundles. Duplicate detection
is retained for Repair/Remove, but no longer lowers overall Status health or
triggers its setup banner. The Status detail is informational, so it cannot
become the primary issue or create a “Fix it” action. Actual permission, runtime
and TCP failures retain their existing severity. Evidence copies on the Air
were preserved as verified ZIP archives. This code change is not yet included
in the notarized 20261017 installer.

### Air acceptance blocker: sleep retirement does not resume — 2026-10-17

User reported Caps Lock configured as Escape in overlay but not acting as Escape.
Read-only Air inspection found no live runtime worker and no applied UserKeyMapping.
The rotated app log records the last ready worker at 13:06:15, then terminal
failure `system-will-sleep` at 13:09:44.833. The parent remained alive; subsequent
capability probes did not start a runtime. Caps mapping journal was clean (lock
file only). Saved config still contained Caps tap Escape / hold Hyper.

Code trace: SessionRuntimeEnvironmentObserver intentionally retires the worker
on sleep to release held output and restore Caps mapping. superviseSessionTick
in ServiceLifecycleCoordinator+SessionRuntime.swift resumes only `.secureInput`;
all other terminal reasons, including normal sleep, require explicit recovery.
This is a release blocker for laptop use. Implement parent-owned wake recovery
with current-session/intent guards, fresh admission and all-keys-up checks;
never revive old queued output or override an explicit user Stop. Cover sleep,
wake ordering, secure input and stop-during-sleep, then verify a real sleep/wake.
Do not claim Caps-to-Escape output passed on the Air until retested with a healthy
worker. Immediate workaround is normal Quit/relaunch. No runtime/settings writes
were made during this diagnosis.

#### Wake recovery implementation and focused validation

The lifecycle coordinator now observes parent-session wake notifications and
records a wake epoch at each worker launch. Explicit sleep/wake retirement waits
for a subsequent wake (including one received before the terminal report), the
current console session, Secure Input to end, and physical keys to be released.
It then starts through ordinary admission, which revalidates configuration and
creates a fresh worker and Caps mapping generation. Manual Stop and Quit invalidate
the pending recovery using the existing intent generation; retired queues are
never reused.

On 2026-10-17, SessionLifecycleInterleavingTests and SessionRuntimeEnvironmentTests
passed: 29 tests, zero failures. New coverage includes wake-before-report,
wake-after-report with readiness delay, worker-observed wake, Stop and Quit while
waiting. This proves the recovery control flow, not a real hardware sleep cycle.
The macOS VM cannot enter genuine system sleep (documented lab limitation), so
Air lid-close/reopen verification is pending; Micah agreed to perform that step
once the updated build is installed. No host sleep settings were changed.

Private wake-fix build: main executable SHA-256
`5d5a10910075fb5bde7cdf3b36842437475a6a1e01e56f23b1c23569c3206587`;
pre-notarization ZIP `c1f48e0aad89ad31aa4be235b0ccfce1f9d259e02417d25e6ef49f3a32ae75a1`.
The 29 focused tests and source diff are preserved under
`~/keypath-review-evidence/20261017-sleep-wake/`. Apple upload approval is pending;
this candidate has not been installed on Air or sleep/wake accepted.

Packaging observation: Apple's XPCTimeStampingService repeatedly timed out on
IPv6 while requesting a timestamp, despite direct RFC3161 requests succeeding.
Signing the outer app using the live DNS-resolved IPv4 timestamp endpoint succeeded;
no system network settings were changed. Sparkle build 2059 was reused intact
from the previous verified installer, with its valid nested signatures. Deep/strict
signature and identity-contract checks passed. Do not hardcode that endpoint IP
in the release scripts: resolve and probe again if this transport failure recurs.

Apple accepted the wake-fix app (submission
`496c155b-b5fc-4203-9534-859902e2ebec`) and installer
(`51e2fb4f-66be-4738-8b7d-aa5c473bd8a1`). Both staple validation and Gatekeeper
passed. Final stapled installer SHA-256:
`576990de96a5723435ebf6aa624f862771e2331686ccb7cff34ef44e13cafba7`.

The app was installed on Air at 14:58 Pacific, preserving config and a verified
previous-app archive in `~/Downloads/KeyPath-before-wake-update-20261017-145815`.
Baseline owned-runtime verification passed: parent 23667, worker 24047, TCP ready,
Caps-to-F18 UserKeyMapping applied. Micah reported Caps Lock acting as Escape
after a lid-close attempt. However, macOS recorded no new sleep/wake and the
worker PID stayed unchanged: this is functional Caps evidence, NOT wake recovery
acceptance. A second test using Apple menu → Sleep has been requested.

#### Real-machine follow-up exposed a second failure

The Apple-menu Sleep attempt failed the user’s Caps-as-Escape check. Parent log
at 14:59:50.603 reported `managed-caps-restoration-pending` and launched only
capability probes afterward. In worker finish(), Caps cleanup failure replaced
the original boundary with that string. Parent cleanup subsequently succeeded
(otherwise supervision would have returned earlier), but automatic recovery no
longer knew why the worker retired. Do not treat the delivered first wake-fix
installer as accepted. A follow-up preserves an optional `retirementReason` in
the owned report alongside `failure`; parent recovery uses that original reason
only after its existing output/Caps cleanup gate succeeds. An arbitrary cleanup
failure alone must never authorize automatic restart.

Revision 2 focused validation passed: 32 tests, zero failures, including wire
round-trip of the original retirement reason alongside a cleanup failure and
legacy-report fallback. Keep the next Air iteration as a signed private test;
notarize/package the final revision only after the physical cycle passes.

Revision 2 signed build installed at 15:08 Pacific. ZIP SHA-256
`084acb1f16d185575664c84bd2690190d1f819f289372f4116569454f376d16e`;
main executable `bfba4a7c27852952a96c6d902070ac3a7e1e3211d6b90714608f105b6a915532`.
This revision is signed but not yet notarized; acceptance is pending. Startup
at 15:08:06.486 refused `physicalKeysHeld` during Caps activation. Asked Micah
to release all keys, use normal Restart, verify Caps before sleep, then repeat
Apple-menu Sleep and verify after waking. Do not count the failed initial
startup as a sleep-recovery result. Previous app/config backup:
`~/Downloads/KeyPath-before-wake2-update-20261017-150759`.

#### Revision 3: held-key race during wake startup

Air revision 2 started successfully at 15:13:30, then resumed after a real wake
at 15:14:44.093. Its replacement worker refused Caps activation at 15:14:44.570
with `physicalKeysHeld`. The parent readiness check and child activation are
separate moments: passing the former cannot guarantee the latter. A transient
held-key refusal must keep wake recovery pending, not require reopening the app.

Wake recovery now retries only the exact owned worker's held-key activation
failure, after successful cleanup and while the same running intent remains
current. Other failures remain explicit. Each retry rechecks console readiness,
Secure Input and all-keys-up, with a 250ms polling delay. Stop, Quit or a newer
request ends the old recovery. The retiring supervisor relinquishes its worker
supervision handle before recovery: otherwise replacement cleanup cancels the
very task that must retry. Tests cover this handoff, retry, Stop/Quit, stale retry
evidence, report ownership and failed cleanup. Real Air acceptance remains pending.

Revision 3 focused regression validation: 36 tests passed, zero failures
(`SessionLifecycleInterleavingTests`, `SessionRuntimeEnvironmentTests`,
`SessionRetirementReportTests`). The recovery-task regression uses the actual
supervisor task handle, so a cleanup-induced cancellation fails the test.

Revision 3 installed on Air at 15:24 Pacific. App executable SHA-256:
`808aed9f9a35c4fb07b1633ce4e5764f66053036a415fe74644e3ec0c3d2500e`.
ZIP SHA-256: `0514b5faf48d0d4a5fe93618572ec868f2d9810ef11012c9af9e83a489dcd3f1`.
Signed private test build, not notarized. Backup:
`~/Downloads/KeyPath-before-wake3-update-20261017-152431`.
Installed verification passed; baseline parent 71767 / worker 72285, report
running/tapActive, managedCapsGeneration matches owned launch nonce, no failure.
Initial ordinary startup did log a held-key refusal before the healthy baseline;
this fix specifically retries wake recovery. Physical Caps-as-Escape and actual
sleep/wake acceptance requested from Micah; do not mark that test passed yet.

Revision 3 physical follow-up: Micah reported sleep still broke Caps. Initial
inspection found only parent 71767; while collecting logs, automatic recovery
started at 15:35:18.896 and became ready at 15:35:19.734 with worker 94556.
Independent verification confirmed running/tapActive, matching managed Caps
nonce and no failure. No restart or setup action was performed by the agent.
Asked whether physical Caps-as-Escape now works. Do not classify as accepted or
permanently stopped until that answer. Current logs lack readiness-gate detail,
so the wait must not be attributed specifically to held keys without evidence.

Micah confirmed Caps Lock works as Escape again without restarting or rerunning
setup. This demonstrates automatic functional recovery for revision 3 in this
attempt. Recovery latency remains unqualified: there is no reliable unlock /
all-keys-up timestamp in the captured evidence. Do not equate the 29-second
runtime gap with 29 seconds after unlock, or declare readiness latency solved.

#### Revision 4: screen wake precedes system wake

Unified power/loginwindow logs establish the missing timeline for revision 3:
will-sleep 15:34:48.614, lid reopened 15:34:51.262, display did-wake
15:34:51.330, session unlocked 15:35:01.899, system will-power-on 15:35:18.616.
Runtime was ready at 15:35:19.734, roughly 18 seconds after unlock. The parent
waited exclusively for NSWorkspace system did-wake, although the display and
user session were already available. This was a quick lid close/open transition;
do not describe it as a verified full deep-sleep interval.

Recovery now accepts public NSWorkspace screen-wake and session-became-active
notifications as well as system wake, while preserving console, Secure Input,
all-keys-up, intent and cleanup gates. Signals must be at least as recent as the
owned terminal report, so an unrelated earlier display wake cannot resume a new
sleep. Logging records notification source and readiness-gate transitions with
elapsed milliseconds (no key identities or typed content). Regression coverage
includes early screen wake with no system wake, stale screen-wake rejection,
and readiness still blocking after a valid activation signal. Physical latency
acceptance remains pending; the app still needs time to launch its fresh worker.

Revision 4 validation: 38 focused regression tests passed. Signed private build
installed on Air at 15:43 Pacific, settings preserved. App SHA-256
`8aeb5f82c94f06939b2feb44e837ceed0c4df1deb0e9e45e5003b406011f018f`;
ZIP `8d5a842acea8c5e835f00ea095889417070840ca3bbdfa0c88e0cde83704005d`.
Installed verification passed; parent 11486 / worker 11932, managed Caps matches
owned nonce, tap active, no failure. Backup:
`~/Downloads/KeyPath-before-wake4-update-20261017-154333`.
Not yet notarized; prompt physical recovery after quick lid reopen remains to
be verified, followed by ordinary Apple-menu Sleep and wake stability.

Revision 4 physical acceptance: Micah confirmed Caps Lock works immediately
following wake/unlock and still works after 30 seconds. Captured two quick-lid
cycles: screen-wake 15:43:54.840 / readiness 15:43:57.129 / runtime ready
15:43:58.426; screen-wake 15:44:27.367 / readiness 15:44:30.380 / runtime ready
15:44:31.608. Both waited for Secure Input to end, not the late system-wake
notification. Later system wakes at 15:44:22.562 and 15:44:55.429 caused fresh
worker recovery, ready at 15:44:23.919 and 15:44:56.577 respectively. Final owned
runtime verification passed (parent 11486 / worker 14964). This verifies the
reported quick-lid wake scenario, not zero-latency recovery or all power modes.
Final packaging uses the identical tested revision 4 archive, without rebuilding.

Final app and DMG notarization accepted by Apple (submissions
`7a09b526-a27c-4a7d-b747-f20f1950ee34` and
`85c1582f-9b0c-46c8-8666-a2ae123104f9`). Both tickets stapled and validated;
Gatekeeper accepted app and DMG as Notarized Developer ID. Final installer:
`/Users/malpern/keypath-review-evidence/20261017-sleep-wake/final/KeyPath-20261017-wake-final.dmg`.
Final SHA-256: `bf980471af60f47dea8ece6710a7a6f2ecdb7be37491c4966e4fed7d29659f9a`.
Air went offline during transfer; delivery is NOT yet verified. Existing
`deliver-keypath-installer-to-air` automation updated to this exact artifact/hash
and reactivated, hourly and quiet while offline. It must verify the remote hash
before finalizing the Downloads filename, notify on delivery, then pause itself.
The tested revision 4 app remains installed; no further app replacement occurred.
