# Test Improvement Plan

*Created: 2026-05-27*

This plan brings KeyPath's test suite from its current state (~3,615 tests, uneven coverage) to comprehensive coverage across all critical paths. It's written for an agent or developer who may not have prior context on the codebase.

## Current State Summary

**What's strong:** CLI (133 tests/1K lines), Packs (108 tests/1K lines), RuleCollections (98 tests/1K lines), Config Generation (~250 tests), Models (~587 tests). Infrastructure layer is at 87% file coverage.

**What's weak:**

| Area | Source Files | Test Files | Key Problem |
|------|-------------|------------|-------------|
| UI views | 337 | 34 | 10% coverage — snapshot-only, no state/logic tests |
| Utilities | 13 | 1 | 92% untested — admin commands, TCP probe, restart, notifications |
| Core | 25 | 7 | 72% untested — DI container, deep link routing, composition root |
| Managers | 11 | 4 | 64% untested — ConfigReload, Recovery, Installation coordinators |
| Services (configuration) | — | — | 24 tests/1K lines — save pipeline, rollback, error paths |

**Ghost tests:** ~10 files totaling 3,000+ lines that have zero or near-zero assertions. They verify data structures exist or round-trip, not that features work. These inflate test counts while catching nothing.

## Architecture Context

KeyPath is an SPM-only macOS app (no Xcode project). XCUITest is not viable.

**Test targets** (defined in `Package.swift`):
- `KeyPathTests` — main target, depends on all source modules
- `KeyPathSnapshotTests` — UI visual regression, depends on `swift-snapshot-testing`
- `KeyPathLayoutTracerTests` — keyboard layout parsing

**Test base classes:**
- `KeyPathTestCase` — `@MainActor` sync, mocks PID providers, resets singletons in teardown
- `KeyPathAsyncTestCase` — async variant with `setUp() async throws`

**Available test doubles:**
- `MockSystemEnvironment` — file system, process state, kanata manager
- `SystemContextBuilder` — builder pattern for `SystemContext` fixtures
- Feature flag toggles and callback injection on `ActionDispatcher`

**Conventions:**
- New tests should use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`) — not XCTest
- Tests must stay under 5s total runtime
- No real `pgrep` in tests (deadlocks) — use `KeyPathTestCase` base class
- No `SMAppService.status` in tests (blocks 10-30s)
- Golden file tests go in `Tests/KeyPathTests/Integration/GoldenConfigs/`
- Snapshot tests require `KEYPATH_SNAPSHOTS=1` env var

---

## Phase 1: Fix Ghost Tests

**Goal:** Every test file should assert behavior, not just compilation. Eliminate false confidence before adding new tests.

**Estimated effort:** 2-3 sessions

### 1.1 Audit and fix zero-assertion test files

These files have test methods but no meaningful assertions:

| File | Lines | Problem |
|------|-------|---------|
| `QMKLayoutParserTests` | 908 | Parses JSON, checks structure — never verifies downstream effect |
| `MappingBehaviorTests` | 484 | Codec round-trips only — no behavioral assertions |
| `MainAppStateControllerTests` | 314 | Calls async methods, doesn't verify results |
| `OverlayHJKLRegressionTests` | 193 | Named for regression, doesn't test it |
| `ViewModelSyncTests` | 121 | Property access only |
| `OutputActionGroupingTests` | 231 | Structure tests, no behavior |
| `WindowManagerTests` | 229 | Sanity checks only |

**For each file:**
1. Read the source code it's supposed to test
2. Identify the 3-5 most important behaviors of that code
3. Replace or augment with tests that assert those behaviors
4. If a file tests pure data structures with no behavior, either add behavioral tests or delete the file and note why

### 1.2 Fix thin-assertion test files

Files with only 1-2 assertions that should have more:

- `ConfigFileWatcherTests` (1 assertion) — add tests for change detection, debouncing, error handling
- `OverlayKeyboardLayoutTests` (1 assertion) — add layout calculation edge cases
- `RuleCollectionCollisionTests` (2 assertions) — expand collision detection scenarios
- `CommandPaletteCoverageTests` (2 assertions) — test command execution, not just registration
- `PermissionOracleFastModeTests` (32 lines) — expand oracle behavior coverage
- `SingleInstanceCoordinatorTests` (2 assertions) — test lock acquisition, contention, cleanup

---

## Phase 2: Untested Coordinators (Critical Runtime Paths)

**Goal:** Cover the coordinators that orchestrate KeyPath's core operations. These are the highest-risk untested code — failures here mean config changes don't apply, recovery doesn't work, or installation breaks.

**Estimated effort:** 3-4 sessions

### 2.1 ConfigReloadCoordinator

**Location:** `Sources/KeyPathAppKit/Managers/ConfigReloadCoordinator.swift` (~200 lines)

**Why critical:** This is the TCP reload path. When a user changes a rule, this coordinator tells the running kanata process to reload. If it fails silently, the user sees no error but their change doesn't take effect.

**Tests to write:**
- Successful reload path: config change -> TCP send -> confirmation
- TCP connection failure: kanata not running -> appropriate error/recovery
- Cooldown enforcement: rapid successive reloads are debounced (the 3s cooldown has caused bugs twice — see `docs/testing/rule-collection-coverage-gaps.md` section 5)
- Timeout handling: kanata responds slowly

**Mock strategy:** Mock the TCP client (it's a protocol). Don't mock ConfigReloadCoordinator itself.

### 2.2 RecoveryCoordinator

**Location:** `Sources/KeyPathAppKit/Managers/RecoveryCoordinator.swift` (~300 lines)

**Why critical:** Handles error recovery — if kanata crashes, permissions change, or the daemon dies. Untested recovery means users get stuck in broken states.

**Tests to write:**
- Each recovery scenario: kanata crash recovery, permission loss recovery, daemon restart
- Recovery ordering: does it try the cheapest fix first?
- Cascading failure: recovery itself fails -> user notification
- Idempotency: calling recovery when already healthy is a no-op

### 2.3 InstallationCoordinator

**Location:** `Sources/KeyPathAppKit/Managers/InstallationCoordinator.swift` (~250 lines)

**Why critical:** Orchestrates the installation wizard flow. The installation engine (`InstallerEngine`) has tests, but the coordinator that drives it does not.

**Tests to write:**
- Happy path: fresh install, all permissions granted
- Permission denied mid-flow: user declines accessibility/input monitoring
- Partial install state: helper installed but daemon not running
- Repair flow: detect degraded state -> trigger repair

### 2.4 RuleCollectionsCoordinator

**Location:** `Sources/KeyPathAppKit/Managers/RuleCollectionsCoordinator.swift` (~300 lines)

**Why critical:** Synchronizes rule state across the app — collection enable/disable, custom rule changes, and config regeneration.

**Tests to write:**
- Enable/disable collection -> config regenerated -> reload triggered
- Custom rule CRUD -> state consistent across manager and store
- Conflict detection during enable: enabling collection A conflicts with collection B
- Error during save: verify rollback behavior

### 2.5 RuntimeCoordinator extensions

`RuntimeCoordinator` itself has 82 lines of tests plus a separate reset test file. The `RuntimeCoordinator+RuleCollections` extension (5.7 KB) has zero tests.

**Tests to write:**
- Rule collection operations routed through RuntimeCoordinator
- State consistency after rule changes propagate through the coordinator chain

---

## Phase 3: Untested Utilities and Core

**Goal:** Cover the foundational utilities and core wiring that every feature depends on.

**Estimated effort:** 2-3 sessions

### 3.1 Utilities (12 of 13 files untested)

Prioritize by blast radius:

**High priority:**
- `AdminCommandExecutor` — executes privileged operations. Test: command construction, error handling, timeout. Mock: actual execution.
- `TCPProbe` — checks if kanata is responding. Test: connect/timeout/refuse scenarios. Mock: socket layer.
- `NotificationObserverManager` — manages distributed notification subscriptions. Test: add/remove observers, cleanup on deinit.
- `DependencyInjection` — DI container. Test: registration, resolution, missing dependency error.

**Medium priority:**
- `KeyDisplayFormatter` — formats key names for display. Test: special keys, modifiers, edge cases (empty input, unknown keys). Pure function — easy to test.
- `BuildInfo` — returns build metadata. Test: version string format, build number.
- `SignatureHealthCheck` — verifies code signing. Test with mock signing state.

**Low priority (side-effect heavy, mock-heavy):**
- `AppRestarter` — restarts the app. Test: verify it calls the right API. Mock: NSWorkspace.
- `SoundManager` / `SoundPlayer` — audio playback. Test: mute in test mode, correct sound selection.
- `OneShotProbeEnvironment` — one-time system probe. Test: probe runs once, caches result.

### 3.2 Core (18 of 25 files untested)

**High priority:**
- `ServiceContainer` — the DI container. Test: registration, resolution, lifecycle (singleton vs transient), thread safety.
- `DeepLinkRouter` — routes `keypath://` URLs. Test: all known routes parse correctly, unknown routes return error, malformed URLs handled.
- `CompositionRoot` — assembles the dependency graph. Test: all required services resolve, no missing dependencies at startup.
- `DistributedNotificationBridge` — bridges system notifications. Test: notification posting and observation (mock NotificationCenter).

**Medium priority:**
- `AppMenuCommands` — menu bar commands. Test: each command triggers the correct action.
- `AppNotificationWiring` — connects notification observers. Test: wiring is complete, no missing observers.
- `BlessDiagnostics` — SMAppService diagnostics. Test with mock SMAppService status.
- `PrivilegedOperationsRouter` — routes privileged operations. Test: routing logic (not actual privilege escalation).

---

## Phase 4: Services Layer Gaps

**Goal:** Fill the moderate gaps in the services layer, focusing on error paths and integration boundaries.

**Estimated effort:** 3-4 sessions

### 4.1 ConfigurationService save pipeline

Currently at 24 tests/1K lines — the lowest density of any major service. The `saveConfiguration` method validates, deduplicates, generates, and writes. Key untested paths:

- Rollback on validation failure in `toggleCollection`
- Rollback on write failure in `saveCustomRule`
- Concurrent save requests (race condition potential)
- The validate-before-write invariant: verify kanata --check runs before file write
- Deduplication edge cases: near-duplicate rules with minor differences

### 4.2 TCP client robustness

- Connection timeout handling and retry logic
- Partial reads (server sends incomplete response)
- Server-not-running scenarios (connection refused vs timeout)
- Concurrent reload requests during the cooldown window

### 4.3 KarabinerConflictService

Referenced in tests but has no dedicated suite. Test:
- Detection of conflicting Karabiner rules
- Conversion accuracy for complex Karabiner configs
- Error handling for malformed Karabiner JSON

### 4.4 DeviceRecognitionService and HIDDeviceMonitor

- Device detection for known keyboard models
- Hot-plug: device connected/disconnected events
- Multiple device handling
- Unknown device fallback behavior

### 4.5 Monitoring services

`Services/Monitoring/` has 16 source files. Test:
- Event listener registration and dispatch
- Health monitor state transitions
- Alert triggering thresholds

---

## Phase 5: UI View Model Testing

**Goal:** Test UI logic without rendering. SwiftUI views are hard to unit test, but ViewModels and state objects are not.

**Estimated effort:** 4-5 sessions

### 5.1 Identify testable view models

Scan `Sources/KeyPathAppKit/UI/` for `@Observable` classes, `ViewModel` suffixes, and state objects. These are the testing targets — not the SwiftUI views themselves.

**Known high-value targets:**
- `KanataViewModel` — the main UI state source. Test state transitions, derived properties.
- `MapperViewModel` — complex state machine for the key mapper UI. The `+ConflictResolution` extension alone is 968 lines.
- `KeyboardVisualizationViewModel` — translates physical layout + logical keymap into visual state.
- Any overlay view models — the overlay is 97 files; the view models drive significant logic.

### 5.2 Test state transitions, not rendering

For each view model:
1. Identify the public API (methods + published properties)
2. Map the state machine: what states exist, what transitions between them
3. Test: initial state, each transition, edge cases (rapid transitions, error states)
4. Test: derived properties compute correctly from underlying state

### 5.3 Expand scenario snapshot coverage

The existing snapshot infrastructure (`ScreenshotTestCase`) is solid. Add snapshots for:
- Gallery pack detail views with different picker selections
- Mapper keycap pairs with various output types (plain, Hyper, app launch, system action)
- Overlay keycaps showing tap-hold idle labels, hold activation, collection coloring
- Conflict resolution dialogs
- Settings panels in various states

See `docs/testing/testing-strategy.md` Layer 2 for the full list.

---

## Phase 6: Integration Tests

**Goal:** Test the full pipeline at critical integration boundaries where unit tests can't catch wiring bugs.

**Estimated effort:** 2-3 sessions

### 6.1 Pack install -> config -> reload -> overlay pipeline

The most important integration test. Exercise:
1. `PackInstaller.install(pack)` — installs a pack
2. Verify the generated `.kbd` file contains expected kanata syntax
3. Mock TCP reload — verify reload is triggered
4. Verify `LayerKeyMapper` updates with new mappings
5. Verify overlay labels reflect the new mappings

Mock only: TCP socket, file system (use temp directory). Let everything else run for real.

### 6.2 Rule collection combo fuzzer

Currently 3 hand-picked combos are tested. With 19 collections, there are 171 possible pairs. Write a parameterized test that:
1. Enables a random subset of collections (2-3 at a time)
2. Generates the config
3. Runs `kanata --check` against it
4. Verifies no grammar conflicts

Run ~50 random combos per test invocation. Tag as `@Test(.tags(.slow))` so it doesn't run in the default fast suite.

### 6.3 Runtime behavior tests

`kanata --check` validates syntax but not semantics. For each pack, assert the headline claim:
- Caps Lock Remap: tap -> escape, hold -> hyper
- Home Row Mods: `a` tap -> `a`, `a` hold -> `lctl`
- Backup Caps Lock: both shifts -> caps

Use kanata's simulated-input harness if available. See `docs/testing/rule-collection-coverage-gaps.md` section 3.

---

## Phase 7: Infrastructure and Tooling

**Goal:** Make coverage measurable and prevent regression.

**Estimated effort:** 1-2 sessions

### 7.1 Enable code coverage reporting

No coverage tooling is currently configured. Add:

```bash
swift test --enable-code-coverage
```

Then extract the `.xcresult` bundle for coverage data. Consider adding a script at `Scripts/test-coverage.sh` that:
1. Runs tests with coverage enabled
2. Extracts per-module and per-file coverage percentages
3. Prints a summary table
4. Optionally fails if coverage drops below a threshold

### 7.2 Standardize on Swift Testing

The suite is ~85% XCTest / ~15% Swift Testing. New tests should all use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`). Don't batch-convert existing tests — convert them when you're already modifying a test file.

### 7.3 SoundManager test isolation

`SoundManager` should no-op in test environments. Tests that trigger sound playback (pack install, error chimes) produce audible beeps. Add a `SoundManager.isTestEnvironment` check or inject a silent mock.

---

## Execution Order and Dependencies

```
Phase 1 (Ghost Tests)          <- No dependencies, start here
    |
Phase 2 (Coordinators)         <- May need new mocks from Phase 1 learnings
    |
Phase 3 (Utilities & Core)     <- Independent of Phase 2, can parallelize
    |
Phase 4 (Services Gaps)        <- Builds on mock patterns from Phase 2-3
    |
Phase 5 (UI View Models)       <- Independent, can start after Phase 1
    |
Phase 6 (Integration)          <- Needs Phases 2-4 complete (uses their mocks)
    |
Phase 7 (Tooling)              <- Start anytime, but most useful after Phase 4+
```

Phases 1, 3, 5, and 7 can run in parallel. Phases 2 and 4 are sequential (coordinators before service gaps). Phase 6 depends on having the mock infrastructure from earlier phases.

## Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Total tests | ~3,615 | ~5,000+ |
| Zero-assertion test files | ~10 | 0 |
| Coordinator test coverage | 36% | 90%+ |
| Utility test coverage | 7% | 70%+ |
| Core test coverage | 28% | 80%+ |
| UI view model test coverage | ~10% | 60%+ |
| Integration pipeline tests | 0 | 3+ end-to-end flows |
| Coverage reporting | None | Automated per-module report |

## Key References

- Existing testing strategy: `docs/testing/testing-strategy.md`
- Rule collection gaps: `docs/testing/rule-collection-coverage-gaps.md`
- Coverage report: `docs/TEST_COVERAGE_REPORT.md`
- Test base classes: `Tests/KeyPathTests/KeyPathTestCase.swift`
- Test doubles: grep for `MockSystemEnvironment`, `SystemContextBuilder` in Tests/
- Snapshot infrastructure: `Tests/KeyPathSnapshotTests/ScreenshotTestCase.swift`
- Anti-patterns: never call real `pgrep` in tests, never call `SMAppService.status`, keep total runtime <5s
