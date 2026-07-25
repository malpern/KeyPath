# KeyPath automation progress log

This is the durable evidence log for the active KeyPath automation-lab work.
The attached Codex heartbeat reviews it every 20 minutes and appends a new
checkpoint while work is active.

## Progress standard

A checkpoint counts as **advanced** only when there is new, verifiable evidence:
a completed milestone, a changed test result, a newly isolated failure, or a
different bounded next step. Commands run, elapsed time, and repeated attempts
do not count by themselves.

A checkpoint is **looping** when the same blocker or materially identical
attempt repeats without new evidence. When that happens, stop repeating the
approach, record why it is exhausted, and choose a materially different safe
next step.

## 2026-07-24 22:09 PDT — baseline

- **Outcome:** advanced
- **Completed milestone:** The lab mini's Screen Sharing disconnect behavior was
  isolated as the cause of the unexpected host relock and disabled. The native
  Peekaboo lab-host launcher is installed in a fresh macOS 27 candidate.
- **Evidence:**
  - `keypath-lab-mini` is reachable over SSH.
  - `/Library/Preferences/com.apple.RemoteManagement RestoreMachineState` reads
    `0`.
  - `/usr/bin/caffeinate -d -i -m -s` is active on the mini.
  - Dashboard branch `codex/lab-state-dashboard` is clean at `a9af69657`.
  - Automation branch `codex/macos-27-desktop-base` is clean at `df51458b3`.
  - Candidate `cbx_adb383f1f5d2` reached a logged-in desktop after keychain reset
    and reboot; its native Peekaboo host launches, but Accessibility and Screen
    Recording remain unapproved.
  - The guest Sharing pane shows Screen Sharing enabled. The RFB automation
    probe reaches the guest but fails authentication, which confirms transport
    without proving control.
- **Current blocker:** Guest Remote Management is not yet enabled/configured, so
  we do not have an authenticated remote-control path for granting and testing
  the two guest permissions.
- **Next action:** Use the supported guest Sharing UI to replace Screen Sharing
  with Remote Management, then repeat the RFB probe. If it authenticates, use
  that path to grant and verify Peekaboo permissions. If it fails differently,
  record the exact new failure before choosing the next route.
- **Loop check:** not looping. The work moved from an unexplained host-lock
  failure to a verified host fix and a narrower guest-control gate.

## 2026-07-24 22:53 PDT — checkpoint 1

- **Outcome:** looping
- **Completed milestone:** Guest Screen Sharing was replaced with Remote
  Management through the supported System Settings UI. Remote Management and
  its VNC-password option are on, so the baseline blocker is cleared.
- **Evidence:**
  - Active lease `cbx_adb383f1f5d2` remains ready on macOS 27 resource
    `9b5c8578-3f31-46c1-bb29-c7b26d2cf691`.
  - The mini is reachable, `RestoreMachineState` remains `0`, and caffeinate is
    active.
  - The live Sharing pane shows Remote Management on.
  - CrabBox source confirms Parallels reads
    `/var/db/crabbox/vnc.password`; a secret-safe comparison proved that file
    exactly matches the current eight-character encrypted lab credential.
  - Three `secure-console-submit` attempts were recorded at 22:25, 22:27, and
    22:47 PDT, but RFB authentication did not change.
  - Parallels 26.4.0 accepts explicit JSON `press` and `release` events. The
    helper now emits one paced event batch and reports delivery separately from
    its unverified credential postcondition.
  - `bash Scripts/lab/tests/keypath-lab-tests.sh` passes, including the
    credential-leak and unsupported-character guards.
- **Current blocker:** The Remote Management UI password is not yet proven to
  equal the lease credential. RFB therefore still lacks an authenticated
  control path for the native Peekaboo host approvals.
- **Next action:** Do not repeat the old per-key helper. Have the user invoke
  the corrected batched helper while the VNC password field is focused, then
  make one RFB probe the postcondition. If that fails, inspect the resulting
  field length and RFB security negotiation rather than typing again.
- **Loop check:** looping was detected and stopped. Repeating the old helper
  produced transport-success messages without a changed RFB result; the
  materially different path is a tested single-batch press/release transport
  plus an independent RFB postcondition.
