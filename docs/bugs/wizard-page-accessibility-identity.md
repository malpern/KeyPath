# Wizard page identifiers overriding child controls

Status: fixed; verified in a macOS 26 disposable VM on 2026-10-14.

The welcome page and shared detail-page modifier applied an accessibility
identifier to a transparent SwiftUI container. In the running app, that
identifier propagated to the children, replacing their own identifiers. The
welcome hero, heading, button and privacy text all appeared as
`wizard-welcome-page`. The permission page had the same defect.

This made identifier-based automation ambiguous. The strict lab helper refused
Get Started before dispatch; normal exact-label navigation still worked.

Both boundaries now use `accessibilityElement(children: .contain)` before
assigning their page identifier. Get Started also has its own explicit
`wizard-welcome-get-started` identifier. This preserves separate accessible
children rather than combining the whole page into one element.

Live verification on executable SHA256
`70cfb0cc395026c4d06edb75420c81aca7568e881a984d1ad9a958c493d3f371`:

- Welcome exposes distinct page, hero, title, button and privacy identifiers.
- The strict AX helper successfully presses Get Started.
- The permission page exposes `wizard-page-Accessibility` as a group and
  `wizard-accessibility-keypath-turn-on` as a separate button.
- 44 focused onboarding regression tests pass after the change.

Evidence: `~/keypath-review-evidence/20261014-onboarding-review/` on the mini.
These observations do not prove completion of consent, runtime startup, or the
tour; that run stopped during normal macOS authentication.

## Follow-up: first-success tour

The fresh macOS 26 live run on 2026-10-14 completed normal Accessibility consent
using the ESP32. The actual GUI-owned runtime started automatically, reported
`running` and `tapActive`, and the Metal tour appeared. Its root TimelineView
and action-bar container had the same identifier-propagation defect: all buttons
reported `first-success-onboarding-dialog`. Give both containers explicit
`.accessibilityElement(children: .contain)` boundaries.

The same live screenshot showed the tour action bar below the guest's visible
screen. Both the SwiftUI root and NSWindow required 650 points of content height.
The lesson already scrolls independently, so reduce that minimum to 520 and size
the initial window to the screen's visible content bounds. Keep the action bar
outside the scrolling lesson. Verify actual buttons on the small display after
rebuilding; a passing model test does not establish that they are visible.

## Live tour follow-up, 2026-10-14 evening

Normal Settings Accessibility consent passed in lease `cbx_5c08c77b98da` (public
UID502, boot `406287e2-fdf1-4c43-b740-0f61b74fa73f`). The ordinary GUI-owned
runtime started without a Start click. The four-step Metal tour appeared and
saved Escape tap, Hyper hold, and Hyper+F for Finder through the UI. The drawer
closed/reopened and recorded Q→A; the generated config and live reload confirmed it.

Two additional findings:
- A scrolled lesson retained its offset on the next step, clipping the new heading.
  Give each lesson scroll view a step identity, including the stacked layout.
- Recording one output created two rules (one disabled by conflict resolution).
  `finalizeCapture()` already saves output and shifted-output captures; the drawer
  also saved on their recording-flag changes. Remove those two redundant view
  saves; retain hold/double-tap saves, which have separate capture paths.

Physical acceptance is not yet a pass: the ESP32 completed one Q down/up pair,
with exact USB trace and attachment to this VM, but the foreground Jig recorded
zero events and the runtime counters did not advance. The attempt was retained
without replay. This is distinct from successful normal consent/calibration and
from UI/config save verification. Investigate after a normal runtime restart,
with independent raw-input control if still absent; do not call this production ready.

The no-output attempt was reconciled from the public-account log: a follow-up
click at 21:46:50 reopened output recording. At 21:48:07 KeyboardCapture consumed
the physical Q (`suppress=true`), then finalized it. This was test interference,
not evidence that the session runtime dropped input. The second click was meant
to refocus the faded overlay but actually rearmed capture. Before hardware runs,
finish/cancel recording and close the drawer (or normally restart the app), then
check the capture log. Keep the failed attempt; a fresh run after correcting the
precondition is a distinct test, never a replay of its uncertain input.


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
