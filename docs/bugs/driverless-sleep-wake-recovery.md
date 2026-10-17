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
