# Back To Good (With New UI)

This document records the feature blocks we used to recover KeyPath from a broken setup state
back to a working baseline,
and then incrementally reintroduce newer UI and wizard improvements
without regressing real keyboard capture.

It is intentionally historical.
Some blocks are already completed,
and remain here as a reference for future decisions.

## North Star

- Keep the working Kanata / VirtualHID / permissions model that reliably captures real key events.
- Avoid long detours into permission/launch architecture changes.
- Reintroduce UI and wizard improvements in small, testable blocks.
- After each block:
  verify the `1 → 2` mapping works end-to-end.

## Block 0: Back To Good Baseline

Status: Done.

Outcome:
- Reverted to a baseline where `1 → 2` mapping works reliably.
- Confirmed the user-visible symptoms were fixed:
  Kanata receives key events,
  and mappings apply correctly.

## Block 1: Shipping / Release UX (Sparkle + What’s New)

Status: Done.

Scope:
- Sparkle auto-update integration.
- “What’s New” dialog after update.
- Build/sign/notarize/staple/deploy pipeline support for Sparkle artifacts.

Notes:
- Fixed Sparkle framework packaging in the app bundle.
- Fixed feed URL and build-number scheme for Sparkle version comparison.
- Fixed Sparkle archive signing output so generated appcast entries are valid.

## Block 2: Wizard UX + Reliability Instrumentation

Status: Mostly done.

Completed subset:
- Wizard Helper page:
  Login Items approval UX improvements,
  plus diagnostics logging.
- Wizard Karabiner page:
  prevent “stuck” UI when Karabiner becomes healthy,
  add readiness transition logs.
- Settings → Status:
  click-through to wizard pages (sheet caching fix via `sheet(item:)`).

Remaining Block 2 work:
- “Fix” progress UX:
  show blocked-by dependency progress inline,
  per the design request.
- Robust single-flight behavior:
  eliminate “Fix already running” no-op toasts.
- Deterministic stuck detection and recovery:
  timeout → clear state → actionable messaging.
- Status aggregation correctness:
  page icon only green if all subtasks are green,
  consistent between wizard + Settings.
- Spacing/padding consistency for remaining wizard outliers.

Implementation plan:
- See `docs/FIXWIZARD.md`.

## Block 3: Settings / Status Consistency Polish

Status: Not started (planned).

Scope:
- Ensure Settings → Status,
  Settings → Status details,
  and wizard summary all agree on red/yellow/green.
- Improve diagnostics affordances:
  one-click access to relevant logs and system panes.
- Reduce “false green” states outside the wizard.

Safety notes:
- Do not change permission checks or service launch model.
- Prefer incremental UI changes backed by snapshot-based evaluators.

## Block 4: Keyboard Visualizer + Mapping UX

Status: Not started (planned).

Scope:
- Restore non-wizard UI improvements that were worked on during the “wizard was working” period,
  including keyboard visualizer enhancements.

Strategy:
- Cherry-pick in small batches.
- Avoid touching installer/wizard codepaths in this block.
- After each batch,
  verify `1 → 2` mapping and wizard setup remain stable.

## Block 5: Other Product Features (Low Risk, Independent)

Status: Not started (planned).

Examples:
- Rules / editor quality-of-life improvements.
- System action picker or other non-installer UI features,
  when they do not affect service lifecycle or permissions.

## Verification Checklist (Every Block)

- Wizard can complete without getting stuck.
- Fix buttons never become permanent spinners.
- Status indicators do not show green when the system is unhealthy.
- Settings → Status navigation opens the correct wizard page.
- Real mapping works:
  `1 → 2` outputs `2` when typing `1`.

