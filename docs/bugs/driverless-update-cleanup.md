# Driverless update cleanup

Sparkle's postponed-install continuation previously called an installer operation that the session backend rejects, then continued installation even when cleanup failed. The session app must stop through its existing ServiceLifecycleCoordinator and verify held-output/Caps recovery before invoking the continuation.

UpdateService now uses the injected runtime stop owner. The coordinator rejects Start, Restart and automatic resume while preparation/installation is active and invalidates already queued starts. Failed cleanup pauses installation, releases this admission, and exposes an actionable error in About; Check for Updates retries the retained continuation. Abort releases admission and invalidates the continuation. A replacement handler receives fresh preparation after any suspended old attempt completes. Successful installation keeps admission until abort or process exit.

Nine focused tests cover cleanup ordering/refusal/retry, suspended aborts, replacement after abort, queued/manual/automatic starts and recovery-refusal persistence. Final logs: `/private/tmp/keypath-session-update-build-v5/`. Accessibility379 and whitespace checks passed; independent source review found no remaining blocker in this scope. Build used the established verified cached Metal artifact with the plugin restored byte-for-byte, not a fresh Metal compilation.

## Remaining release gate

Sparkle does not promise to call shouldPostponeRelaunchForUpdate for every installation, including some termination-time paths. This change validates the postponed continuation, not universal update cleanup. Test and resolve update-on-quit with preserved configuration and Caps recovery before release. Normal app Quit must remain usable during retained uncertainty; do not cancel every Quit and impede system reboot. No signed live updater acceptance or production release is claimed here.

## Graceful app termination

The AppDelegate now defers every graceful Quit until `viewModel.stopKanata`
returns through the admitted ServiceLifecycleCoordinator. The runtime owns held
output release and Caps journal recovery; no synchronous replacement cleanup is
introduced. A separate termination hold invalidates queued starts before the
first Task hop and rejects new Start, Restart, automatic resume and Caps selection
while cleanup/termination is pending. Repeated termination requests coalesce.
An update abort cannot release this separate hold.

Windows close and plugin flushing start only after the cleanup decision. A
successful stop keeps admission held through the existing bounded plugin flush
and process exit. A refused ordinary Quit logs uncertainty and still exits; the
Caps recovery record remains available to the next launch. This failure branch
replies immediately without a plugin-flush suspension: otherwise an update could
become staged after the ordinary refusal decision during that optional wait.
Process exit closes its windows. A refused termination
with observed update evidence replies false, leaves windows/plugins intact and
releases only the termination hold so the user can resolve the runtime issue and
retry. The menu-bar Quit entry no longer closes windows before that decision.

UpdateService records update expectation synchronously in its nonisolated
Sparkle callbacks, using a lock rather than scheduling that observation on the
main actor. `willExtractUpdate` runs before installer launch in the bundled
Sparkle source. `willInstallUpdateOnQuit`, `willInstallUpdate`, and the postponed
relaunch hook also record evidence. Returning false from install-on-quit observes
without taking over scheduling; neither return value prevents installation on
termination. A successful update-cycle completion must not clear this evidence:
the automatic driver can complete with nil error while its external installer
remains alive. An extraction error can clear unstaged expectation; once staging
has been observed a later check error cannot prove that external installer was
cancelled, so expectation is retained conservatively for this process.

Focused decision tests cover synchronous admission, cleanup before window/plugin
work, repeated Quit, ordinary cleanup refusal, update staging during suspended
cleanup, cancelled-update UI preservation, successful retry and staged evidence
surviving cycle completion. A lifecycle test exercises a queued Start, new Start,
Restart and resume, stop admission and an overlapping updater abort. The integrated termination/lifecycle/update suite passed (runner 37 passed), with
no compiler or app warnings/errors, accessibility380 and whitespace checks. Logs:
`/private/tmp/keypath-termination-build-v1/`. Independent source review found no
concrete blocker within this observed-update scope. Cached Metal was verified and
the temporary plugin restored byte-for-byte; no live updater acceptance is claimed.

### Update safety remains a release gate

This closes ordinary graceful Quit and **observed** update termination. It does
not establish universal Sparkle safety. An external installer staged before this
app process can survive and be resumed without `willExtractUpdate` in this
process; callback evidence does not prove absence of that installer. Forced
termination/process death also bypasses the AppKit decision. Retained staged
evidence is conservative and can cancel a later refused Quit even if an external
installer was subsequently cancelled without a definitive callback. Resolve and
verify these paths with preserved Caps/configuration before public release. Do
not change this limitation into a claim of universal update cleanup, and do not
cancel every ordinary Quit as a substitute.

Evidence reviewed in bundled Sparkle 2.9.4: `SPUUpdaterDelegate.h`,
`SPUCoreBasedUpdateDriver.m` (`extractUpdate`, `installerWillFinishInstallationAndRelaunch`),
`SPUInstallerDriver.m` (stage 2 may notify installation after target exit), and
`SPUAutomaticUpdateDriver.m` (scheduled installer survives nil-error completion).


### First driverless release: manual downloads

Session builds do not construct or start the Sparkle controller. “Download
Update…” opens the official GitHub releases page in the browser; it does not
check, download, stage, or replace the running application. About hides automatic
checks, automatic installation, and channel controls. Stored Sparkle preferences
cannot enable those paths. Quit KeyPath before replacing the app; configuration
files remain outside the application bundle.

This is a temporary release simplification, not a new updater implementation.
Admitted graceful termination remains in force. It does not cancel an external
installer already staged by an older build: migration from such a build still
requires a separately verified clean manual transition. Restore automatic updates
only after previous-process installer and configuration/Caps cleanup behavior is
qualified. Public release and migration acceptance remain separate gates.

### Signed guest acceptance, October 6

Non-debug source b11ef90c9 passed a fresh-account consent flow in owned lease
cbx_8639d8a80d3e. The welcome screen names Accessibility and Input Monitoring and
briefly mentions Caps Lock tap + hold. After normal consent, the runtime page
initially retained its failed pre-consent start; its normal Restart action reached
Ready without reopening the parent. Worker 2532 independently reported both
permissions, a running active tap, and an empty held-output ledger.

With both legacy automatic-update preferences set before launch, the actual
Download Update menu opened the official GitHub release page in Safari. The same
parent/worker remained running and the profile hash stayed unchanged. The current
public release is still v1.0.1, so a downloadable driverless release must exist
before shipping this candidate. Normal Quit then retired both parent and worker,
preserved the profile, and logged runtime stop before window closure/plugin flush.

The normal About command uses the standard macOS panel, not the unused custom
AboutView. The follow-up menu polish adds replacement instructions to that actual
panel, removes the duplicate simulator/repair entry, hides Input Capture
Experiment outside DEBUG, and names the existing wizard Set Up KeyPath. The
summary container's label had overridden the visible Open Rules button in AX;
removing that parent label lets the explicit button label remain authoritative.
These follow-up changes require their own signed visual acceptance.

Raw receipts: `/private/tmp/keypath-manual-download-live-01`. Canonical destruction
and independent provider absence, retained stopped template, and detached
nonpersistent fixture checks passed. Earlier failed offscreen menu delivery and
first-run helper refusal remain separate failures. No manual replacement,
notarization, legacy staged-installer cancellation, or broad keyboard acceptance
is claimed by this run.
