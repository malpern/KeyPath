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
