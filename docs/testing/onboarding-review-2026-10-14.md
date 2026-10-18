# Onboarding review handoff

## Current status — October 14 final acceptance

The current candidate is `KeyPath-reviewed.zip`, SHA256
`ca33ef8191cf6c07830944ff111c89cb08ea8f90c3d6a0ac9c7214dcb72b82e0`.
All 5,502 tests passed. The 13 reviewed files are integrated into the original
experimental worktree, preserving unrelated dirty work. It is signed and arm64 only.

Current-build physical Caps Lock tap → Escape, hold → Hyper, and Hyper+F → Finder
now pass using the ESP32 and tour-created configuration. Tap and hold also pass
after a verified reboot and normal reopen, with unchanged configuration, a new
runtime nonce, and no held outputs. No new permission grant was needed. This
proves reboot/reopen recovery, not automatic launch at login.

The final owned lease `cbx_969875edd45b` is destroyed; the physical fixture is back
on the host with its attachment policy unchanged. Evidence is in `vm-final/`,
including `final-acceptance-summary.md` and `reboot-acceptance.json`. The initial
hold assertion was corrected to account for redundant full-Hyper flags caused
by carrier autorepeat; all required modifier transitions remain strictly checked.
This was a test-harness correction, not a product fix.

Apple accepted submission `6138cd4c-c6eb-4e8c-9510-987b202d16a2`.
The separate stapled delivery archive is `KeyPath-reviewed-notarized.zip`, SHA256
`8fb7db3e02200e6b3c00ef62303ffd41cfe48ef037e2857af6b086174492b083`.
Gatekeeper reports `accepted`, `Notarized Developer ID`; the arm64 executable
hash is unchanged from the tested candidate. Existing Apple credentials worked
through the secure prompt; no new secret or keychain change was needed.
Air delivery remains outstanding because SSH times out. No public release or
host installation is claimed.
The sections below are the chronological record; their earlier candidate names
and open testing gates have been superseded by this status.

## Earlier checkpoints (historical)

The tested source and build are preserved on the mini in
`~/keypath-review-evidence/20261014-onboarding-review/`. See
`review-status.json`, `review-fixes.patch`, and `source-snapshot.tar.gz`.
The original experimental worktree was preserved unchanged.

The signed, Apple-silicon-only test ZIP is `KeyPath-ui-fixed.zip`, SHA256
`f2db190151b580b9d6691548a66dbbf16ece313d2e45de28d8f91bd75b355d9b`.
It is not notarized and is not a production release.

## Verified

Welcome renders, Get Started works, and the welcome and permission-page
accessibility identifiers are distinct after the container fix. The original
full suite passed 5,502 tests; 44 focused onboarding tests passed after the fix.
The final full suite then passed all 5,502 tests on the UI-fixed source (90 seconds,
zero compiler warnings).
The normal secure-input calibration passed all 37 key pairs, with no repeats
or lost focus.

## Interrupted consent

The normal Accessibility request reached authentication-pending. Approval
stopped after five public test credential characters when the expected Privacy
& Security pane could no longer be verified. There was no submit intent. A
fresh screenshot showed general Accessibility settings with no authentication
sheet. The cause is not established: do not describe this as a timeout, a
KeyPath defect, or a successful permission grant.

The original durable consent claim and progress records were retained. Do not
reset or replay them. The owned VM `cbx_dee1acdb1dbd` was destroyed and provider
UUID `8a92876d-8edb-4c18-a8ae-951cf4ba5625` independently confirmed absent.

## Capture the correct account before destroying the next VM

The generic lab `artifacts` collector copies `$HOME/Library/Logs/KeyPath` and
runs `keypath-cli system inspect` in its transport account. That is not proof
about the public UID502 GUI account. In this run, its permission result must
not be used to infer the GUI application's grant.

Before teardown of a public-account test, use the maintained owned `guest-root`
route and the account journal to verify the exact boot, console account, UID,
and app identity. Separately capture that account's KeyPath logs and running
parent/worker identity. Label transport-account diagnostics separately. Do not
run a fresh CLI under another account and call its permissions the app's.
Capture these observations at the failure, before quitting or replacing the
app. The generic screenshot and controller logs remain useful, but do not
replace account-scoped product evidence.

## Remaining acceptance

Complete normal permission approval, verify the actual GUI process's effective
access, then automatic runtime start, the tour, and physical mapping behavior
on the same candidate. Historical passes of other builds do not close this gate.
Copy this test ZIP to the Air's Downloads when it is reachable and verify the
destination checksum. The last delivery attempt was blocked by the Air being
offline; nothing was copied or installed there.


## Live continuation, October 14 evening

Owned lease `cbx_5c08c77b98da` passed physical secure calibration (37 pairs),
normal Settings Accessibility consent, and automatic GUI-owned driverless startup.
All four Metal tour steps were exercised: Escape tap, Hyper hold, Finder on F,
and completion into the keyboard. Drawer close/reopen and Q→A recording/save
were verified against UI and actual account configuration. The tour candidate
passed all 5,502 tests in 84 seconds (zero Swift warnings).

Additional fixes: fit the tour to the available screen, preserve distinct AX
identities, reset lesson scrolling on step change, and remove duplicate output
capture autosaves from the drawer. See `docs/bugs/wizard-page-accessibility-identity.md`.

The first physical remap check was contaminated by accidentally rearming the
output recorder while attempting to refocus the faded overlay. The product log
proves that recorder consumed the physical Q. Its intent, fixture trace, Jig
status and runtime counters are retained. Normal menu Quit subsequently removed
both parent PID12435 and worker PID13079. Fresh acceptance remains necessary on
the final candidate. The Air still times out over SSH; no new copy claimed.


Final review candidate `KeyPath-reviewed.zip` (SHA256
`ca33ef8191cf6c07830944ff111c89cb08ea8f90c3d6a0ac9c7214dcb72b82e0`)
passed 5,502 tests after all changes (154 seconds, zero Swift warnings).
Live checks confirmed scroll reset to the next heading and exactly one enabled
W→B rule from one recording. Physical Q→A passed before and after normal menu
Quit/reopen, with new parent/worker/nonce and unchanged configuration/artifacts;
independent A down/up, exact two-event counter deltas, empty output ledger.
Evidence: `vm-second/remap-reviewed-before.json` and `remap-reviewed-after.json`.
This does not establish physical Caps Lock tap/hold/launcher or reboot recovery.
Air delivery remains blocked by SSH timeout. The private candidate is not notarized.

## Integration and earlier hardware evidence reconciled

The 13 reviewed files were integrated into the original experimental worktree after checking each target against the pre-review snapshot. All 2,960 recorded source files then matched the tested isolated source byte-for-byte. Unrelated dirty changes were preserved. The existing Caps mapping lease regression passed again (`PASS: durable Caps lease fake transport scenarios`).

Earlier physical acceptance was recovered and checked at `/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_8926584c31dc/20261009T131513Z/physical-acceptance`: all 15 cases in `build-7-all-cases-results.json` passed on the October 9 candidate. Raw tap/hold observer evidence includes two Control press/release transitions and no held keys; the normal parent-owned Caps-to-Escape runtime report has four input/output events and an empty output ledger. This is historical coverage, not a fresh test of the current binary. Do not describe physical driverless Caps capability as entirely unproven or rerun its feasibility investigation. The remaining current-build check is the tour-generated Escape/Hyper behavior and launcher action, plus final release acceptance.

The current candidate remains signed but unnotarized. Air SSH still times out, so no delivery or installation is claimed. Integration is complete; committing the broad existing worktree and final distribution remain outstanding.
