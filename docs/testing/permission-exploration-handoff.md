# Driverless permission investigation — current handoff

Updated October 5, 2026. Execution authorization remains in force: guest-only testing, normal guest permission consent, ESP32 physical input, and experimental branch commits/pushes. Active approval mode: workspace-write, restricted network, auto_review. No owned VM is active; the last guest was destroyed and the ESP32 independently verified detached.

Read [the active workflow](driverless-active-workflow.md), then [the failure ledger](permission-experiment-failure-ledger.md). The prior handoff is preserved byte-for-byte in [the historical archive](archive/permission-exploration-handoff-through-2026-10-05.md). Historical percentages and active-guest entries there describe their recorded time, not current state.

## Evidence and remaining milestones

- Selected lab workflow: two consecutive setup-to-cleanup qualification runs passed. This supports this workflow, not a claim of general VM-lab reliability.
- Latest physical trial: all 542 transport calls succeeded. The callback stalled for approximately 752 ms; no genuine macOS tap timeout was observed. Profile restoration, key release, target retirement, VM destruction and independent provider/USB checks passed.
- Pending: genuine timeout and new-parent recovery; restart and console/session transitions; Caps Lock ownership/recovery; reduced-permission installer/onboarding UX.
- Next: one separately bounded one-second timeout experiment. If it does not trigger a genuine timeout, investigate the trigger before another VM cycle. Do not increase delays repeatedly or accept a timer as an OS timeout.

## Current implementation

Lab branch `experiment/reusable-guest-setup`, commit `76a407d40b5dd36c488ef6b0b43b2ca07df19dfc`, contains the reviewed SDK CREATE integration. Source integration checks passed 11/11 on Python 3.9 and 3.14; native setup-script/SDK join passed 7/7. The committed route still needs its first fresh live trial.

Signed product experiment: `experiment/tap-timeout-hook`, commit `d9fcf9785ee3e544be800982068141271cb24901`. No new product build is required for the one-second test. Keep the existing signed artifact and experimental worktrees.

One-second runtime source `/private/tmp/keypath-physical-timeout-1000ms-d9fc-candidate`, manifest `081868bfcd6141364d6cceadf74df90fd38a74845f28a8b622af945098fa2858`: root 130 tests and independent source review passed. Fresh configuration support `/private/tmp/keypath-timeout-1000ms-config-candidate`, manifest `c25da4d5710e0f7523c712a91a342ec5479b98ded63bfbd3e769c93a2ee2bec7`, passes five root inert admission checks; fresh generated configuration still requires root inspection before release. Existing staging dependencies independently passed; only the root runner needs the two current canonical pins. No successor staging packet or maintained CREATE wrapper is needed. Neither is live authorization; fresh identity, installation/consent checks, timing, scope and hardware gate are mandatory.

Current canonical CLI SHA256 `f8470518428f75590e7ea6f481a6a544f40745f4a881039b9d4ed884231cdc03`; remote SHA256 `9e5b849322f5beffe2513f69c9ace8a4dfbe1d8d6c3cd3877a2d804186a33a24`. Frozen older packet pins remain historical. Bind fresh caller configuration to current bytes; never modify historical receipts or replay spent claims.

Latest trial evidence: `/private/tmp/keypath-timeout-d9fc-qualified-fresh`. Qualification evidence: `/private/tmp/keypath-reliability-d9fc-sdk-run2` and `/private/tmp/keypath-reliability-d9fc-sdk-run3`. Detailed hashes and cleanup proofs remain there and in the archive.

## Restrictions

Never read or stage `evidence/auth-image.base64`. No host product installation, security/TCC changes, account/reboot changes, firmware updates, permanent USB binding, PR merge, or outbound messages. Original QA501 account is metadata-only; use only the disposable public UID502 account. No TCC database modification, SIP changes, NOPASSWD, or host permission bypasses. Driverless retains app Accessibility and Input Monitoring; password/Secure Input limits are accepted. Revisit onboarding after permission/runtime work.
