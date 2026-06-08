# KeyPath Testing Strategy

*Last updated: 2026-05-07*

## Overview

KeyPath's overlay, mapper, and gallery features are connected through notifications, shared state, and config file generation. Bugs are common at the boundaries — the same data takes different paths for display vs. saving, and a change in one system (pack install) must propagate through config generation, TCP reload, and overlay label rendering.

This document captures the testing strategy for ensuring reliability across these systems.

## Testing Layers

We use a layered approach, ordered from fastest/cheapest to slowest/most expensive:

### Layer 1: Unit Tests (current: ~2100+ XCTest + 413 swift-testing)

Pure logic and state machine tests. No UI rendering, no I/O.

**What's covered:**
- Label resolution: `LabelMetadata`, `effectiveLabel` priority chain, `tapHoldIdleLabels`
- Config generation: `KeyMappingFormatter` (KeySequence → kanata S-expressions)
- Mapper state: `canSave`, `isIdentityKeystrokeMapping`, shifted output blocking, multi-tap index mapping, conflict resolution (hold vs. tap-dance)
- Notification payloads: `outputKey` vs. `displayLabel` distinction in `.mapperDrawerKeySelected`
- Overlay: window sizing, frame persistence, inspector panel layout, health indicator state machine
- Gallery: pack registry integrity, pack↔collection mapping, configuration types
- System: validation ordering, permission oracle logic, service health

**Key test files for the overlay/mapper/gallery data flow:**
- `OverlayEffectiveLabelTests` — label priority: hold > tapHoldIdle > displayLabel > baseLabel
- `MapperNotificationPayloadTests` — outputKey (kanata name) vs. displayLabel (glyph) separation
- `TapHoldIdleLabelTests` — idle label population from enabled collections
- `MapperKanataFormatTests` — KeySequence→kanata conversion, modifiers, special keys
- `MapperMultiTapTests` — multi-tap index mapping, auto-expand/trim of tap-dance steps
- `MapperConflictAndSaveTests` — canSave logic, identity mapping, shifted output blocking, conflict state
- `PackCollectionIntegrationTests` — pack↔collection mapping integrity, config type validation

### Layer 2: Scenario Snapshot Tests (expanding)

Set up a ViewModel in a post-interaction state, render the SwiftUI view, compare against a reference image. No app launch needed — state-in, pixels-out.

**What to cover:**
- Gallery: pack detail view with different picker selections (tap-hold, single-key, home-row-mods)
- Mapper: keycap pair with various output types (plain key, Hyper, app launch, system action, URL)
- Overlay: keycaps with tap-hold idle labels, keycaps during hold activation, collection-colored keycaps
- Conflict dialogs: hold vs. tap-dance conflict resolution UI
- Post-install states: overlay after pack installation showing new labels

**Why snapshots over computer-use:** Deterministic, fast (~5s), free, CI-friendly. Computer-use is non-deterministic, slow (~30s per interaction), expensive (tokens), and not suitable for CI pipelines.

### Layer 3: Integration Tests (planned)

Exercise the full pipeline with real code but mocked system boundaries.

**Target flow:** Pack install → config generation → verify `.kbd` file content → mock TCP reload → verify layer key map update → verify overlay label.

**System boundaries to mock:**
- `SMAppService.status` (synchronous IPC, slow)
- `launchctl` / `pgrep` (process detection)
- `IOHIDCheckAccess` (permission checks)
- TCP connection to kanata (use mock server)

**What NOT to mock:** Config file generation, `RuleCollectionsManager`, `LayerKeyMapper` simulator, `KeyboardVisualizationViewModel` state updates.

### Layer 4: XCUITest Smoke Tests (not viable for SPM)

XCUITest requires a native Xcode project with test host/target relationships.
KeyPath is an SPM-only project — `XCUIApplication(bundleIdentifier:)` cannot
discover windows from an SPM-built app because the test runner lacks the
`TEST_HOST`/`BUNDLE_LOADER` configuration that Xcode projects provide.
`swift package generate-xcodeproj` was removed in Swift 6.

**Verdict:** Skip XCUITest. The combination of unit tests, scenario snapshots,
integration tests, and computer-use spot-checks provides equivalent coverage
without the overhead of maintaining a parallel Xcode project.

If Apple adds SPM support for UI test targets in a future Xcode release, revisit.

### Layer 5: Manual Verification (ad-hoc)

For behaviors that can't be automated: real key events through the CGEvent tap, permission dialog flows, LaunchDaemon lifecycle on real hardware.

Use Claude Code computer-use or Peekaboo for spot-checking specific bugs — not as a test harness.

For Home Row Mods release QA, use the focused checklist and installed-app smoke
script in [hrm-settings-release-qa.md](hrm-settings-release-qa.md).

## Anti-Patterns

- **Don't use computer-use as a test harness.** It's for debugging and spot-checks, not reproducible test suites. It's non-deterministic, expensive, and can't run in CI.
- **Don't mock everything.** The bugs we find are at integration boundaries — mock only the system boundary (launchctl, SMAppService, IOHIDCheckAccess), let everything above run for real.
- **Don't write shallow smoke tests.** "Gallery opens" is not a useful test. "Installing Caps Lock Remapper with Escape tap / Hyper hold produces correct overlay labels" is.
- **Don't test permissions with real APIs in unit tests.** `PermissionOracle` logic is unit-testable; actual TCC state is not.

## Immediate Next Steps

1. **Scenario snapshots** — Add snapshot tests for post-interaction states: pack detail views with picker selections, mapper keycap pairs with different output types, overlay keycaps with tap-hold idle labels
2. **End-to-end integration test** — One test that exercises pack install → config generation → label map verification
3. **Accessibility identifiers** — Add to gallery pack cards, mapper drawer, overlay keycaps using dotted naming convention
4. **Document manual test cases** — For the ~20 flows that require real key events or permission dialogs, write structured test cases (preconditions, steps, expected result) in `docs/testing/manual-tests.md`

## Tools

| Tool | Purpose | Status |
|------|---------|--------|
| XCTest / Swift Testing | Unit and integration tests | Active (~2500+ tests) |
| swift-snapshot-testing | Visual regression | Active (easy/medium/hard tiers) |
| XCUITest | UI automation | Not viable (SPM-only, no Xcode project) |
| Peekaboo | Ad-hoc AI-driven UI verification | Available (not in CI) |
| Computer-use MCP | Spot-check debugging | Available (not for test suites) |
