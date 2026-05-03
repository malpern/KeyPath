# KeyPath Refactoring Plan

**Created:** 2026-03-11
**Updated:** 2026-03-12
**Status:** 10 of 12 items complete

This document tracks architectural and code quality issues identified during a comprehensive codebase review. Items are prioritized by impact on maintainability, testability, and developer experience.

---

## Tracking

| # | Item | Priority | Status | PR |
|---|------|----------|--------|----|
| 1 | Singleton reduction / DI | P0 | **Done** | #232 |
| 2 | App.swift decomposition | P0 | **Done** | #242 |
| 3 | KeyPathAppKit modularization | P0 | Open | — |
| 4 | Large file decomposition | P1 | Open | — |
| 5 | Layout data → JSON | P1 | **Done** | #240 |
| 6 | Combine → @Observable | P2 | **Done** | #236 |
| 7 | AnyView removal | P2 | **Done** | #235 |
| 8 | Duplicate FeatureFlags | P2 | **Done** | #234 |
| 9 | UI/ directory cleanup | P3 | **Done** | #237 |
| 10 | Services/ directory cleanup | P3 | **Done** | #238 |
| 11 | RuntimeCoordinator decomposition | P3 | **Done** | #241 |
| 12 | Launcher main.swift cleanup | P3 | **Done** | #239 |

---

## Completed Items

### 1. Singleton reduction / DI (PR #232)

Added `ServiceContainer` DI container and `EnvironmentValues` extensions for dependency injection. The composition root wires services in `App.init()`. Singletons still exist but can now be replaced with injected dependencies incrementally.

### 2. App.swift decomposition (PR #242)

Split 1,530-line `App.swift` into 6 focused files:
- `App.swift` — thin `KeyPathApp` struct (55 lines) + slimmed `AppDelegate`
- `Core/CompositionRoot.swift` — service initialization and wiring
- `Core/AppMenuCommands.swift` — SwiftUI `Commands` struct
- `Core/DeepLinkRouter.swift` — `keypath://` URL scheme dispatch
- `Core/OneShotProbeHandler.swift` — diagnostic probe modes
- `Core/AppNotificationWiring.swift` — notification observer registrations

### 5. Layout data → JSON (PR #240)

Extracted 5 MacBook keyboard layouts from 1,100 lines of procedural Swift into JSON resource files at `Resources/Keyboards/`. Created `PhysicalLayoutLoader` with Codable DTOs. `PhysicalLayout+Builtins.swift` reduced from 1,427 to 341 lines. Added `Scripts/generate-layout-json.swift` for regeneration.

### 6. Combine → @Observable (PR #236)

Removed redundant `ObservableObject` from `WizardToastManager`. Replaced `AnyCancellable` + Combine notification subscriptions with async `NotificationCenter.notifications` in `MainAppStateController`, `MenuBarController`, and `OverlayHealthIndicatorObserver`. Combine retained only where genuinely needed (SwiftUI `.onReceive`, `PassthroughSubject` for driver install progress).

### 7. AnyView removal (PR #235)

Replaced all 7 `AnyView` instances with concrete types, `@ViewBuilder`, and generics. Key changes: `LiveKeyboardOverlayController` now uses `NSHostingView<LiveKeyboardOverlayView>`, `HomeRowKeyboardView` became generic over popover content, `OverlayMapperSection+ShiftOutput` uses `@ViewBuilder` closure.

### 8. Duplicate FeatureFlags (PR #234)

Consolidated `KeyPathAppKit/Utilities/FeatureFlags.swift` into `KeyPathCore/FeatureFlags.swift`. All flags now `public` in `KeyPathCore`.

### 9. UI/ directory cleanup (PR #237)

Moved 73 files from `UI/` root into 9 subdirectories: `Vim/`, `WindowSnapping/`, `KeyboardTransforms/`, `Pickers/` (new), plus existing `Dialogs/`, `Settings/`, `Rules/`, `Components/`, `Overlay/`. ~10 top-level navigation entry points remain at root.

### 10. Services/ directory cleanup (PR #238)

Organized 88 files from `Services/` root into 15 subdirectories: `Audio/`, `Configuration/`, `Icons/`, `Import/`, `Kanata/`, `Karabiner/`, `KeyboardCapture/`, `LayerMapping/`, `Monitoring/`, `Networking/`, `Permissions/`, `RuleCollections/`, `SimpleMods/`, `System/`, `VimIntegration/`. 10 singleton files remain at root.

### 11. RuntimeCoordinator decomposition (PR #241)

Extracted two focused types from RuntimeCoordinator:
- `ServiceLifecycleCoordinator` — start/stop/restart, runtime status, split runtime evaluation
- `ConfigReloadCoordinator` — TCP reload, safety monitoring, permission gating

RuntimeCoordinator is now a thin orchestrator with forwarding methods.

### 12. Launcher main.swift cleanup (PR #239)

Extracted all process management into `LauncherService` struct. `main.swift` reduced from 682 to 4 lines.

---

## Open Items

### 3. KeyPathAppKit modularization

**Priority:** Low urgency — tackle when build times become painful or when onboarding contributors.

**Problem:** `KeyPathAppKit` contains 91% of the codebase (570+ files). One monolithic library target defeats modular architecture.

**Why it's not urgent:** The directory cleanup (#9, #10) provides 80% of the navigability benefit. SwiftPM handles incremental builds well. No compile-time wall yet.

**Plan (when ready):**
- [ ] Identify natural module boundaries (installer, overlay, rule engine, services)
- [ ] Extract `KeyPathInstaller` — wizard, bootstrapper, health checker, engine
- [ ] Extract `KeyPathOverlay` — overlay controller, views, keycap rendering
- [ ] Extract `KeyPathRuleEngine` — rule collections, conflict analysis, config generation
- [ ] Extract `KeyPathServices` — TCP client, event listener, action dispatch
- [ ] Keep `KeyPathAppKit` as the thin app-layer glue
- [ ] Phase: one module at a time, start with the most self-contained (Installer)

---

### 4. Large file decomposition

**Priority:** Medium — tackle opportunistically when already making changes to one of these files.

**Problem:** 13 files exceed 1,000 lines. They work fine but are harder to navigate and reason about.

**Recommended approach:** Don't do a dedicated decomposition pass. Instead, extract a focused type each time you're already touching one of these files.

**Highest-value targets:**

| File | Lines | Why it matters | Decomposition Strategy |
|------|-------|----------------|----------------------|
| `ActionDispatcher.swift` | 1,345 | Grows with every new action | Replace giant switch with handler registry pattern |
| `HelperService.swift` | ~1,380 | Many operation categories | Split by domain (service mgmt, VHID, cleanup) |
| `LiveKeyboardOverlayController.swift` | 1,299 | Performance-sensitive | Extract window management, inspector panel, state machine |

**Lower priority (functional but large):**

| File | Lines | Decomposition Strategy |
|------|-------|----------------------|
| `PrivilegedOperationsCoordinator.swift` | ~1,200 | Extract per-domain coordinators (VHID, Kanata, Helper) |
| `WizardDesignSystem.swift` | 1,245 | Split tokens vs. components vs. animations |
| `RulesSummaryView.swift` | 1,061 | Extract section views, search, recommended rules |
| `RuleCollectionCatalog.swift` | 1,015 | Make data-driven (JSON catalog + loader) |
| `ServiceBootstrapper.swift` | 988 | Extract validation, installation, and recovery phases |
| `LiveKeyboardOverlayView.swift` | 986 | Extract inspector panel, header, keyboard sections |
| `KarabinerConverterService.swift` | 976 | Could be its own module — discrete import domain |
| `ConfigurationService.swift` | 963 | Split read/write/validation/migration into separate types |
| `KanataEventListener.swift` | 951 | Extract event parsing, routing, and state tracking |

**Guideline:** No file should exceed ~500 lines. Prefer extracting new types over extension files.
