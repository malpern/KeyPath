# Singleton Reduction & Dependency Injection — Implementation Plan

**Created:** 2026-03-11
**Parent:** [refactor-plan.md](refactor-plan.md) — P0 Item #1
**Status:** Planning

---

## Problem Statement

KeyPath has ~80 `static let shared` singletons. Views, services, and managers reach directly for `.shared` throughout the codebase. This makes unit testing nearly impossible (hidden dependencies), creates tight coupling, and makes it hard to reason about initialization order.

## Current State

**What already exists (and works):**
- `App.init()` manually creates `ConfigurationService` → `RuntimeCoordinator` → `KanataViewModel` (a composition root seed)
- `DependencyInjection.swift` defines two `EnvironmentKey`s: `permissionSnapshotProvider` and `preferencesService`
- `KanataViewModel` uses proper constructor injection (`init(manager: RuntimeCoordinator)`)
- `RuntimeCoordinator` accepts optional injected services (`injectedConfigurationService`, `engineClient`, `configRepairService`)
- Tests use `KeyPathTestCase` base class with static property overrides as test seams

**What doesn't work:**
- 93 of 261 UI files (36%) access `.shared` directly
- 60+ singletons have zero protocol abstractions
- `App.swift` itself references 25+ singletons
- Services reference other singletons internally (deep coupling)
- Tests can't substitute most dependencies

## Design Principles

1. **Incremental, not big-bang.** Every phase ships independently and leaves the app working.
2. **Extend existing patterns.** `DependencyInjection.swift` + `EnvironmentKey` + constructor injection are already in use — scale them.
3. **Don't touch AppLogger.** It's infrastructure-level logging used by ~95% of files. Injecting it everywhere adds noise for zero testability gain.
4. **Protocols only where testability demands it.** Don't add protocol abstractions to leaf services that have no side effects worth mocking.
5. **Environment for UI, constructor for services.** SwiftUI views get dependencies via `@Environment`. Services/managers get them via `init`.

---

## Singleton Tiers

Based on dependency analysis, singletons fall into four tiers:

### Tier 1 — Infrastructure (leave alone)
Pervasive, stateless, or too fundamental to inject:
- `AppLogger.shared` — referenced by ~95% of files
- `FeatureFlags.shared` (KeyPathCore) — read-only feature gates
- `SubprocessRunner.shared` — thin Process wrapper

### Tier 2 — Leaf services (easy wins, 1-2 consumers)
Low coupling, few references, trivial to pass via init or environment:
- `UpdateService` (2 files), `UserNotificationService` (2), `GlobalHotkeyService` (2)
- `TypingSoundsManager` (2), `QMKKeyboardDatabase` (2), `APIKeyValidator` (2)
- `BrowserHistoryScanner` (1), `KindaVimStateAdapter` (1), `FeatureTipManager` (1)
- `SimulatorWindowController` (1), `TooltipWindowController` (1)
- ~12 singletons referenced from only 1 file

### Tier 3 — Mid-tier services (moderate effort)
Used by 4-10 files, often by both views and services:
- `HelperManager` (14 files), `KanataDaemonManager` (12), `KanataSplitRuntimeHostService` (11)
- `AppContextService` (10), `FaviconFetcher` (9), `IconResolverService` (9)
- `WindowManager` (7), `ServiceHealthChecker` (6), `MainAppStateController` (5)

### Tier 4 — Hub services (high effort, high reward)
Used by 12+ files, deeply wired into the app:
- `PreferencesService` (26 files — #1 most referenced)
- `AppKeymapStore` (14 files), `RuleCollectionStore` (12 files)
- `LiveKeyboardOverlayController` (8 files — UI coordinator singleton)

---

## Implementation Phases

### Phase 0: Service Container + Protocols for Top Services
**Goal:** Create the container and wire the 5 most impactful services through it.
**Effort:** ~2 sessions

#### 0a. Create `ServiceContainer`

Create `Sources/KeyPathAppKit/Core/ServiceContainer.swift`:

```swift
/// Central service container created once in App.init() and passed down.
/// NOT a singleton — instantiated explicitly and injected.
@MainActor
@Observable
final class ServiceContainer {
    let preferences: PreferencesService
    let appKeymapStore: AppKeymapStore
    let ruleCollectionStore: RuleCollectionStore
    let iconResolver: IconResolverService
    let faviconFetcher: FaviconFetcher

    init(
        preferences: PreferencesService = .shared,
        appKeymapStore: AppKeymapStore = .shared,
        ruleCollectionStore: RuleCollectionStore = .shared,
        iconResolver: IconResolverService = .shared,
        faviconFetcher: FaviconFetcher = .shared
    ) {
        self.preferences = preferences
        self.appKeymapStore = appKeymapStore
        self.ruleCollectionStore = ruleCollectionStore
        self.iconResolver = iconResolver
        self.faviconFetcher = faviconFetcher
    }
}
```

Default values point to `.shared` so adoption is incremental — callers that don't pass anything get current behavior. Tests pass mocks.

#### 0b. Add SwiftUI Environment plumbing

Extend `DependencyInjection.swift`:

```swift
private struct ServiceContainerKey: EnvironmentKey {
    static var defaultValue: ServiceContainer { ServiceContainer() }
}

extension EnvironmentValues {
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
```

#### 0c. Inject from App.swift

```swift
// In App.init():
let container = ServiceContainer()

// In body:
ContentView()
    .environment(viewModel)
    .environment(\.services, container)
```

#### 0d. Migrate views one-by-one

Replace `PreferencesService.shared` → `@Environment(\.services) var services` then `services.preferences`. Start with the 13 views that use PreferencesService.

**Checklist:**
- [ ] Create `ServiceContainer.swift`
- [ ] Add `EnvironmentKey` for container
- [ ] Inject container in `App.swift`
- [ ] Migrate PreferencesService access in views (13 files)
- [ ] Migrate AppKeymapStore access in views (11 files)
- [ ] Migrate RuleCollectionStore access in views (7 files)
- [ ] Migrate IconResolverService access in views (7 files)
- [ ] Migrate FaviconFetcher access in views (8 files)

---

### Phase 1: Eliminate Single-Reference Singletons
**Goal:** Remove `.shared` from ~12 singletons that are only used in 1 file.
**Effort:** ~1 session

For each, create the instance locally or pass it from the parent. These are the trivial wins.

| Singleton | Consumer | Fix |
|-----------|----------|-----|
| `InputCaptureExperimentWindowController` | App.swift | Local let in App |
| `RecentKeypressesWindowController` | App.swift | Local let in App |
| `ContextHUDController` | App.swift | Local let in App |
| `HelpWindowController` | App.swift | Local let in App |
| `KanataErrorMonitor` | App.swift | Local let in App |
| `SimulatorWindowController` | AdvancedSettingsTabView | Pass via environment or local |
| `KindaVimStateAdapter` | ContextHUDController | Constructor inject |
| `BrowserHistoryScanner` | BrowserHistorySuggestionsView | Constructor inject or environment |
| `FeatureTipManager` | LiveKeyboardOverlayController | Constructor inject |
| `TooltipWindowController` | LiveKeyboardOverlayView+Header | Constructor inject |

**Note:** Many of these are `NSWindowController` singletons used to ensure one-window-at-a-time. These can stay singleton internally but should be accessed through the container or a `WindowCoordinator` rather than via `.shared` scattered across call sites.

**Checklist:**
- [ ] Audit each singleton above — confirm single reference
- [ ] For App.swift-only singletons, move to local `let` properties in App or a `WindowCoordinator`
- [ ] For view-only singletons, pass from parent or use environment
- [ ] Remove `static let shared` from each (or mark `fileprivate`)

---

### Phase 2: Service-Layer Constructor Injection
**Goal:** Mid-tier services receive their dependencies via init instead of reaching for `.shared`.
**Effort:** ~3 sessions

#### Target services (by dependency depth, bottom-up):

**Round 1 — Leaf services (no singleton deps):**
- `PermissionGate` — inject `PermissionOracle`
- `UserNotificationService` — inject `PreferencesService`
- `FaviconLoader` — inject `FaviconFetcher`
- `RecoveryDaemonService` — no deps besides logger

**Round 2 — Mid-level services:**
- `KanataDaemonManager` — inject `SubprocessRunner`, `HelperManager`, `PreferencesService`
- `ServiceHealthChecker` — inject `KanataDaemonManager`, `SubprocessRunner`, `KanataSplitRuntimeHostService`
- `ConfigHotReloadService` — inject `KanataDaemonManager`, `ServiceHealthChecker`
- `IconResolverService` — inject `FaviconFetcher`
- `WindowManager` — inject `SpaceManager`, `UserNotificationService`
- `AppContextService` — inject `PreferencesService`, `AppKeymapStore`

**Round 3 — Hub services:**
- `MainAppStateController` — inject `PermissionOracle`, `OrphanDetector`, `KanataDaemonManager`, `ServiceBootstrapper`, `ServiceHealthChecker`
- `PrivilegedOperationsCoordinator` — inject `HelperManager`, `SubprocessRunner`

**Pattern for each:**

```swift
// BEFORE:
class FooService {
    static let shared = FooService()

    func doWork() {
        BarService.shared.bar()
    }
}

// AFTER:
class FooService {
    static let shared = FooService()  // keep for now, remove in Phase 4

    private let barService: BarService

    init(barService: BarService = .shared) {  // default = backward compatible
        self.barService = barService
    }

    func doWork() {
        barService.bar()  // instance, not global
    }
}
```

The default parameter `= .shared` means all existing callers keep working. Tests can pass mocks. Once all callers inject explicitly, remove the default.

**Checklist:**
- [ ] Round 1: Leaf services (4 services)
- [ ] Round 2: Mid-level services (6 services)
- [ ] Round 3: Hub services (2 services)
- [ ] For each: add init params with `.shared` defaults, replace internal `.shared` references with stored properties
- [ ] Verify tests still pass after each round

---

### Phase 3: Expand ServiceContainer
**Goal:** Add mid-tier services to the container so the UI layer has a single injection point.
**Effort:** ~1 session

Grow the container as services are migrated:

```swift
@Observable
final class ServiceContainer {
    // Phase 0
    let preferences: PreferencesService
    let appKeymapStore: AppKeymapStore
    let ruleCollectionStore: RuleCollectionStore
    let iconResolver: IconResolverService
    let faviconFetcher: FaviconFetcher

    // Phase 3 additions
    let appContext: AppContextService
    let windowManager: WindowManager
    let helperManager: HelperManager
    let daemonManager: KanataDaemonManager
    let healthChecker: ServiceHealthChecker
    let stateController: MainAppStateController
}
```

Wire up in `App.init()`:
```swift
let container = ServiceContainer(
    preferences: preferencesService,
    daemonManager: KanataDaemonManager(
        subprocessRunner: subprocessRunner,
        helperManager: helperManager,
        preferences: preferencesService
    ),
    // ... etc
)
```

**Checklist:**
- [ ] Add Phase 2 services to ServiceContainer
- [ ] Update App.init() to wire the full graph
- [ ] Migrate remaining view files from `.shared` to `@Environment(\.services)`

---

### Phase 4: Protocol Abstractions for Testability
**Goal:** Add protocols only where tests need to substitute behavior.
**Effort:** ~2 sessions

Not every service needs a protocol. Focus on services with side effects that tests must avoid:

| Service | Why protocol needed |
|---------|-------------------|
| `HelperManager` | XPC calls, privileged operations |
| `KanataDaemonManager` | launchctl, process management |
| `SubprocessRunner` | spawns real processes |
| `ServiceBootstrapper` | system-level service installation |
| `ServiceHealthChecker` | pgrep, TCP probes |
| `PermissionOracle` | IOHIDCheckAccess, TCC database |
| `WindowManager` | CGS private API calls |

**Pattern:**
```swift
protocol DaemonManaging: Sendable {
    func startService() async throws
    func stopService() async throws
    var isRunning: Bool { get async }
}

extension KanataDaemonManager: DaemonManaging {}

// In tests:
final class MockDaemonManager: DaemonManaging { ... }
```

**Already done:** `PermissionSnapshotProviding` protocol exists for `PermissionOracle`.

**Checklist:**
- [ ] Define protocols for the 7 services above
- [ ] Make existing classes conform
- [ ] Update ServiceContainer to use protocol types where needed
- [ ] Create mock implementations in test target
- [ ] Update `KeyPathTestCase` to provide mock container

---

### Phase 5: Remove `.shared` from Migrated Services
**Goal:** Once all consumers inject via container or init, remove `static let shared`.
**Effort:** ~1 session per batch

This is the cleanup phase. For each service:
1. Search for remaining `.shared` references
2. If zero external references remain, remove `static let shared`
3. If some remain, migrate them first

**Order:** Bottom-up (leaf → hub), same as Phase 2.

**Checklist:**
- [ ] Remove `.shared` from Tier 2 leaf singletons
- [ ] Remove `.shared` from Tier 3 mid-tier services
- [ ] Remove `.shared` from Tier 4 hub services
- [ ] Grep confirm: zero `.shared` references outside ServiceContainer and App.init()

---

### Phase 6: Clean Up App.swift
**Goal:** Extract initialization into a proper CompositionRoot, leaving App.swift thin.
**Effort:** ~1 session

```swift
// CompositionRoot.swift
@MainActor
struct CompositionRoot {
    let container: ServiceContainer
    let coordinator: RuntimeCoordinator
    let viewModel: KanataViewModel

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configService = ConfigurationService(...)
        let helperManager = HelperManager()
        let daemonManager = KanataDaemonManager(helperManager: helperManager, ...)
        // ... build the full graph

        container = ServiceContainer(...)
        coordinator = RuntimeCoordinator(injectedConfigurationService: configService, ...)
        viewModel = KanataViewModel(manager: coordinator)
    }
}

// App.swift — now ~60 lines
struct KeyPathApp: App {
    @State private var root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(root.viewModel)
                .environment(\.services, root.container)
        }
    }
}
```

**Checklist:**
- [ ] Create `CompositionRoot.swift`
- [ ] Move all service creation from `App.init()` into `CompositionRoot`
- [ ] Keep `App.swift` as thin scene/window routing
- [ ] Verify app launches correctly

---

## Phase Summary

| Phase | What | Singletons Addressed | Effort |
|-------|------|---------------------|--------|
| **0** | ServiceContainer + top 5 services via Environment | 5 (46 view-file migrations) | ~2 sessions |
| **1** | Eliminate single-reference singletons | ~12 | ~1 session |
| **2** | Constructor injection in service layer (bottom-up) | ~12 | ~3 sessions |
| **3** | Expand container with mid-tier services | +6 | ~1 session |
| **4** | Protocol abstractions for testable services | 7 protocols | ~2 sessions |
| **5** | Remove `static let shared` | all migrated | ~2 sessions |
| **6** | Extract CompositionRoot from App.swift | — | ~1 session |

**Total estimated effort:** ~12 sessions, shipping incrementally.

## What We're NOT Doing

- **Not introducing a DI framework** (Swinject, Factory, etc.) — Swift's type system + init injection + SwiftUI Environment is sufficient.
- **Not adding protocols to everything** — only where tests need mock substitution.
- **Not touching AppLogger** — infrastructure logging stays global.
- **Not refactoring RuntimeCoordinator internals** — that's a separate item in the refactor plan.
- **Not changing test architecture** — `KeyPathTestCase` stays; we just give it a mock `ServiceContainer`.

## Risks

| Risk | Mitigation |
|------|-----------|
| SwiftUI `@Environment` default values mask missing injection | Add `assertionFailure` in debug builds if container is default-constructed outside App |
| Services with circular dependencies | Dependency graph analysis (above) shows no cycles — maintain this |
| Merge conflicts with active feature work | Do phases on separate branches; Phase 0 is the only large diff |
| Performance of container creation | Container is created once at launch; no runtime cost |

## Validation

After each phase:
1. `swift build` succeeds
2. `swift test` passes
3. App launches and basic flow works (install wizard, overlay, settings)
4. Grep for `.shared` shows decreasing count
