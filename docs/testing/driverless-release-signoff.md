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
  It has not been installed or live-tested in this iteration.
- This remains a private candidate on `design/driverless-caps-ui`, not a public release.

## Current automated acceptance

| Check | Current result | Evidence / limits |
| --- | --- | --- |
| Full safe test suite | PASS, 5,569 tests in 134 seconds | `~/keypath-review-evidence/20261017-tcp-handoff/full-runner.log` |
| Accessibility identifiers | PASS, 382 files | `accessibility.log` in that evidence folder |
| Computer Use source contract | PASS after stale expectations corrected | Current preview choices and driverless uninstall replace obsolete picker/system-helper controls. This proves source targets, not clicks. |
| Signing/notarization/Gatekeeper | PASS | `~/keypath-review-evidence/20261017-tcp-handoff/` |
| Air installed runtime | PASS, previous header-hover candidate | Fresh evidence in `20261017-final-qa/air-verification.log` |
| Clean VM install/onboarding/uninstall/reinstall | BLOCKED | Two clean admissions failed in Parallels startup before product installation. This gate is not passed. |
| Visual snapshot regression | PASS, 55 tests in 66 seconds | Metal entrance frames, hard views and scenario snapshots; no baseline changes or relaxed tolerances. Overlay/General/Repair reference images also reviewed. Hover interaction is still a manual check. |

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
- No application code or installer changed this pass. The current Air installer
  remains the verified header-hover candidate; no rebuild/notarization is needed
  for QA scripts and documentation only.
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
