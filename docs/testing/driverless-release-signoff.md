# Driverless release sign-off — October 17, 2026

This is the current release checklist. Dated investigation notes retain their
historical evidence; their old “remaining” sections are not the current backlog.

## Candidate and scope

- Current product source: `b878232f7642abfa83e1e069792611c95f8e6ee3` (tour transaction/rollback fix).
- Apple Silicon only; driverless runtime; no Full Disk Access/browser-history suggestions.
- Existing production-version migration is explicitly out of scope.
- Current notarized installer: `~/keypath-review-evidence/20261018-tour-final/KeyPath-20261018-tour-fix.dmg`.
- SHA-256: `b09de126d7df247959d2c86b430bb489125d78dd001526a6aba0657a87647bc1`.
- Air delivery is queued; SSH was unreachable on October 18 at 06:08 Pacific.
  The Air's previously accepted TCP-handoff build is not this new tour candidate.
- This remains a private candidate on `design/driverless-caps-ui`, not a public release.

## Current automated acceptance

| Check | Current result | Evidence / limits |
| --- | --- | --- |
| Full safe test suite | PASS on TCP-handoff predecessor, 5,569 tests | `~/keypath-review-evidence/20261017-tcp-handoff/full-runner.log`; not rerun for tour-only fix |
| Tour/pack focused tests | PASS, 46 tests | 31 pack and 15 onboarding tests, including transaction rollback regressions |
| Accessibility identifiers | PASS, 382 files | Current tour candidate validation |
| Signing/notarization/Gatekeeper | PASS on current candidate | `~/keypath-review-evidence/20261018-tour-final/` |
| Clean VM install/onboarding/uninstall/reinstall | PASS | Owned `cbx_626ccf25e58c`; normal consent, rule lifecycle, Quit/reopen, backup/removal, reinstall and reboot; details below |
| Full four-page tour with Caps Lock setup | PASS on current candidate | Owned `cbx_6a7d61356f4e`; Caps Lock Escape, Hyper hold, Hyper+F Finder configuration, Open Keyboard/Ready |
| Physical Caps Lock tap and hold | PASS on current candidate | ESP32 native output oracle: `caps-live/physical/caps-tap-keyup.json` and `caps-hold-keyup.json` in October 18 evidence |
| Air sleep/wake | PASS on TCP-handoff predecessor | User verified immediate and 30-second Escape behavior without warning; current tour candidate still needs Air smoke test |
| Visual snapshot regression | PASS, 55 tests on TCP-handoff predecessor | No baseline changes or relaxed tolerances; current Air hover/appearance sign-off remains manual |

## Evidence carried forward, with limits

- Earlier clean-account VM runs exercised normal permission consent, automatic
  startup, the four-step Metal tour, drawer open/close, recording/save, and
  ordinary menu Quit/reopen. See October 14/16/17 investigation evidence.
  These are historical passes, not a fresh full pass of this exact binary.
- Air sleep/wake and secure-input recovery were observed at 20:16 and 20:17;
  both resumed and validated successfully. Subsequent changes fix the independent
  TCP badge and clipped header backgrounds; final visual sign-off is still needed.
- Wake/secure-input status regression tests passed, including stale validation
  results and genuine failures. The full 5,566-test pass preceded the TCP/header
  polish; focused gates afterward passed 79 and 8 tests respectively.
- VM power-state tests cannot establish genuine MacBook sleep/wake behavior.
- No new features or lab redesign are required for sign-off.

## Manual Air checklist (final candidate)

1. Sleep via Apple menu, wait one minute, wake and unlock. Test Caps Lock as
   Escape immediately and after 30 seconds. No false orange setup/TCP warning;
   a brief neutral recovery status is acceptable. Record the time for log review.
2. Test the configured Caps Lock hold action (if enabled), ordinary modifiers,
   and normal typing. No stuck keys after releasing everything.
3. Quit from KeyPath’s menu and reopen. Confirm remapping and saved rules return.
4. Reboot/login once. Confirm the intended Launch at Login behavior and recovery;
   do not change the setting just to make this check pass.
5. Add a temporary simple remap, verify it in a blank text document, edit it,
   disable it and delete it. Confirm normal typing returns. Leave existing rules intact.
6. Confirm the top-right hover highlight and keyboard/layer picker look correct,
   with drawer open/closed. Briefly check small overlay size and light/dark mode.

Additional clean onboarding/removal acceptance is owned by automated VM testing;
it is not silently transferred to the Air checklist if the VM cannot run.

## Public release gate

Freeze one candidate, close failed/pending acceptance items, reconcile release
notes and source integration, then perform the repository review/merge/release
workflow with the required approvals. Notarization alone is not release sign-off.

## Provisioning blocker and cleanup

Attempts `cbx_be9a6c088d29` and `cbx_64f7023a0508` failed with:
`Failed to start the VM: Unable to start the virtual machine. An unexpected error
occurred while starting the virtual machine.` No vm-lab ownership manifest was
published, so `status` refused the first ID as not owned by the interface.
Independent read-only provider inventories after each failure showed neither
new guest registered. No existing/foreign lease was adopted or mutated; no
provider VM was created directly. No third attempt or host reboot was performed.
Evidence: `create.log`, `create-retry.log`, `provider-inventory.txt`,
`provider-after-retry.txt`, and `preflight-after.txt` under the run evidence folder.

The generic provider error does not establish its root cause. The next lab action
is a bounded provider-start diagnosis (capture the failed start's provider
support diagnostics), then rerun this exact candidate's clean-account acceptance.
Do not count the host regression tests as normal macOS permission-consent proof.

## Findings and disposition this pass

- Fixed `check-computer-use-readiness.py`: two removed pickers are now preview
  buttons; unsupported virtual-key/system-helper/reset expectations were stale;
  the supported driverless uninstall button is required by its current ID.
  Other automation targets remain enforced. Both the original failure and the
  passing rerun are retained.
- The initial QA consolidation changed only scripts/docs. The later TCP handoff
  fix produced the new notarized installer named above; the installed Air app
  remains the previous header-hover candidate as verified below.
- Header hover and smallest-size/light-mode readability still need direct
  confirmation. Broad snapshot tolerances and noninteractive fixtures are not
  proof of those exact interaction states.
- This pass did not execute a clean install, normal consent, uninstall/reinstall,
  or guest reboot. They remain open together under the blocked VM gate.
- Public release is not yet approved: final Air checks, clean VM acceptance,
  and source integration/release review remain. Avoid claiming “bug free.”

A later read-only process inventory found other Virtualization.framework workers
and CrabBox activity on the host. Their ownership was not established and none
were stopped. This is evidence of shared host activity, not proof of the start
failure’s cause. Preflight capacity alone did not predict the provisioning failure.

## TCP handoff follow-up

The 20:49 wake showed a 761 ms gap between successful runtime validation and
the overlay receiving a TCP event. The checking-only suppression was incomplete.
The new candidate adds a bounded five-second settling window, with regression
coverage for successful reconnect, persistent failure, and non-renewal by routine
health checks. Focused tests and the full suite pass. Actual sleep/wake visual
acceptance on the new candidate remains outstanding.

## Air follow-up: 21:12 recovery, October 17

Micah reports sleep/wake showed only “Restarting…” and no error. Logs confirm:

- 21:12:23.749: recovery gate ready after secure input cleared.
- 21:12:25.789: overlay TCP connected.
- 21:12:26.610: runtime ready; 21:12:28.010: validation succeeded.
- A later wake notification at 21:12:38.888 also completed recovery:
  runtime ready 21:12:42.242, validation succeeded 21:12:44.048.

**Build identity matters:** installed executable SHA-256 is
`45a665945852d91ae7677c29671eb2c89c25334bbf7cad86f49f0bc1eabead20`, matching
header-hover, with parent PID 52511 running since 20:37. The new TCP handoff
executable hash is `9c367b0c77658782f8f0ab26b25231a928fcaa473037a191223361ee34345e7a`.
The new installer was delivered, not installed. This is a successful recovery
observation on the old build, not live acceptance of the handoff fix. Here TCP
reconnected before validation finished, so the old race was not exercised.

The retrieved power log contains no new 21:12 actual system-sleep entry (latest
is 20:16:53–20:17:00). Record the user-reported sleep/wake and observed recovery
notifications without claiming a newly verified full one-minute system sleep.
The user did not separately reconfirm Caps Lock immediate/30-second behavior
in this report. Prior functional passes remain historical evidence.

Evidence: `~/keypath-review-evidence/20261017-tcp-handoff/air-recovery-followup.log`.
Next: install the delivered candidate and verify one genuine sleep/wake cycle,
then finish the remaining Air interaction checks and blocked clean-VM gate.

## Installation and continued automated QA: 21:22, October 17

Installed the delivered TCP handoff DMG on the Air, preserving the previous app
in Trash and leaving settings intact. Verified executable SHA-256
`9c367b0c77658782f8f0ab26b25231a928fcaa473037a191223361ee34345e7a`, valid signature,
stapled notarization, Gatekeeper acceptance, parent PID 15560, worker PID 16291,
and owned TCP endpoint 127.0.0.1:37001. Micah has been told it is ready for the
next sleep/wake test. Evidence: `air-install.log`, `air-installed-verification.log`
in the TCP handoff evidence directory. Computer Use source contracts also pass.

### Lab diagnosis and current capacity

The correct provider log is `/Library/Logs/parallels.log` (not the nonexistent
`/Library/Logs/Parallels/parallels.log`). It confirms clone cleanup and
`PRL_ERR_VM_START_FAILED` for the earlier attempts. The failed launch logged
“Failed to find audit port for uid 505”; `clawd` has no GUI domain. This suggests
an account/session problem but does not alone establish the complete root cause.

The default controller route uses `clawd` and reports zero Parallels leases.
The supported console route, `vm-lab --host malpern@mini keypath preflight`,
correctly reports two leases, matching read-only provider inventory:
`cbx_345abf6018d5` and `cbx_d21f6077b13c`. Both are other work's running guests.
Capacity is two, so no new admission was attempted and no existing guest was
stopped/adopted. This is a capacity block for the clean acceptance run, not a
product failure. Resume through the supported console-account route when capacity
is available; do not repeat the zero-lease default-route assumption.
Evidence: `lab-provider-diagnosis.log`, `lab-provider-inventory.txt`,
`lab-user-context.txt`, and `lab-console-preflight.log` in the TCP handoff folder.

Final automated result for this iteration: 55 visual snapshot tests passed with
zero failures and unchanged baselines (`20261017-tcp-handoff/snapshot-runner.log`).
Together with the prior 5,569-test suite, source contracts and installed trust/
runtime checks, available automated checks pass. Clean guest acceptance remains
blocked by shared lab capacity; manual sleep/wake on the installed candidate is
not yet recorded as passed.

## Latest Air acceptance — 21:31, October 17

Micah confirms Caps Lock works immediately and after 30 seconds following
sleep/wake, with no warning. Installed executable hash was reverified as the
TCP handoff build (`9c367b0c…`). Mark functional Caps Lock and neutral recovery
presentation **PASS by user observation on the current build**.

Logs independently confirm TCP reconnect at 21:31:16.316, runtime ready at
21:31:16.844 and validation success at 21:31:16.850. A later system wake signal
also recovered and validated successfully at 21:31:38.967. Evidence:
`20261017-tcp-handoff/air-final-sleep-wake.log`.

The power-log query still returns no new system-sleep entry after 20:17;
therefore the duration/depth of sleep is not independently established by this
capture. This does not negate the observed working recovery, but do not describe
it as a power-log-verified one-minute sleep. The deterministic regression tests
cover the adverse validation-before-stream ordering; this live cycle connected
the stream before validation.

Both Parallels slots remain occupied. A 30-minute thread follow-up is scheduled
to resume clean-account QA through the console-account route when capacity is
available, without touching other leases. Remaining manual items: Caps Lock hold
(if configured), Quit/reopen, reboot/login, rule editing, and hover/drawer/appearance.
Release review/integration remains pending. No repeated full test run is needed
without new changes or failures.

## Clean desktop QA and failed-tour regression — October 17, 22:53

Fast Arrows released its prior guests. An owned macOS 26.5.2 unmanaged desktop
lease (`cbx_626ccf25e58c`) was admitted through `--host malpern@mini` and tested
as a new public account, UID 502. Evidence root:
`~/keypath-review-evidence/20261017-tcp-handoff/clean-qa/`.

Passed on the TCP handoff artifact: welcome, normal Accessibility consent and
refresh without relaunch, automatic runtime startup, tour presentation, drawer
open/close, settings/status, ordinary rule save and actual A → C output in TextEdit,
Quit (parent and worker exit), reopen with saved rule, and UI uninstall. Uninstall
created a Downloads backup, removed active configuration, moved the app to Trash
and exited without Finder error dialogs. Reinstall displayed welcome and then the
tour again. Input Monitoring was not explicitly granted in this account.

The run found a real product bug: the tour persisted Caps Lock → Escape before
runtime/device admission. When this VM's virtual keyboard failed Caps admission,
that saved collection poisoned later ordinary rule saves. The fix keeps runtime
application inside the existing pack transaction and restores the prior revision
on failure. See `docs/bugs/tour-caps-preparation-transaction.md`.

The fixed Developer ID signed functional replacement passed 46 focused tests
(31 pack transaction and 15 onboarding session tests), including three new tests;
zero compiler warnings. It also passed the accessibility source check and build.
Functional ZIP `KeyPath-tour-fix.zip` SHA-256:
`70eebd0d27452ef28d233604a58bf04c6d2c4bccf465dc9c334c2d8fcac7e4d7`;
executable SHA-256:
`a79ab1185afd3a078b6a0111f929ffb974518a8b573d8ce23fb49db78920988f`.
At this point in the run the replacement was not notarized or delivered; see
the October 18 packaging update below for the current artifact status.
The replacement receipt and source manifest identify its exact base plus patch.

Live regression passed: reject Caps setup, compare the prior configuration files
byte-for-byte, skip the tour, and save A → C successfully without repair/restart.
The existing worker stayed healthy. Editing to A → B produced B in TextEdit;
deleting the rule restored A. TextEdit progressed from `Cc` to `Ccb` to `Ccba`.
Evidence includes `pre-tour-files.log`, `post-tour-files.log`,
`replacement-1/state.json`, `tour-fix-source.json`, `tour-fix-build.log`,
`runtime-reopen.log`, `uninstall-postconditions.log`, and tool screenshots.

Do not turn the virtual keyboard's rejection into a Caps success claim. The
successful physical Caps tour (including remaining tour pages and hold behavior)
still needs compatible hardware. Earlier Air sleep/wake acceptance remains valid
for its installed TCP handoff build; this small tour fix is a new artifact.

### Post-reboot and final Quit

The supported public reboot cycle changed boot UUID from
`b21155aa-7253-490b-8292-828737f9078d` to
`b2fb7539-8546-4f04-b5b3-a6e77d759156`. The initial reboot call lost its
response during shutdown; observation verified the new boot, without a repeated
reboot dispatch. The cycle completed with both autologin authorities OFF and its
cache absent (`reboot-cycle/state.json`, `complete:true`).

The fixed app reopened on the public desktop without a new consent prompt and
showed Ready. Independent runtime verification passed with parent PID 402,
worker PID 874, owned TCP 127.0.0.1:37001 (`runtime-post-reboot.log`). The custom
rules file remained empty after deletion. A final normal Quit exited both PIDs.
Final app log: `tour-fix-final-guest.log`. This verifies app/permission recovery
after a real guest reboot, not physical Caps output or genuine system sleep.

The scheduled capacity waiter is paused: the available-VM batch has run, and the
old artifact must not be admitted again automatically. Remaining release work:
physical Caps tour/hold acceptance, notarized packaging of this new fix, and
release review/integration. The Air was not modified during this batch.

## Tour rollback installer — October 18

Packaged the exact tested functional ZIP after committing its source as
`b878232f7642abfa83e1e069792611c95f8e6ee3`. Apple accepted the app submission
`e7965bb9-fc43-42ff-b426-ba03ec2e736e` and installer submission
`700707c7-ff82-4551-8348-9f6e85b68ab6`. App and DMG tickets were stapled and
validated; Gatekeeper accepted the DMG as Notarized Developer ID.

Installer: `~/keypath-review-evidence/20261018-tour-final/KeyPath-20261018-tour-fix.dmg`.
Final stapled SHA-256:
`b09de126d7df247959d2c86b430bb489125d78dd001526a6aba0657a87647bc1`.
Executable remains `a79ab1185afd3a078b6a0111f929ffb974518a8b573d8ce23fb49db78920988f`.
Air SSH timed out; the existing delivery automation now targets this installer,
verifies both hashes, and pauses after delivery. No Air installation occurred.
Physical Caps tour/hold acceptance is still pending; notarization is not a test
of that behavior. The rig is online with its pinned firmware and not assigned to
another VM. A new owned-guest admission is waiting behind shared provisioning.


### Physical tour follow-up: UI targeting blocked

Owned lease `cbx_d63d055d962b` completed admission and readiness, root-console
preparation, and pinned Python installation. Product testing did not start:
CUA selected the concurrent Typover macOS VM when binding to
`com.parallels.macvm`, even after opening the KeyPath guest from Control Center.
The selected process's Window menu exposed only the Typover window. No guest
keyboard input or fixture reports were sent, and Typover's lease was not changed.
This is an automation targeting limitation, not a newly observed KeyPath failure.

Collected artifacts at
`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_d63d055d962b/20261018T121056Z`.
Destroyed the owned guest successfully; destruction warned that its hydration-stop
marker could not be written over guest SSH, then confirmed provider deletion.
Air SSH still timed out. Delivery remains queued, and physical Caps Lock tour,
tap Escape, and hold Hyper acceptance remains open. Resume this test when the UI
can target the owned VM unambiguously, or complete it on the Air; do not recreate
another guest merely to repeat this targeting failure.


### VM console targeting workaround

Use one Parallels macOS console at a time for host CUA testing. Multiple guests
share `com.parallels.macvm`; selecting that bundle does not select a lease, and
the selected process's Window menu cannot switch to a different VM process.
The available macOS CUA API has no documented PID selector. Do not rename app
bundles or alter their signatures to work around this.

Before admission, confirm no competing console is active. If another tenant is
using one, wait for its normal release. After admission, bind the app afresh and
require its AX window title to contain the exact owned lease ID before every
input batch. Also check the screenshot against that title after any focus or
process change. A mismatch stops input immediately; it never justifies stopping
another tenant's guest. This serializes host-console UI work only, not independent
builds, unit tests, or guest command-line checks.

On October 18, after the competing VM was released, a fresh binding correctly
selected owned lease `cbx_5a95a4b49d72`; both AX title and screenshot matched.
This verifies the single-console workaround, not a fix to CUA's multiple-process
selection limitation and not physical Caps Lock acceptance.

The targeting-only recheck also opened and dismissed the host Window menu on the
correct lease. Guest readiness did not complete before cleanup: the provider
reported `starting` and refused ordinary deletion as busy. The supported
`recover-wedged` route stopped and deleted only this lease successfully. The
remaining readiness waiter was terminated after provider deletion. Thus console
selection is verified, but this run does not establish guest readiness or any
additional product acceptance result.


Correction after inspecting `settling.jsonl`: the targeting recheck did not
prove a startup hang. Tools installation was active, then the guest rebooted and
reported `installerActive:false` with six seconds of quiet time. Cleanup was
requested before the required 90-second quiet window completed. Observation
failures after deletion are not startup evidence. A child readiness observer
survived termination of its wrapper; it was identified by exact lease ID and
terminated on the next turn. Future runs must let the existing ten-minute
readiness deadline resolve, monitor its settling log, and preserve the useful
same-artifact guest for the acceptance batch rather than stop after targeting.

## Final physical acceptance — October 18, 06:11 Pacific

Owned macOS 26.5.2 lease `cbx_6a7d61356f4e` completed readiness, normal
Accessibility consent in disposable UID 502, automatic progression into the
four-page tour, Caps Lock setup, Hyper hold, Hyper+F Finder configuration, and
Open Keyboard with Ready status. No TCC database edits were used.

The ESP32 fixture (serial `2884855553BC`) sent real USB reports. The exact
installed executable hash remained
`a79ab1185afd3a078b6a0111f929ffb974518a8b573d8ce23fb49db78920988f`;
active worker config matched SHA-256
`ac647da365f73e7afd158def810ee4221c6cb5b1221937ddba22cfd9a2dec9ac`.
Tap produced Escape down/up. Hold produced all four Hyper modifiers, A down/up,
and all modifier releases. Both native oracles passed with all-up fixture
reports and no held worker output usages. Hyper+F was configured through the
tour; this physical oracle used A, not an app-launch assertion.

Two test-tool defects were fixed without changing KeyPath: fixture scheduledUs
uses an absolute clock (compare offsets from the first report), and AppKit can
omit Command-modified keyUp from responder dispatch (capture it with a local
keyUp monitor scoped to the focused Jig canvas). The first hold run failed
because the old Jig missed A-up; it is preserved, not counted as a pass. The
updated Jig captured the complete sequence and a repeat tap also passed. Nine
focused fixture-checker tests cover absolute timestamps and reject offset drift.

Evidence: `~/keypath-review-evidence/20261018-tour-final/caps-live/physical/`.
`caps-hold-keyup.json` and `caps-tap-keyup.json` are the authoritative pass
receipts; `manifest-keyup.json` pins the test-tool hashes. Final product log:
`caps-live/keypath-debug-physical-final.log`. The Jig's text-sentinel mismatch
is expected for the native-event oracle and is not the acceptance verdict.

Remaining: deliver this notarized installer when Air is reachable, perform the
short final Air smoke/appearance checklist, and complete source review/integration
before a public release. No newly identified KeyPath defect remains from this
physical acceptance batch; this does not claim every possible configuration is
bug-free or substitute VM testing for genuine MacBook sleep/wake.

The capture Jig's 37 core tests also passed. Test-tool fixes are committed as
`9b5e88d88` (KeyPath Jig branch) and `3e08465` (vm-lab Caps acceptance branch).
Collected guest artifacts:
`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_6a7d61356f4e/20261018T131115Z`.
The lab confirmed deletion of owned UUID
`70889833-c185-422b-9479-a14652aea03d`; cleanup warned only that its optional
hydration stop marker could not be written over SSH before provider deletion.

## Air current-candidate follow-up — October 18, 06:54 Pacific

Delivered and installed the current tour-fix DMG with matching source/remote
hashes, Developer ID/Gatekeeper/stapler verification, preserving existing rules
and preferences. The previous app was archived in Downloads before replacement.
User confirmed Caps Lock works immediately after waking and after 30 seconds,
with no warning. Live owned-session verification passed for parent 61704,
worker 65630 and TCP 37001; latest validation reported no blocking issues.

However, logs reveal a remaining startup UX defect. Initial launch at 06:51
refused managed Caps activation with `physicalKeysHeld` and stopped; after the
user released all keys and the app was reopened, startup passed. The code uses
combined session key state, so this does not prove the user was physically
holding a specific key. Ordinary startup treats this transient condition as a
terminal failure; only the System wake path retries it today.

The 06:54:18.780 system-wake notification was followed by six held-key activation
refusals, then runtime Ready at 06:54:28.266 and successful validation at
06:54:29.750. This is successful automatic recovery with a roughly 9.5-second
notification-to-ready interval, not evidence of zero recovery delay. User-visible
no-warning acceptance passed. Repeated `Terminal failure` log lines during this
recoverable condition are misleading diagnostic severity.

Before production: handle held-key startup as a transient wait using the existing
lifecycle recovery machinery, retain the all-up guard, test release-to-ready and
cancellation/real failures, then repeat the affected launch and wake checks. Do
not remove the guard or mask genuine failures. Source review/integration and final
Air appearance/Quit-reopen checks also remain. Evidence: `air-install-latest.log`,
`air-install-retry.log`, `air-wake-final.log`, `air-wake-power.log` under the current
October 18 tour-final evidence directory. This finding supersedes the earlier
statement that this candidate has no newly identified product defect remaining.

## Held-key startup follow-up (2026-10-18, in progress)

Ordinary held-key startup now uses the existing safe readiness/retry loop after
verified worker cleanup, preserving all-up activation and intent cancellation.
The terminal error log is delayed until retryable cases have been classified.
See `docs/bugs/2026-10-18-held-key-startup.md`. Build/test/install results follow
below; this entry alone is not release acceptance.

Full safe suite passed on this change (runner: 5,525 passed, exit 0; 105 seconds).
Both new held-key lifecycle tests and the updated diagnostic-placement test
passed. Accessibility identifiers passed across 382 files. Evidence:
`/Users/malpern/keypath-review-evidence/20261018-held-key-startup/`.
The initial full run found an old lint expectation that required terminal
formatting before retry classification; it was updated to retain pre-cleanup
diagnostic capture while checking terminal formatting occurs after retries.

### Held-key candidate delivered and installed

Source commit `9a2a7f9d9` was built, Developer ID signed, and notarized. App
submission `b55336d9-5d7a-44da-9c68-97b4cf2427db` and DMG submission
`d5ec1f81-de13-4749-aae6-4683a76ea26d` were accepted; stapling/Gatekeeper passed.
Air Downloads contains `KeyPath-20261018-held-key-fix.dmg`, verified SHA-256
`9974076031f24f95444445d5c80be485241c7d0f6a9b912b45a0f1c39c0bf14f`.
Installed executable SHA-256:
`b9965f1f51cb5a66f33833dcd691ca83b695c32e21089d51382a66f996f10f40`.
Rules were preserved; old app archived as
`Downloads/KeyPath-before-held-key-update-20261018-071326.zip` on Air.

The first install verification correctly refused: the deployment script used
`ps pid,comm,args`, whose `comm` column macOS truncated, so it missed the old
parent and worker. Corrected to untruncated `ps -axww -o pid=,args=` with an exact
executable prefix boundary. The identified old parent was then terminated
normally and both old processes were observed exited before reopening. Final
owned-session verification passed: parent 2700, worker 3124, TCP 37001. The
initial verification failure is retained with the evidence rather than counted
as an app startup failure or successful installation.

Remaining acceptance on this candidate: launch with a key held, release it,
confirm automatic remapping without restart/error; then sleep/wake and Caps Lock
immediately and after 30 seconds. These physical checks are not claimed by the
unit tests or process health verification.

## Installer visual polish (2026-10-18)

Private DMG layout now uses native typography, explicit drag-to-install and
open-from-Applications instructions, a crisp SF Symbols arrow, and 96-point
icons instead of 128-point icons. Actual Finder preview checked at
`/Users/malpern/keypath-review-evidence/20261018-installer-design/preview.png`.
Finder user preferences can override tab/path/status visibility; the preview
uses hidden bars. The app payload is the unchanged held-key candidate. Packaging
passed image integrity and mounted app strict signature checks. No app rebuild
or further functional regression run is needed for this background/layout edit.

### Brand correction to installer polish

The light redesign was rejected as insufficiently KeyPath. It is superseded by
`installer-branded@2x.png`: original amber-lit keyboard artwork, serif KeyPath
wordmark and the established “Keys that do more.” tagline. Smaller native icons
and explicit installation guidance remain. Warm label plates preserve contrast
for Finder's black native filenames. No filenames are baked into the background.
An experiment setting Finder's fallback background color did not change filename
contrast, so the extra packaging driver was discarded. The standard dmgbuild
path remains. Final mounted Finder preview and strict packaged app signature
checks passed; see `20261018-installer-brand/preview.png` in the evidence root.

Branded installer notarization accepted (`ee13cd28-7036-41bc-ad5b-67a7f6d85efd`),
stapling and Gatekeeper passed, and hash-verified delivery completed to Air
Downloads as `KeyPath-20261018-branded-installer.dmg`. Final SHA-256:
`cbbecef1fdc912c64958b449b8c5b6f22824f907c8cda839c4288827348263d0`.
The app payload remains the tested held-key fix; only installer presentation changed.

## Installer composition refinement (2026-10-18)

Supersedes the separate cream filename plates: native app and Applications icons
now share one installation surface. Icon centers moved inward to (205,208) and
(455,208). The original keyboard artwork with glowing legends is used; supporting
type is regular system sans serif, the wordmark remains serif, and the instruction
is quieter. Native labels stay real, selectable, and readable at 13 points.
Mounted Finder inspection passed: no clipping, correct icon placement, readable
labels/instructions, app selection verified. Image checksum and strict packaged
app signature passed. Evidence: `20261018-installer-polish/preview.png` and
`package.log` in the existing review evidence root. The contained app remains the
held-key startup fix; this is installer presentation only.

A zero-point filename experiment was rejected: Finder ignored the invalid
icon-view settings, losing the background and resetting icon size. A diffuse
lighting experiment was also discarded after visual review. Neither is shipped;
standard dmgbuild and valid native label settings remain in use.

Polished installer notarization accepted (`cbbac958-664c-4161-971c-21bc98b28959`),
stapling/Gatekeeper passed, and source/remote SHA-256 matched on delivery to Air
Downloads: `KeyPath-20261018-polished-installer.dmg`, hash
`b534981b81ff0887df0f697488f114cdad9599538a66b4ceffbfc8401d4547d1`.
No app reinstall was performed for this presentation-only change.

### Installer design revision — 2026-10-18

User rejected the cream card layout. Replaced it with a split composition: historical
KeyPath wordmark, tagline and amber keyboard on the left; native app and Applications
icons in a vertical drag path on a full-height silver column on the right.
Actual Finder preview: `/Users/malpern/keypath-review-evidence/20261018-installer-split/preview.png`.
App unchanged from tested held-key build. Packaged strict signature, image integrity,
Apple notarization, stapling and Gatekeeper passed. Submission
`499d2a03-7142-4dca-8d0c-6b25f389d63b`.
Delivered to Air Downloads as `KeyPath-20261018-brand-layout.dmg`, remote hash verified:
`9ffb8208fcf6cdb354c104228a05943d0511b71b8f4f2fc081292c78e60af487`.
Presentation-only change; outstanding physical held-key acceptance remains unchanged.

Installer refinement: removed “Your keyboard. Your way.” and narrowed the silver
column by 25% (310 to 232.5 points), recentering icons and instruction. Finder
preview verified; package signature, notarization, staple and Gatekeeper passed.
Delivered `KeyPath-20261018-brand-refined.dmg` to Air Downloads with matching hash
`398b4c0442bcb48e14196e0eb2e06a7847d7cdc0dd43af75a96544a4f264bf8e`.
Evidence: `/Users/malpern/keypath-review-evidence/20261018-installer-narrow/`.

Typography refinement (2026-10-18): kept the 40-point serif wordmark, warmed it
to ivory, moved the tagline from y99 to y91, reduced it from 14 to 13 points,
and used warm gray. Finder rendering verified. Same tested app inside.
Notarization `40739346-2453-45f6-adf2-f6897f7cab2c` accepted; staple and Gatekeeper
passed. Air Downloads delivery `KeyPath-20261018-brand-final.dmg` verified against
SHA-256 `615e0104a9496ae319b61cce05ad263d94a1dccc107c90e3608674a917958dc9`.
Preview and evidence: `/Users/malpern/keypath-review-evidence/20261018-installer-type/`.

### Splash and tagline unification — 2026-10-18

Source `7a3130399` implements the approved centered amber-keycap splash with native
ivory serif wordmark and warm-gray **Keys that do more.** tagline. Retired both
old poster resources, including their baked-in old tagline. Brand policy is now
`docs/design/keypath-brand.md`. Welcome, About and current installer already use
the selected tagline; repository copy search found no remaining active use of the
retired tagline.

Activity is limited to the launch handoff, pauses for Reduce Motion, and is stopped
when the splash hides or hosts a menu-action sheet. Existing startup timing and
runtime behavior are unchanged. Native SwiftUI preview verified loading and static
states at the real 640×440 window size; evidence `preview.png` and `preview-idle.png`
in `/Users/malpern/keypath-review-evidence/20261018-splash-brand/`. The preview
contained only the splash component; KeyPath was not installed/launched on mini.

Production build, signing identity/bundle contract, strict signature, pinned
SwiftFormat lint and accessibility checks passed. All six ReopenPolicy cases
passed through the safe runner (77 seconds including compilation). App notarization
`592d58da-5991-48b1-abee-4b661f6aff6e` accepted; app staple and Gatekeeper passed.
This UI-only iteration does not replace the outstanding physical held-key startup
acceptance recorded above. On Air, a brief launch check should confirm the new
splash hands off cleanly to setup/keyboard without lingering activity.

DMG notarization `98fc76ba-88e3-4a3d-b6d6-707fc19d22a2` accepted. Final image
staple/validate and Gatekeeper passed. Delivered to Air Downloads as
`KeyPath-20261018-splash-brand.dmg` with verified matching SHA-256
`1f4c5cc900cb30cc338ce09b0d957873cb9784d306a21678f0bc70abe6c2bcd0`.
Delivery only; the Air's installed app and settings were not changed in this pass.

### About and Help branding follow-up — 2026-10-18

`cc471f1e4` replaces the separate AboutView's generic diagnostics description with
**Keys that do more.**, placed beneath a serif KeyPath wordmark and above version
metadata. The menu's standard macOS About panel already used the correct tagline
and remains the menu destination; no new diagnostics/update surface was activated.
Native preview of the extracted, unchanged header layout passed; screenshot at
`/Users/malpern/keypath-review-evidence/20261018-about-brand/about-header.png`.
Pinned SwiftFormat and accessibility checks passed. Production build/bundle/signing
checks passed; app BuildInfo records `d1da418e0`.

Audited in-app Help Browser, local guides, Help copy and its illustrated header
banner. No retired tagline found there; the banner says “KeyPath Documentation”.
`d1da418e0` records exact tagline spelling/punctuation in help authoring guidelines
and brand policy. Article copy remains focused on users' goals.

App notarization `019d73d4-29e6-4e29-b3a0-6dbb80ea1ce5` accepted; staple and
Gatekeeper passed. This follow-up changes presentation/copy only and includes the
previously tested splash. Prior functional QA/manual acceptance status is unchanged.

Final DMG notarization `e2ba8e3c-fd11-4317-8fe8-fa74c56236fe`, staple/validate,
image integrity, packaged app signature and Gatekeeper passed. Delivered to Air
Downloads as `KeyPath-20261018-brand-complete.dmg`; source and remote SHA-256 match:
`0e2bdc00d530176f9d69521872b075bad936c10e7a0d0d64d0c2fef535bd358f`.
This supersedes the splash-brand installer for the next install/test. Delivery only.
