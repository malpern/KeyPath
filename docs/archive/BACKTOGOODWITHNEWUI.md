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

Status: Done.

Completed subset:
- Wizard Helper page:
  Login Items approval UX improvements,
  plus diagnostics logging.
- Wizard Karabiner page:
  prevent “stuck” UI when Karabiner becomes healthy,
  add readiness transition logs.
- Settings → Status:
  click-through to wizard pages (sheet caching fix via `sheet(item:)`).

Notes:
- Blocked-by-fix state is now shown inline,
  and queued fixes auto-resume when the prior fix completes.
- Queued fix waits are canceled on navigation,
  and time out to actionable messaging rather than spinning forever.

Implementation plan:
- See `docs/FIXWIZARD.md`.

## Block 3: Settings / Status Consistency Polish

Status: Done.

Scope:
- Ensure Settings → Status, Settings → Status details, and wizard summary all agree on red/yellow/green.
- Improve diagnostics affordances: one-click access to relevant logs and system panes.
- Reduce “false green” states outside the wizard.

Outcome:
- Aligned all wizard/Settings status rows through the new `IssueSeverityInstallationStatusMapper`, so every status view shares a single canonical red/yellow/green determination without touching InstallerEngine or permission plumbing.
- Added `SystemDiagnostics` helpers so each detail card exposes multi-action links to login items, accessibility/input monitoring panes, and Kanata/Karabiner logs directly from Settings.
- Hardened the Kanata configuration generator (safety comments, output-trimming before aliasing, alias sanitization) and kept keyboard-visualizer tests stable with a zero hold-clear grace in test mode; the Block 3-focused tests pass (`swift test` exit 0).

Safety notes:
- Do not change permission checks or service launch model.
- Prefer incremental UI changes backed by snapshot-based evaluators.

## Block 4: Keyboard Visualizer + Mapping UX

Status: Done.

Scope:
- Restore non-wizard UI improvements that were worked on during the "wizard was working" period,
  including keyboard visualizer enhancements.

Outcome:
- All visualizer features already integrated and working:
  - MapperView: Experimental visual key mapping page with keycap-based input/output capture
  - Overlay: Live keyboard visualization with hold label detection (Hyper, Meh)
  - LayerKeyMapper: Simulator-based key mapping with proper symbol rendering
  - Multi-keyboard layout support (MacBook + Kinesis 360)
  - Smooth key fade-out animation: Released keys transition from blue to black over 0.25s using color interpolation
    - Per-key fade tracking with `keyFadeAmounts` dictionary
    - Color blending (blue→black) instead of opacity for clean visual transitions
    - Distinguished from global overlay fade via `isReleaseFading` flag
- Test coverage: 15 tests passing (LayerKeyMapper, Overlay hold labels, KeyboardVisualization)
- No TODOs or FIXMEs found in visualizer code
- Build successful, app deployed and running
- Released as v1.0.0-beta3

Strategy:
- Verified all features compile and run correctly
- Ran existing test suite - all 15 visualizer tests passing
- Reviewed code for issues - none found
- Manual testing confirms features work as expected

## Block 5: Other Product Features (Low Risk, Independent)

Status: Done.

Scope:
- Low-risk, independent features that don't affect service lifecycle or permissions.
- Focus on keyboard visualization enhancements and config output quality.

Outcome:
- **Key Emphasis via push-msg (ADR-024 partial)**:
  - Fully implemented emphasis feature: `(push-msg "emphasis:h,j,k,l")`
  - Merges custom emphasis with auto-emphasis (HJKL on nav layer)
  - Clears via `(push-msg "emphasis:clear")` or automatic on layer change
  - Visual treatment: Orange background for emphasized keys
  - Infrastructure: `.kanataMessagePush` notification, KeyboardVisualizationViewModel integration
- **Icon Registry Infrastructure (ADR-024 partial)**:
  - KeyIconRegistry with 50+ icon mappings (SF Symbols + app icons)
  - Design challenge documented: icon messages lack key context
  - Display logic deferred to v1.0.0-beta5 (see CLAUDE.md ADR-024 for solutions)
- **Physical Keyboard Layout Config Output**:
  - Already implemented via KeyboardGridFormatter (discovered during Block 5)
  - Configs formatted as physical keyboard rows with column alignment
  - Improves readability for advanced users who hand-edit configs
- Released as v1.0.0-beta4

Notes:
- Emphasis feature ready for production use
- Icon display deferred (infrastructure complete, rendering TBD)
- Physical layout was already working (documentation updated)

## Verification Checklist (Every Block)

- Wizard can complete without getting stuck.
- Fix buttons never become permanent spinners.
- Status indicators do not show green when the system is unhealthy.
- Settings → Status navigation opens the correct wizard page.
- Real mapping works:
  `1 → 2` outputs `2` when typing `1`.
