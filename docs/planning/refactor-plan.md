# KeyPath Refactoring Plan

**Created:** 2026-03-11
**Status:** Planning — nothing started yet

This document tracks architectural and code quality issues identified during a comprehensive codebase review. Items are prioritized by impact on maintainability, testability, and developer experience.

---

## P0 — Critical (Architectural)

### 1. Singleton Explosion (~80 `static let shared` instances)

**Problem:** Nearly every service, manager, and controller is a singleton accessed via `.shared`. This creates hidden dependencies, makes unit testing difficult, and tightly couples unrelated modules.

**Key offenders (sample):**
- `ActionDispatcher.shared`, `MainAppStateController.shared`, `WindowManager.shared`
- `ServiceBootstrapper.shared`, `ServiceHealthChecker.shared`, `PrivilegedExecutor.shared`
- `ConfigHotReloadService.shared`, `PermissionGate.shared`, `OrphanDetector.shared`
- `LiveKeyboardOverlayController.shared`, `ContextHUDController.shared`
- Full list: ~80 instances across `Sources/`

**Plan:**
- [ ] Design a composition root / DI container (extend the pattern already started in `App.init()`)
- [ ] Identify the dependency graph between singletons
- [ ] Migrate leaf services first (no downstream singleton deps), then work inward
- [ ] Add protocol abstractions where needed for testability
- [ ] Phase: do incrementally, module by module

---

### 2. `App.swift` — 1,530 lines (god file)

**Problem:** The SwiftUI `App` entry point contains app lifecycle, scene management, deep link handling, notification setup, and initialization logic. Should be a thin routing layer.

**File:** `Sources/KeyPathAppKit/App.swift`

**Plan:**
- [ ] Extract `CompositionRoot` — service initialization and wiring
- [ ] Extract `DeepLinkRouter` — URL handling
- [ ] Extract `SceneConfiguration` — window/scene setup
- [ ] Extract `AppLifecycleHandler` — lifecycle callbacks
- [ ] Keep `App.swift` under ~100 lines

---

### 3. `KeyPathAppKit` is 91% of the codebase (570 / 624 files)

**Problem:** One monolithic library target defeats modular architecture. Build times, code navigation, and separation of concerns all suffer.

**Plan:**
- [ ] Identify natural module boundaries (installer, overlay, rule engine, services)
- [ ] Extract `KeyPathInstaller` — wizard, bootstrapper, health checker, engine
- [ ] Extract `KeyPathOverlay` — overlay controller, views, keycap rendering
- [ ] Extract `KeyPathRuleEngine` — rule collections, conflict analysis, config generation
- [ ] Extract `KeyPathServices` — TCP client, event listener, action dispatch
- [ ] Keep `KeyPathAppKit` as the thin app-layer glue
- [ ] Phase: one module at a time, start with the most self-contained (Installer)

---

## P1 — High (Large Files Needing Decomposition)

### 4. Files over 1,000 lines

| File | Lines | Decomposition Strategy |
|------|-------|----------------------|
| `HelperService.swift` | 1,498 | Split by operation category (service mgmt, VHID, kanata, cleanup) |
| `ActionDispatcher.swift` | 1,345 | Replace giant dispatch with handler registry pattern |
| `PrivilegedOperationsCoordinator.swift` | 1,332 | Extract per-domain coordinators (VHID, Kanata, Helper) |
| `LiveKeyboardOverlayController.swift` | 1,299 | Extract window management, inspector panel, state machine |
| `WizardDesignSystem.swift` | 1,245 | Split tokens vs. components vs. animations |
| `RulesSummaryView.swift` | 1,061 | Extract section views, search, recommended rules |
| `RuntimeCoordinator.swift` | 1,056 | Already has extensions — needs real type decomposition |
| `RuleCollectionCatalog.swift` | 1,015 | Make data-driven (JSON catalog + loader) |
| `ServiceBootstrapper.swift` | 988 | Extract validation, installation, and recovery phases |
| `LiveKeyboardOverlayView.swift` | 986 | Extract inspector panel, header, keyboard sections |
| `KarabinerConverterService.swift` | 976 | Could be its own module — discrete import domain |
| `ConfigurationService.swift` | 963 | Split read/write/validation/migration into separate types |
| `KanataEventListener.swift` | 951 | Extract event parsing, routing, and state tracking |

**Guideline:** No file should exceed ~500 lines. Prefer extracting new types over extension files.

---

### 5. `PhysicalLayout+Builtins.swift` — 1,427 lines of hardcoded data

**Problem:** Static keyboard geometry is embedded as Swift literals. Hard to maintain, impossible for users to extend.

**File:** `Sources/KeyPathAppKit/Models/PhysicalLayout+Builtins.swift`

**Plan:**
- [ ] Move layout data to JSON resource files
- [ ] Add a `PhysicalLayoutLoader` that decodes at runtime
- [ ] Enables future user-contributed layouts without code changes

---

## P2 — Medium (Patterns & Best Practices)

### 6. Mixed Combine + @Observable

**Problem:** The project has mostly adopted `@Observable` but retains Combine artifacts in ~8 files.

**Specific issues:**
- `WizardToastManager.swift` — conforms to **both** `@Observable` AND `ObservableObject` (line 10)
- `MainAppStateController.swift` — imports Combine, uses `AnyCancellable` alongside `@Observable`
- `OverlayHealthIndicatorObserver.swift` — Combine publishers + async/await mixed
- Several files still use `@Published` or `PassthroughSubject`

**Plan:**
- [ ] Audit all `import Combine` in Sources/
- [ ] Remove `ObservableObject` conformance from `WizardToastManager`
- [ ] Replace `AnyCancellable` patterns with `@Observable` + async sequences
- [ ] Keep Combine only where genuinely needed (e.g., bridging to AppKit APIs)

---

### 7. AnyView usage (7 instances)

**Problem:** Type-erased views hurt SwiftUI diffing performance.

**Locations:**
- `LiveKeyboardOverlayController.swift:1277` — in `buildRootView()` (called frequently)
- `WizardWindowController.swift:48,56` — conditional environment injection
- `LiveKeyboardOverlayView.swift:929` — inspector panel builder
- `HomeRowModsCollectionView.swift:138`
- `OverlayMapperSection+ShiftOutput.swift:46`

**Plan:**
- [ ] Replace with `@ViewBuilder`, generics, or concrete view types
- [ ] Priority: overlay controller (performance-sensitive path)

---

### 8. Duplicate `FeatureFlags` types

**Problem:** Two separate files define `FeatureFlags`:
- `Sources/KeyPathCore/FeatureFlags.swift`
- `Sources/KeyPathAppKit/Utilities/FeatureFlags.swift`

**Plan:**
- [ ] Audit which is used where
- [ ] Consolidate into one canonical location (likely `KeyPathCore`)

---

## P3 — Low-Medium (Organization)

### 9. Flat `UI/` directory (281 files)

**Problem:** Many views sit at the `UI/` root with no subdirectory. Hard to navigate.

**Existing subdirs:** `Overlay/`, `Rules/`, `Help/`, `Experimental/`, `Settings/`, `Simulator/`, `ContextHUD/`, `KeyboardVisualization/`, `Components/`, `Dialogs/`, `Status/`, `Style/`, `ViewModels/`

**Orphaned at root (sample):** `AboutView.swift`, `SimpleModsView.swift`, `FunctionKeysView.swift`, `KarabinerImportSheet.swift`, `AnimatedKeyboardTransformGrid.swift`, `EmergencyStopDialog.swift`, `AIKeyRequiredDialog.swift`

**Plan:**
- [ ] Group by feature: `About/`, `Modifiers/`, `Import/`, etc.
- [ ] Move dialog views into `Dialogs/`
- [ ] Move remaining settings views into `Settings/`

---

### 10. `Services/` directory is a grab bag (109 files)

**Problem:** Everything from TCP clients to favicon fetchers to browser history scanners lives in one flat directory.

**Plan:**
- [ ] Create subdirectories: `Networking/`, `Configuration/`, `System/`, `AI/` (already exists), `Import/`, `Audio/`, `Monitoring/`
- [ ] Move files into appropriate subdirectories

---

### 11. Extension-file proliferation on `RuntimeCoordinator`

**Problem:** Files like `RuntimeCoordinator+ServiceManagement.swift`, `+Lifecycle.swift`, `+Configuration.swift`, `+State.swift` suggest the class needs type decomposition, not just file splits.

**Plan:**
- [ ] Identify distinct responsibilities
- [ ] Extract into focused types (e.g., `ServiceLifecycleManager`, `ConfigurationReloader`)
- [ ] `RuntimeCoordinator` becomes a thin orchestrator delegating to these types

---

### 12. `KanataKanataLauncher/main.swift` — 682 lines

**Problem:** Executable entry points should be minimal. Complex process management is inline.

**Plan:**
- [ ] Extract process management into a `LauncherService` type
- [ ] Keep `main.swift` as a thin entry point

---

## Tracking

When work begins on an item, update status here:

| # | Item | Status | PR |
|---|------|--------|----|
| 1 | Singleton reduction / DI | Not started | — |
| 2 | App.swift decomposition | Not started | — |
| 3 | KeyPathAppKit modularization | Not started | — |
| 4 | Large file decomposition | Not started | — |
| 5 | Layout data → JSON | Not started | — |
| 6 | Combine → @Observable | Not started | — |
| 7 | AnyView removal | Not started | — |
| 8 | Duplicate FeatureFlags | Not started | — |
| 9 | UI/ directory cleanup | Not started | — |
| 10 | Services/ directory cleanup | Not started | — |
| 11 | RuntimeCoordinator decomposition | Not started | — |
| 12 | Launcher main.swift cleanup | Not started | — |
