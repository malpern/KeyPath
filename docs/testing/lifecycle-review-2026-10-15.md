# Driverless lifecycle review — October 15, 2026

Scope: close the remaining launch-at-login, installation, permission-recovery and
uninstall/reinstall gaps. Preserve the experimental worktree and the previous
notarized acceptance artifact. No host KeyPath installation, host permission
change, public release or older-version migration is part of this run.

## Changes

- Optional General → Startup → Launch at login, backed directly by macOS
  SMAppService.mainApp. System status is authoritative; no persisted Boolean,
  extra helper, root daemon or polling loop. Refresh on settings activation;
  synchronous Apple IPC runs off the UI actor through the existing
  SMAppServiceStatusProvider. Pending approval is distinct.
- Uninstall backs up first, unregisters the login item and verifies its status,
  then removes data and trashes the app. A failed unregister preserves data/app
  and resumes the existing admission gates.
- Runtime failures now preserve the detailed cause in logs and provide recovery
  text appropriate to missing access, a disabled tap, or a timeout. Disabled
  taps suggest checking Accessibility without falsely claiming consent was
  revoked. The message no longer asks for a separate Input Monitoring grant.
- Scripts/package-test-dmg.sh packages a signed app using the existing branded
  dmgbuild layout without invoking build, deployment, Sparkle or publication.
  DMGBUILD_BIN can select an isolated virtual environment. Sign/notarize the
  resulting image separately before distribution.
- Installation, General settings, privacy and Caps Lock guides corrected to
  reflect automatic runtime start, the Metal tour, automatic keyboard setup,
  current effective-access checks, and backup/removal behavior.

## Evidence and remaining live checks

Working evidence: /private/tmp/keypath-onboarding-20261014/lifecycle/.
17 focused tests passed, including system registration refresh, pending approval,
failed/no-op changes, and preservation on uninstall registration failure.
The first full gate found one status-centralization lint violation (5511 passed,
1 failed). Corrected the caller to use the existing provider without changing the
lint allowlist; all 14 focused login/provider lint checks then passed. The final
gate then passed 5595 checks with one expected General Settings snapshot
difference. Visually reviewed the new Startup row, updated only that reference,
and reran the affected snapshot: passed. Live lifecycle acceptance remains pending.
Accessibility check passed across 382 UI files. Packaging the earlier preserved
app passed hdiutil verification; this is packaging validation only, not acceptance
of the new lifecycle build.

Live acceptance must verify the final candidate, not the previous ZIP:
1. Open DMG, inspect layout, drag app to Applications; check the downloaded-app
   path and that onboarding is clear without permission granted.
2. Enable launch at login in the actual settings UI, reboot and verify an app
   process starts without manually opening it. Disable and verify registration.
3. Grant Accessibility normally, then revoke it with no keys held; verify
   fail-closed runtime behavior and clear recovery. Regrant/reopen and verify.
4. Uninstall through UI; verify backup contents, app exit, missing app/config,
   removed login registration. Reinstall and verify fresh onboarding/config.

A held-output ledger is not proof of delivered key-up events after posting
permission is revoked: CGEvent.post has no delivery acknowledgement. Do not claim
physical held-key release under revoked permission from unit tests.

Air delivery/manual built-in-keyboard acceptance waits for the Air to reconnect.

## Live review findings

- Finder drag installation verified the candidate executable SHA256
  `0dbfb365b425295c18c88dcc174ab808ced280d5b1e3c5cfffe76941b6060a3e`.
- Fresh launch showed Welcome, then the Accessibility explanation without the
  old orange runtime warning. Grant/recovery and lifecycle checks remain pending.
- Live DMG review found the @2x PNG was displayed at twice its intended logical
  dimensions. Packaging now preserves pixels in a 144-DPI TIFF. The Finder frame
  also needs 32 extra points for its title bar so the bottom instruction is visible.
- Final local signed image: `KeyPath-lifecycle-final.dmg`, SHA256
  `f4ae64b372a17dcd045b1b74cd90543a8debd252f360ac07a8746c9dc3fa0898`.
  Not uploaded to Apple; final live layout verification pending. Earlier lifecycle
  image hashes are superseded, including the earlier pending approval request.

## Live outcome, 08:20 UTC

- Final DMG layout verified visually: correct scale and complete bottom instruction.
- Physical consent calibration passed 37 exact down/up pairs, zero repeats, stable secure focus.
- Normal Accessibility Settings approval passed; authentication dismissed and toggle on independently verified. No Input Monitoring grant requested.
- KeyPath automatically advanced to the Metal tour. After Skip tour, runtime reported active, Accessibility granted, and the overlay reported Ready. The settings drawer opened. This is not a new physical remapping acceptance test.
- Separate Settings window could not be opened through native menu clicks. Finder Settings and KeyPath Quit also failed through the same input route; main app thread was idle/responsive. This is an unresolved input-delivery/product-interaction issue, not a proven Settings scene bug. Do not apply speculative scene changes from this observation.
- Clicking Accessibility off opened a new authentication dialog. The runtime connection ended and overlay showed one issue, but the authentication change was not completed. A faded floating overlay intercepted the attempted Cancel click. Full revocation/regrant recovery remains unverified.
- Login-startup, disable-login-item, uninstall/backup/quit/reinstall acceptance remain open. Do not label this candidate production-ready.
- A scratch fixed physical Settings shortcut probe was prepared but never executed; it is diagnostic work, not product code or passing evidence.
- Owned lease cbx_4ecd82fcc1fc destroyed, cleanup_status complete; provider inventory empty. ESP32 serial 2884855553BC returned to host (Connected-To-Vm NO, autoconnect ask).
- New installer remains local and unnotarized. Apple upload approval and Air availability remain pending.

Next bounded action: qualify one harmless physical Settings shortcut before another full lifecycle attempt. Preserve the existing lab; do not rebuild infrastructure or change app menu routing without distinguishing input delivery from an app defect. Also verify that a faded overlay cannot obstruct system permission dialogs.

## Follow-up: overlay obstruction fix

The temporary October 14 build copy no longer existed when work resumed. The
experimental checkout and durable evidence were preserved. Implemented a focused
fix through the existing app suppressor: automatically hide for System Settings
and SecurityAgent, and reject automatic show/bring-forward paths while suppressed.
See `docs/bugs/overlay-obstructs-permission-dialogs.md`.

Focused regression tests passed twice (2 tests each), including after guarding the
remaining bring-forward bypass. Accessibility validation passed across 382 files.
The lab preflight passed with capacity available; no new lease was created.
Live dialog/restore validation remains pending. The existing final DMG does not
contain this follow-up source change; do not distribute it as the overlay fix.
New evidence: `~/keypath-review-evidence/20261015-overlay-review/`.

## October 15 final build and bounded live attempt

A parallel code review found and fixed three additional overlay races: launcher
activation before suppression checks, delayed hide completion after a restore,
and lost or unwanted restoration around Settings/explicit-hide transitions.
Suppression now hides immediately, invalidates stale animation completions, guards
launcher activation, and preserves only eligible restoration intent.

The final focused regression run passed all 3 tests. The Developer ID release
build and deep/strict signature verification passed. The final candidate is
`~/keypath-review-evidence/20261015-overlay-review/KeyPath-overlay-final.zip`:
SHA-256 `43b1805367064e45272dedede5f459b4d0cfe52facff232fa45360550c2fe829`.
Executable SHA-256:
`f74dbd8813467689ce918c801edd6114c95c2edb321ca68e95b9e7d2b524d791`.
This candidate is not notarized, installed on the host, or copied to the Air.
It supersedes `KeyPath-overlay-review.zip`, which lacks the final race fixes.

Disposable lease `cbx_28d7471b7d2c` was created using frozen lab source
`66f391c049e9bd7c15296c17381f4aae8e3e8205`. Parallels 27.0.3 no longer matches the
pinned SDK route. No allowlist was changed: an explicit native transport passed
22/22 read-only probes (root identity, stdout/stderr, exit status, literal args).

Public-console preparation stopped after normal autologin disable removed its
preference but left the original QA cache present. The safety journal refused
logout; no original password/cache contents were read or changed, and no public
account was created. Do not replay the claimed disable step or weaken this guard.
A Finder Settings menu click also dismissed its menu without opening Settings,
reproducing a non-KeyPath control failure. This does not prove a KeyPath menu bug.
No KeyPath permission or functional acceptance was completed in this lease.
Diagnostics were collected before lease destruction; see `live/destroy.log`.

Remaining release gates: live overlay/dialog restoration, completed permission
revocation/recovery, launch at login, uninstall/reinstall, notarization of the final
candidate, and Air delivery/manual acceptance when available. Fix or qualify the
public-console prerequisite before paying for another full application test cycle.


## October 15 public desktop recovery and Settings routing

Active approval mode was workspace-write with auto-review escalations. The
existing public-console recovery already covers the stale original autologin
cache; no new recovery framework was needed. Its 12 focused tests passed, and
`rig/README-public-test-console.md` now links the maintained recovery sequence.

Owned lease `cbx_b726c029cb77` reached a verified public desktop as
`keypathqa_b726c029` (UID 502), with original QA account preserved, autologin OFF,
cache absent, and bounded awake assertion. Transport exit 255 was reconciled
against state rather than replaying claimed operations. Setup Assistant completed.
The pinned `KeyPath-overlay-final.zip` installed and passed signature verification.
Welcome → Get Started → Enable Accessibility → System Settings worked normally.
KeyPath Accessibility remained OFF; this run did not establish runtime acceptance.

Finder Settings opened with Command-comma, although its menu selection did not.
KeyPath Settings and Quit remained unresponsive through this VM input route,
including after closing the setup window. A one-second process sample showed the
main thread waiting normally in the AppKit event loop, not a blocked main thread.
Do not claim these observations establish a new Settings-scene or quit defect.

A separate source review did establish a status-menu routing defect: Settings and
Rules callbacks posted tab-selection notifications without requesting a Settings
window. Both now call the existing `openPreferencesTab` helper. Three focused
overlay regression tests and the canonical Developer ID build passed. Candidate:
`~/keypath-review-evidence/20261015-overlay-review/KeyPath-overlay-settings.zip`,
SHA-256 `16a6c82f51a04b9ada479665fc60bf852802861b51aee6d3523f3f2625468bd6`.
This archive is signed but unnotarized. It was NOT installed in the above lease,
which retains the immutable previously admitted archive. Live acceptance of the
Settings routing fix remains pending; compile/regression success is not UI proof.

Follow-up inspection also found Repair/Remove assigns Command-comma, colliding
with standard Settings. Review that shortcut during the next menu-focused change;
no speculative scene rewrite has been made. Runtime-disconnected logs retry every
second before Accessibility approval; this is diagnostic noise, not proof of a
runtime failure after permission is granted.

Evidence is preserved in `~/keypath-review-evidence/20261015-overlay-recovery/`.
Permission recovery, overlay restore, login startup, and uninstall/reinstall remain
release gates. No Apple upload, public release, host install, or Air delivery was
performed in this pass.

## October 15 completed consent and recovery pass (15:47–16:01 Pacific)

This section supersedes the pending-consent status above. Normal System Settings
Accessibility consent completed in lease `cbx_b726c029cb77`, using the maintained
public-test consent workflow. No TCC database edits or host permission changes
were used. The app independently reported Accessibility granted, automatically
started its session runtime at 15:55:39, and displayed the Metal first-success
tour. Skip Tour dismissed it. No Input Monitoring grant was requested in this run.
This is runtime/UI evidence, not an end-to-end physical remapping test.

Live observations:
- The keyboard overlay hid when System Settings became active and returned when
  Finder became active, including a repeated focus round trip.
- Clicking the keyboard inspector control opened the drawer.
- Revoking Accessibility was detected at 15:57:17; validation and the health badge
  changed to an unhealthy state. The app and worker remained running.
- After restoring Accessibility, validation succeeded at 15:58:17 and the health
  observer changed from one issue to healthy. Recovery required no app restart.
- The 60-second fallback refresh creates a visible delay after permission changes.
  Improve refresh on return from System Settings using existing notification and
  validation paths; do not add a second polling framework. Detection/recovery is
  proven; behavior of physical remapping while permission is revoked is not.

The VM retained the immutable `KeyPath-overlay-final.zip` admission throughout.
It did not exercise the subsequent Settings menu-routing fix. A source-confirmed
Command-comma conflict was also fixed: Repair/Remove no longer claims the standard
Settings shortcut. The app product build passed (74.11 seconds), the canonical
Developer ID release build passed, and deep/strict signature verification passed.
The newest candidate containing both menu fixes is:
`~/keypath-review-evidence/20261015-overlay-recovery/KeyPath-menu-final.zip`
SHA-256 `2980ec20d4261ecbc8103b9de48c74e04e5c8581c41c23ff613a9fbecfb534f3`.
It is signed but unnotarized; no Air delivery or host install was performed.

Evidence: `live/consent-resume/`, `live/post-consent.log`, `live/revocation.log`,
`live/final-runtime.log`, `live/regrant.log`, and build logs in the same evidence
root. Lab artifact collection succeeded (including screenshot) at
`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_b726c029cb77/20261015T230005Z`.
See `live/destroy.log` for lease cleanup.

Remaining gates: live acceptance of the newest menu fixes; faster permission
status refresh; active-overlay authentication/layer-change edge cases; launch at
login; uninstall/reinstall; final notarization and Air manual acceptance. Do not
label the candidate production-ready or bug-free based on this bounded pass.

## October 15 final lifecycle candidate follow-up (16:49 Pacific)

The permission-status delay now refreshes through the existing canonical validator
when System Settings deactivates. It does not require KeyPath itself to become
frontmost and adds no polling loop. The focused MainAppStateController run passed
36 tests. Live timing verification of this change remains pending.

A parallel lifecycle review found that pending opt-in KindaVim telemetry could
recreate Application Support data after uninstall. The store now drains before
backup, suspends new writes through successful exit, and resumes on failure
without changing opt-in. The application termination callback also skips the
post-uninstall flush. See `docs/bugs/uninstall-pending-telemetry.md`.

All 36 lifecycle regressions passed: 19 telemetry (including two new uninstall
cases), 8 session uninstall, 5 login-item, 4 application termination tests. Logs:
`permission-refresh-tests.log` and `lifecycle-final-tests.log` under the retained
October 15 overlay-recovery evidence directory. A new canonical signed build is
being prepared for live acceptance. The Air SSH probe timed out; delivery and
physical built-in-keyboard acceptance remain pending.

## October 15 lifecycle acceptance (16:53–17:10 Pacific)

Canonical signed candidate `KeyPath-acceptance-final.zip` (SHA-256
`5f10fa4d4bd8b546db655e6f2cd855abdedaa27a6b77c93e06b5f5cec44c3369`)
was installed in owned lease `cbx_3c4151e21d63`, macOS 26.5.2. This used the
base keypathqa console account without changing its credentials or autologin;
it is a lifecycle test, not fresh public-account permission-consent evidence.

Passed independently:
- Launch at login enabled via UI and verified in `sfltool dumpbtm`; after normal
  app quit and a real guest reboot, KeyPath launched itself (PID 592, boot UUID
  C84B0AAF-0E11-47D3-834F-D21BB3D374E4). Runtime startup with Accessibility was
  not tested in this guest.
- Disabling launch at login changed macOS disposition to disabled; reenabled
  before uninstall to exercise its cleanup.
- Status-menu Settings opened General using Down/Down/Return. Status-menu Quit
  using a visibly highlighted item and Return exited the app (independent pgrep).
  Direct synthetic menu clicks and some rapid key sequences did not activate
  actions; do not infer a product defect from those failed deliveries.
- Repair/Remove → Back Up and Uninstall completed, exited without Finder errors,
  removed /Applications/KeyPath.app, ~/.config/keypath and Application Support/
  KeyPath, and left the login-item record disabled (macOS retains historical
  records; absence of that record is not required).
- Finder independently showed the backup in Downloads, with 0-keypath,
  1-KeyPath, preferences.plist (906 bytes), and README.txt. Shell enumeration
  was denied by guest Downloads privacy; byte-for-byte backup verification
  was not completed in this pass.
- Reinstalling the same immutable candidate returned to Welcome onboarding.

Evidence is retained under the October 15 overlay-recovery directory in
`final-lifecycle/`. The base's Peekaboo app selected a different bridge after
reboot and menu inspection reported missing AppleScript automation permission;
keyboard navigation in the Parallels console completed the required actions.
No permission bypass was used.

The exact candidate's notarization upload was rejected by automatic approval
review because the previous approval was for a different ZIP. A new approval
request identifies SHA 5f10fa4d and Apple as destination; no upload occurred.
Remaining: live timing of faster permission refresh, active-overlay
permission/authentication/layer edge cases, final notarization/package validation,
and physical Air acceptance/delivery when reachable. Do not declare production
readiness until these gates are closed or explicitly scoped out.

## October 15 approved notarization continuation

The user explicitly approved sending SHA 5f10fa4d to Apple. The first invocation
stalled locally in SecItemCopyMatching / Keychain integrity checking, with no
network socket and no submission receipt. The API-key file documented in the
shared registry was absent on both mini accounts. Stopped only that invocation;
no credential or Keychain settings were changed.

A secure non-echoing notarytool prompt supplied the existing APPLE_NOTARY_PASSWORD
from sops in memory (no secret in arguments, logs, or plaintext files). Apple
history succeeded and showed no submission from the stalled attempt. The exact
approved archive was then submitted using the repository signing helper with
that scoped transport. Preserve submission state before retrying any upload.
The Air SSH probe still timed out.

Read-only edge review found no new confirmed overlay blocker. One bounded
freshness risk remains to reproduce: revalidate joins an in-flight validation,
so a permission edit after that run's snapshot may await the 60-second fallback.
This is a pending concurrency regression test, not evidence of permission bypass
or continued physical remapping after revocation. Do not silently mark the live
permission/overlay edge gates complete from source review.

Apple accepted ZIP submission `c955bd50-a52e-434d-aa88-178717d4ea5d`.
The staged app was stapled and passed Gatekeeper as Notarized Developer ID.

Installer verification then reproduced a packaging defect: dmgbuild's
hide_extensions setting writes com.apple.FinderInfo on KeyPath.app. The source
passed strict codesign; the mounted packaged app failed with resource-fork/Finder
information detritus. Removed that layout setting and added read-only mounted
bundle signature verification to package-test-dmg.sh. The corrected DMG's
contained app passes deep/strict codesign, stapler validate and Gatekeeper.
No app binary or signed resource changed; no application rebuild was needed.

Corrected signed installer retained beside the ZIP:
`KeyPath-1.0.2-driverless-verified.dmg`
SHA-256 `0cd1b07ecaca831acf9b3193b0d65c365e157443dccea0f0f3006f0bb5ce775b`.
Its container upload requires separate approval under automatic review. The
initial DMG aca11ec3 is superseded and must not be shipped; neither DMG was
uploaded. The latest approval request explicitly names corrected hash 0cd1b07e.
Air remains offline. No public release or host installation occurred.

## October 15 completed installer notarization (17:34 Pacific)

The user's Continue authorized the corrected DMG submission. Apple accepted
`b77403c0-6af9-45c1-bfc5-25931e9286b0` for submitted SHA 0cd1b07e. The final
retained DMG was stapled and passed stapler validation, strict codesign, and
Gatekeeper open assessment as Notarized Developer ID. The app inside had already
passed its separate deep/strict signature, ticket and Gatekeeper checks.

Finder visual inspection confirmed the app, Applications shortcut, and connecting
arrow. The preview volume was detached; KeyPath was not installed on the host.
The Air SSH check still timed out, so no delivery occurred. App/installer
notarization is now complete; remaining permission/overlay live-edge and physical
Air acceptance gates above are unchanged. Final artifact and submission evidence
are retained in the October 15 overlay-recovery directory.


## October 15 explicit permission-refresh race

The remaining source-review finding was reproduced deterministically: an explicit
`revalidate()` during an in-flight validation joined the old capture and performed
only one check. The new regression failed before the fix. MainAppStateController
now coalesces explicit refresh requests into a follow-up capture, invalidates
caches again after the old capture completes, and clears the in-flight task only
inside its owner. Ordinary concurrent refreshes still share a capture. The forced
manual-refresh entry point uses the same policy; no new poller or service exists.

The focused MainAppStateController run passed all 36 Swift Testing tests (runner
summary counts 37 including its additional harness result), with no build warnings.
Independent read-only concurrency review found no blocking defect. Logs:
`/private/tmp/keypath-refresh-regression.log` (expected regression failure) and
`/private/tmp/keypath-refresh-fixed.log` (passing). A fresh signed app build is
underway, with host deployment, notarization and publication disabled; live
permission/overlay acceptance is still pending and is not inferred from these tests.

The prior notarized installer remains immutable at
`/Users/malpern/keypath-review-evidence/20261015-overlay-recovery/KeyPath-1.0.2-driverless-verified.dmg`.
Its final **post-staple** SHA-256 is
`c54b80a31cdf1d31fe84aa05847c573c60151470c98b1c58125c9391d174f6c2`.
It does not include this new source fix. The Air still timed out on the latest
SSH check, so no installer delivery is claimed.

The canonical production build completed successfully with all signing identity
contracts and deep/strict codesign verification passing. Candidate:
`/Users/malpern/keypath-review-evidence/20261015-permission-refresh/KeyPath-permission-refresh.zip`
SHA-256 `dc8cf2046b6b5585d6d12772dd99f2e2bb0ea5ad5c4227b0b0bd139e2e81ca5b`.
It is signed, **not notarized or live-accepted**. The evidence directory retains
regression/build logs, tracked source patch and untracked-file hash manifest.
No VM lease was created for this candidate yet. Maintained lab preflight passed;
its current public-desktop runbook uses boot-identity protocol v2, so any new
permission run must use fresh v2 journals rather than reusing old v1 receipts.

## October 15 refreshed candidate live acceptance (in progress)

Candidate `dc8cf2046b6b5585d6d12772dd99f2e2bb0ea5ad5c4227b0b0bd139e2e81ca5b` is installed in owned macOS 26.5.2 lease `cbx_ae5f5515700b`. The frozen v2 controller and fresh journals are at `/private/tmp/keypath-refresh-acceptance`. Approval mode remains workspace-write with restricted network and auto-review escalation. No host installation occurred.

The first-boot settling gate correctly waited through the Parallels Tools reboot and a quiet period. Public account/home preparation succeeded on its first attempt; normal Setup Assistant was completed, temporary public autologin was restored OFF, and a bounded wake assertion was verified. Generic UI preflight correctly refused the base-account route because UID502 owns this desktop; the maintained public-account helpers were used instead. This is not a product or permission failure.

Secure-field calibration passed with 37 down/up pairs, zero repeats and no lost focus (about 198 seconds). Fresh KeyPath showed Welcome and Enable Accessibility; opening Settings reached the normal authentication dialog. Consent approval and product capability acceptance remain in progress. The Air SSH probe timed out; no delivery is claimed.

## October 15 consent results and overlay dismissal follow-up (18:14 Pacific)

The normal Settings consent adapter completed successfully (`approve.log`:
`passed=true`, `normalSettingsConsent=true`). The refreshed candidate automatically
started its runtime and reached the Metal keyboard tour, step 1 of 4. Skipping the
tour reached the working overlay. Settings suppressed the overlay and Finder
restored it; the drawer opened after recovery. Menu dismissal was initially
inconclusive in immediate console captures; the subsequent capture showed the
overlay hidden, and it stayed hidden after Finder activation. No menu defect is
claimed from those early captures.

Important correction: the attempted Accessibility OFF toggle opened an
authentication dialog and was cancelled. Logs continued to report Accessibility
granted. This proves recovery from an interrupted authentication flow, NOT a
completed revoke/regrant cycle. The maintained consent adapter supports enabling,
not authenticated revocation; that acceptance gate remains pending. No Input
Monitoring grant was requested.

Source review identified two narrower, independently actionable lifecycle bugs:
closing through the overlay X did not preserve explicit-hide intent, and closing
the drawer instantly could leave an opening timer (or queued MainActor tick)
writing its reveal value. The close callback now records explicit dismissal;
instant transitions cancel timers; queued ticks check their animation generation
and timer validity. Hiding during the first opening frame now closes the drawer
as well. These reuse existing state and tokens, with no additional service.

Both OverlayDismissalTests passed, including a deliberately queued opening tick
followed by instant close. Independent read-only review found no blocker. A live
check of final window geometry after interrupting AppKit's frame animation is
still required. The signed production build is in progress; these changes are not
yet in a notarized installer. Logs: `/private/tmp/keypath-overlay-dismissal-tests.log`
and `/private/tmp/keypath-overlay-dismissal-build.log`.

VM evidence collection passed (download and screenshot status 0). Owned lease
`cbx_ae5f5515700b` was deleted successfully. Cleanup warned that its optional GitHub
Actions hydration stop marker could not be written (transport 255); the provider
VM deletion itself succeeded. Air physical acceptance and updated artifact delivery
remain pending. No host installation or public release occurred.

The overlay-dismissal production build completed, including deep/strict signature
verification and all identity contracts. Retained signed candidate:
`/Users/malpern/keypath-review-evidence/20261015-overlay-dismissal/KeyPath-overlay-dismissal.zip`
SHA-256 `0654591d0472b9645277d5c00767823f85d43d5e3e36f4da7d0e49a3476cc397`.
This candidate is NOT notarized or live-accepted. Two focused regressions passed;
its build/test logs and source patch are retained beside it. The latest Air SSH
probe still timed out. Next: validate interrupted drawer geometry and explicit X
close in the new candidate, complete pending permission/launcher edge acceptance,
then notarize/package the final accepted candidate and deliver when Air is online.

## October 15 iteration-performance follow-up

The measured ~33-minute cycle and pre-run capability/reuse policy now live in
`/Users/malpern/local-code/vm-lab-automation-robustness/docs/iteration-workflow.md`,
linked from the lab README/public-desktop workflow and KeyPath's AGENTS.md and
remote-installer-lab guide. Documentation whitespace checks passed.

Correction to the proposed speedup: retaining the lease is immediately useful
for more scenarios/retests of the same artifact. The current install-app route
has no replacement-artifact admission, so retaining it alone cannot safely remove
setup from a new-build cycle. That requires a small separately qualified extension;
no such extension or prepared base is claimed complete. No VM/template changed.

Next run preflight for signed candidate 0654591d:
- Interrupted drawer opening: check final frame and reveal after immediate hide;
  compare final width to the recorded collapsed frame, not just a click result.
- Explicit X close: verify window hidden, activate Finder then KeyPath, verify it
  remains hidden until an explicit show. Record actual window visibility plus image.
- Launcher while Settings is frontmost: require a supported trigger and observable
  focus/visibility postcondition before admitting the scenario; otherwise mark pending.
- Revoke/regrant: pending unsupported authenticated-revocation route. Do not spend
  calibration/setup on the assumption that enable-only consent covers this test.
- Batch supported checks in one owned session. Collect/destroy after the session;
  if a new candidate is needed, current admission still requires a fresh lease.
- Air delivery remains deferred while SSH is offline. Notarization follows final
  live acceptance; the current archive is signed only.


## October 15 replacement-artifact implementation (offline validated)

The maintained lab now has `rig/replace_product.py`, a guest transaction helper,
and per-lease revision admission. See its `docs/product-replacement.md` for exact
commands and limits. Original manifests/archives stay intact; revision attempts and
receipts are collected separately. Failed/unknown attempts retain locks; explicit
reconciliation verifies the guest read-only and settles only matching evidence.
Original install-app refuses after a revision claim. No TCC/settings reset occurs.

21 focused tests passed (13 guest, four controller, four host admission), plus
existing lab shell/installation suites. The current signed ZIP 0654591d passed
structural/hash validation; executable SHA is
`9730badd358c7097c2c89abafc61e6fb6d2c322dea6efb06cd5ef967fd4f5984`.
No live replacement, new VM or base change occurred. Next is one bounded two-build
qualification and timing run, not another lab redesign. No speedup is yet claimed.


## October 16 same-VM replacement qualification

Supersedes the earlier “not live-qualified” replacement status. On owned macOS
26.5.2 lease `cbx_0bf6c66b5523`, signed A (`dc8cf204…`) was replaced by signed B
(`0654591d…`) through the guarded revision route in **5.994 seconds**. The original
manifest and captured settings/preferences remained byte-identical. B's normal
public-user launch passed runtime verification (parent 7958, worker 8168, TCP
127.0.0.1:37001) without regranting Accessibility. Drawer open/close and View →
Toggle Overlay passed; the overlay stayed hidden after activating Finder.

Correction to the previous UI checklist: the visible X in the expanded drawer is
“Close settings drawer,” not an overlay-close control. Do not claim overlay-X
acceptance from it. Interrupted AppKit frame geometry remains untested.

Remaining onboarding observation: A stayed on Enable Accessibility after normal
consent was ON and authentication dismissed, repeatedly logging AX denied. A
normal menu Quit/relaunch recovered runtime but went directly to the overlay;
no Metal tour was observed. Investigate permission refresh and tour routing before
release. Do not attribute this to replacement, which happened afterwards.

Timing: initial VM settling about 4m40s; desktop/account preparation reached ready
at about 12 minutes; calibration took 190 seconds; consent plus investigation
brought the first verified runtime to about 21 minutes. The six-second figure is
only replacement admission/staging/verification/swap, not the whole run or build.
A permission-toggle transport error was reconciled once from its existing journal;
an initial runtime check run as root was invalid and rerun as the public user.

Evidence: `/Users/malpern/keypath-review-evidence/20261016-replacement-qualification`.
Collected lab artifacts (download and screenshot status 0) include revision intent
and receipt. No host KeyPath installation, base promotion, notarization or Air
shipment occurred. B remains signed-only and is not final release acceptance.

Cleanup completed: owned lease deleted and provider absence independently verified.
The optional hydration stop marker returned transport 255; this did not prevent
VM deletion. All qualification evidence and collected artifacts are retained above.
