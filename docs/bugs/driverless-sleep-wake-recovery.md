# Driverless Caps Lock recovery after sleep

## Behavior and cause

Sleep retires the owned runtime and restores its output/Caps mapping. The parent
must start a fresh worker automatically once the user's session is available.
No setup wizard or manual restart should be needed.

Three failures were reproduced on the Air on 2026-10-17:

1. Cleanup failure replaced the original sleep reason, hiding automatic recovery.
2. A key pressed between parent readiness and worker activation caused a terminal
   startup refusal. Replacement cleanup also cancelled the recovering supervisor.
3. A quick lid close/open woke the screen before macOS delivered system did-wake.
   The parent waited roughly 18 seconds after unlock for that later notification.

## Recovery contract

- Preserve the original retirement reason separately from any cleanup failure.
- Resume only after output/Caps cleanup succeeds, under existing lifecycle admission.
- Accept system wake, screen wake and session reactivation. A signal preceding
  the owned terminal report cannot authorize a later sleep recovery.
- Keep console readiness, Secure Input and all-keys-up checks. Retry only an owned
  held-key activation refusal after successful cleanup, at a bounded polling rate.
- Stop, Quit and newer requests invalidate the pending recovery generation.
- The recovering task relinquishes the retired worker's supervisor handle so
  replacement cleanup cannot cancel recovery itself.
- Record wake source and changing readiness gates, never key identities or content.

Affected installer/repair matrix rows: **Session runtime stopped or not ready**
and **Session tap active and TCP responding**. Readiness still requires current
owned process, tap and TCP evidence; a saved rule or overlay is not proof.

## Validation and release evidence

38 focused tests passed: lifecycle interleavings, environment boundaries and
retirement-report compatibility. These include wake ordering, stale signals,
held-key retry, cleanup failure, report ownership, Stop and Quit.

Micah verified Caps Lock as Escape immediately after wake/unlock and again after
30 seconds. Logs show two quick-lid cycles recovering about 1.2–1.3 seconds after
the readiness gate cleared. Later system-wake events also recovered successfully.
This does not prove zero-latency activation or every macOS power mode.

The final artifact is the exact tested build, packaged without rebuilding:

- App executable SHA-256: `8aeb5f82c94f06939b2feb44e837ceed0c4df1deb0e9e45e5003b406011f018f`.
- Installer: `KeyPath-20261017-wake-final.dmg`.
- Installer SHA-256: `bf980471af60f47dea8ece6710a7a6f2ecdb7be37491c4966e4fed7d29659f9a`.
- Apple accepted app submission `7a09b526-a27c-4a7d-b747-f20f1950ee34` and
  DMG submission `85c1582f-9b0c-46c8-8666-a2ae123104f9`.
- App and DMG tickets stapled/validated; Gatekeeper accepted both.
- Evidence: `/Users/malpern/keypath-review-evidence/20261017-sleep-wake/`.

## Remaining acceptance

- A longer Apple-menu Sleep interval (at least one minute), followed by physical
  Caps Lock testing immediately after unlock, remains pending. The VM cannot
  substitute for this hardware acceptance check.
- The tested app is already installed on Air. Final DMG delivery was interrupted
  when Air went offline. The existing delivery automation targets the exact hash
  above, verifies before finalizing Downloads, and pauses after successful delivery.
- This focused commit does not incorporate the worktree's earlier uncommitted
  onboarding/driverless changes. The notarized artifact includes those changes;
  this commit alone is not a reproducible source snapshot of the entire release.

## Final cleanup review

Focused wake fix committed as `fb1c38c83`. Review checked retirement-reason
preservation, ownership/cleanup gating, stale wake rejection, cancellation and
Stop/Quit intent ordering. No additional blocking wake-path finding was identified.
After confirming this branch is not behind origin/master, `Scripts/test-full.sh`
passed against the complete working tree: **5,627 tests**, including snapshots;
exit 0, build 76 seconds, tests 194 seconds, total 271 seconds. This is not a
claim that only the focused commit was tested in a clean checkout.

The release evidence directory also holds a private `final/source-checkpoint/`:
base commit IDs, binary working-tree patches (KeyPath and Kanata), and the
untracked source archive. It preserves the broader experimental source state
without folding unrelated changes into the wake commit. Full test logs are in
`final/review/`. The longer physical sleep test and verified installer delivery
remain pending; neither a unit test nor a successful notarization substitutes
for those checks.

## Reopened: final installer fails longer sleep acceptance

Final DMG delivery and replacement installation on Air completed with matching
hashes. Micah then reported Caps Lock failure after sleep. The 17:56 cycle logs
show screen wake at 17:56:51.611, readiness at 17:56:55.237, replacement worker
1052 launched at 17:56:55.404, and terminal `managed-caps-restoration-pending`
at 17:56:56.095, coincident with the parent's system-wake notification.
The app remained alive but had no worker. This invalidates production acceptance.

The failed startup report was deleted by normal cleanup, so the original
retirement reason cannot be recovered from this cycle. A late system-wake event
interrupting replacement startup is the leading explanation, not yet proven by
that report. The running-worker supervisor already handles this boundary, but
the startup retry classifier previously allowed only held-key activation failure.

The follow-up change allows an owned stopped/failed startup report whose original
reason is `system-wake-observed` to retry after successful cleanup, under the
same intent and readiness checks. It does not retry unknown cleanup failures,
permission errors, foreign reports, or a new sleep event. Startup now logs state,
original retirement reason and failure before cleanup deletes the report.
Regression coverage includes late wake with/without pending cleanup, foreign
ownership, nonterminal state and new sleep. Physical acceptance remains required.
Evidence: `post-final-failure/air-debug.log` beside the prior release evidence.

Follow-up candidate installed on Air: executable SHA-256
`67843a16e47ae73da194306d61cf26b976f785b801fad6ed70133acdd059f2af`;
ZIP SHA-256 `dafeb8e84229f1af563a00722710b8ab214518f05dec3d06bda9c56319a6456a`.
39 focused tests passed. The candidate uses the prior verified companion/resource
bundle with a rebuilt release app executable and Developer ID local signature;
it is not notarized. Owned-session verification passed: parent 14733, worker
15261, matching report and TCP 37001. Initial packaging omitted the executable's
Frameworks rpath; launch verification caught it, the path was added before
re-signing, and the corrected candidate passed structural and live verification.
The next physical sleep test is still pending. Do not use the earlier 'final'
DMG to overwrite this newer test candidate.

### Candidate 5 physical feedback and logs, 18:22 PDT

Micah reports Caps Lock works immediately after unlock and after 30 seconds.
Screen wake was observed at 18:22:04.642, readiness cleared at 18:22:08.046,
and runtime became ready at 18:22:09.875. A later system-wake notification at
18:22:26.488 recovered by 18:22:28.378. Parent PID 14733 stayed unchanged;
final worker 55654 passed owned-report/TCP verification and reported an active
Caps generation matching its nonce. No terminal startup failure appeared in
this cycle. Evidence saved as `wake5-user-pass.log` and
`wake5-user-pass-power.txt` in `post-final-failure/`.

This validates user-visible recovery for this cycle. The power log does not
contain a new explicit Entering Sleep/Wake-from-Deep-Idle pair; it reports a
15,022 ms sleep-notification delay from Transmission. Do not label this as
confirmed one-minute deep sleep or proof that the new startup-race branch fired.

After Transmission exited, the next observed cycle retired at 18:24:58.157,
received screen/system wake at 18:25:02.961/18:25:03.041, passed readiness at
18:25:04.996 and reported runtime ready at 18:25:06.245. Owned-session verification
passed (same parent 14733, worker 61542). Micah reported Caps Lock works immediately
and after 30 seconds. Power log now confirms Clamshell Sleep and Deep Idle wake,
but both timestamp 18:25:02 with zero seconds recorded, triggered by lid/user
activity. This is a verified short physical sleep recovery, not a one-minute
residency. Evidence: transmission-quit-sleep-test.log and
transmission-quit-verification.txt in post-final-failure/.

Immediate-wake investigation: unified powerd log confirms display off at
18:24:57.623, then a newly activated `com.apple.powermanagement.lidopen`
assertion at 18:25:02.834 and wake reason `lid ... RTP.multi-touch/UserActivity`
at 18:25:02.845. This does not prove a network wake or identify who/what moved
the lid. No PreventSystemSleep assertion was present. Transmission had exited.
Stopped this task's two live SSH tail streams to remove active network monitoring
from the next trial. Use the app's existing on-disk log and collect after wake;
leave normal power settings intact. Next isolation: Apple-menu Sleep with lid
left stationary/open, no input for 90 seconds measured on a separate device.

### Lid-open software sleep: confirmed physical sleep recovery

Micah reports waiting 90 seconds with lid open and Caps Lock working immediately
and after 30 seconds. The power log's measured interval differs: Software Sleep
18:27:14, network-triggered DarkWake 18:27:25 (11 seconds asleep), Maintenance
Sleep 18:27:35, and power-button FullWake 18:27:48 (13 more seconds asleep).
Thus actual sleep is confirmed with an intervening background wake, but the
recorded elapsed sleep-to-full-wake window is 34 seconds, not 90.
KeyPath readiness cleared 18:27:48.473 and worker 66891 was ready 18:27:49.809
(1.336 seconds later). Parent 14733 remained unchanged. Owned report/TCP
verification passed at 18:28:12. No startup failure appears in this cycle.
Evidence: post-final-failure/lid-open-90s-verification.txt. This is valid real
sleep/recovery evidence; do not claim a verified continuous one-minute sleep.

### Candidate 5 notarized installer delivered

User authorized notarization and delivery. Packaged the already-tested executable
without rebuilding. Added a secure signing timestamp; CodeDirectory hash stayed
`3626a6af1cadc5985e533700625c47a0d382da33` before/after signing. Apple accepted
app submission `563c67da-719e-4b24-9811-ab44f45aebc8` and DMG submission
`920fb10c-b4e8-448b-a4d2-efca17007fe9`. Both tickets stapled and validated;
Gatekeeper accepted both artifacts. New installer in Air Downloads:
`KeyPath-20261017-wake5-final.dmg` (supersedes the earlier wake-final DMG).
Post-staple SHA-256 `aabf99cdb2dd3c5ab640e1a5b3e330a833a9762b200330aaedb46d6ff09027f2`
verified locally and remotely before finalizing the filename. Air stapler
validation passed. The installed test app was not replaced during delivery.

Artifacts and source checkpoint: `20261017-sleep-wake/wake5-final/` under the
private review evidence root. Remaining public-release work includes integrating
the experimental source changes into a reviewed reproducible commit and a final
install/relaunch smoke test of this distribution artifact. A continuous one-minute
sleep has not been proved; the real shorter sleep/dark-wake/recovery did pass.

Final candidate-5 broad gate: `Scripts/test-full.sh` passed **5,628 tests**,
including visual snapshots (exit 0; build 98 s, tests 225 s, total 324 s).
Logs: post-final-failure/full-tests.log and full-runner.log. Tests ran against
the complete working tree, not a clean integrated production branch.
