# Driverless release sign-off — October 17, 2026

This is the current release checklist. Dated investigation notes retain their
historical evidence; their old “remaining” sections are not the current backlog.

## Candidate and scope

- Product source: `9d163f88e` (TCP recovery handoff fix).
- Apple Silicon only; driverless runtime; no Full Disk Access/browser-history suggestions.
- Existing production-version migration is explicitly out of scope.
- Air installer: `~/Downloads/KeyPath-20261017-tcp-handoff.dmg`.
- Installer packaging/delivery evidence: `~/keypath-review-evidence/20261017-tcp-handoff/`.
- Previous header-hover candidate passed installed trust/owned-session/TCP checks.
  The TCP handoff candidate is notarized and copied to Air Downloads with matching
  SHA-256 `d7f2cc1459c3afc2161633c919a76a1778f1b2d4b1bf7287297cae21944e299e`.
  Installed on the Air at 21:22; signature, stapling, Gatekeeper, owned-session
  runtime and TCP checks passed. User-reported wake behavior and visual acceptance passed; see latest evidence below.
- This remains a private candidate on `design/driverless-caps-ui`, not a public release.

## Current automated acceptance

| Check | Current result | Evidence / limits |
| --- | --- | --- |
| Full safe test suite | PASS, 5,569 tests in 134 seconds | `~/keypath-review-evidence/20261017-tcp-handoff/full-runner.log` |
| Accessibility identifiers | PASS, 382 files | `accessibility.log` in that evidence folder |
| Computer Use source contract | PASS after stale expectations corrected | Current preview choices and driverless uninstall replace obsolete picker/system-helper controls. This proves source targets, not clicks. |
| Signing/notarization/Gatekeeper | PASS | `~/keypath-review-evidence/20261017-tcp-handoff/` |
| Air installed runtime | PASS, TCP handoff candidate | `20261017-tcp-handoff/air-installed-verification.log`; executable hash verified |
| Clean VM install/onboarding/uninstall/reinstall | BLOCKED | Two clean admissions failed in Parallels startup before product installation. This gate is not passed. |
| Visual snapshot regression | PASS, 55 tests on TCP handoff source; 135 seconds including rebuild | Metal entrance frames, hard views and scenario snapshots; no baseline changes or relaxed tolerances. Overlay/General/Repair reference images also reviewed. Hover interaction is still a manual check. |

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
