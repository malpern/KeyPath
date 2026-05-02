# RuntimeCoordinator Decomposition Plan

## The Problem

RuntimeCoordinator is a 1,713-line God Object split across 12 files. It owns 28 sub-managers and exposes ~60 methods spanning service lifecycle, config management, rule collections, diagnostics, installation, recovery, and UI state publishing.

The irony: most domain logic is *already* extracted into focused coordinators (ServiceLifecycleCoordinator, ConfigReloadCoordinator, RuleCollectionsCoordinator, etc.). RuntimeCoordinator's remaining role is **pass-through delegation** — it forwards calls to sub-coordinators and aggregates their state for the UI. But consumers hold a reference to the whole RuntimeCoordinator when they only need one slice.

This creates three concrete problems:

1. **Cognitive overload.** Opening RuntimeCoordinator to understand, say, config reload requires scanning 1,052 lines of init + state to find the 2 methods that delegate to ConfigReloadCoordinator.

2. **Dependency opacity.** `MapperViewModel` takes a `RuntimeCoordinator?` but only calls `ruleCollectionsCoordinator` methods. `MainAppStateController` takes it but only calls `isInTransientRuntimeStartupWindow()` and `clearDiagnostics()`. The dependency graph looks like "everything depends on everything" when the actual coupling is narrow.

3. **Testing friction.** Testing a component that takes RuntimeCoordinator requires either constructing the full object graph (28 sub-managers) or mocking a broad protocol.

## What NOT to Do

- **Don't create new abstraction layers.** The sub-coordinators already exist. The fix is exposing them directly, not wrapping them in more protocols.
- **Don't rename RuntimeCoordinator.** The name is fine for what it should become — a thin orchestration root.
- **Don't extract more sub-coordinators.** The 28 that exist are already fine-grained. The problem is how they're wired, not how they're structured.
- **Don't try to do this in one PR.** Each phase should be independently shippable.

## The Target Architecture

RuntimeCoordinator shrinks from a God Object to a **composition root for runtime services** — it creates and wires sub-coordinators in init, holds shared state (keyMappings, diagnostics, currentLayerName), and exposes the sub-coordinators as public properties. Consumers take the specific coordinator they need, not the whole RuntimeCoordinator.

```
Before:                              After:
                                     
MapperViewModel                      MapperViewModel
  → RuntimeCoordinator               → RuleCollectionsCoordinator (direct)
    → ruleCollectionsCoordinator         
                                     MainAppStateController
MainAppStateController               → ServiceLifecycleCoordinator (direct)
  → RuntimeCoordinator                   
    → serviceLifecycleCoordinator    KanataViewModel
    → clearDiagnostics()             → RuntimeCoordinator (thin, for UI state)
```

## Current Consumer Analysis

| Consumer | What it actually uses | Narrow dependency |
|----------|----------------------|-------------------|
| KanataViewModel | UI state, start/stop, config, rules, diagnostics | RuntimeCoordinator (legitimate — it's the ViewModel's backing model) |
| MainAppStateController | `isInTransientRuntimeStartupWindow()`, `clearDiagnostics()`, `currentRuntimeStatusInternal()` | ServiceLifecycleCoordinator + DiagnosticsManager |
| MapperViewModel | Rule collection methods | RuleCollectionsCoordinator |
| RecordingCoordinator | Rule collection save | RuleCollectionsCoordinator |
| KanataConfigGenerator | Rule collections, config service | RuleCollectionsCoordinator + ConfigurationService |
| SystemValidator | `inspectSystemContext()` (for wizard compat) | InstallerEngine |
| SimpleModsService | Rule collections | RuleCollectionsCoordinator |
| KeyboardCapture | Rule collections | RuleCollectionsCoordinator |
| WizardCommunicationPage | Start/restart kanata | ServiceLifecycleCoordinator |

**Key insight:** 6 out of 9 consumers only need RuleCollectionsCoordinator or ServiceLifecycleCoordinator. Only KanataViewModel legitimately needs the full RuntimeCoordinator.

---

## Phase 1: Expose Sub-Coordinators as Public Properties

**Risk: Low. No behavior change.**

RuntimeCoordinator's sub-coordinators are currently `private`. Make the most-consumed ones `public` (or `internal`) so consumers can access them directly.

```swift
// Before
class RuntimeCoordinator {
    private let serviceLifecycleCoordinator: ServiceLifecycleCoordinator
    private let ruleCollectionsCoordinator: RuleCollectionsCoordinator
    // ...
}

// After
class RuntimeCoordinator {
    let serviceLifecycleCoordinator: ServiceLifecycleCoordinator
    let ruleCollectionsCoordinator: RuleCollectionsCoordinator
    // ...
}
```

**Files touched:** RuntimeCoordinator.swift (change access modifiers)
**Tests:** Existing tests pass unchanged.

---

## Phase 2: Narrow Consumer Dependencies

**Risk: Low-Medium. Mechanical refactor per consumer.**

For each consumer, replace `RuntimeCoordinator` with the specific sub-coordinator it actually needs. Do this one consumer at a time.

### 2a: MainAppStateController
```swift
// Before
private weak var kanataManager: RuntimeCoordinator?

// After  
private weak var serviceLifecycle: ServiceLifecycleCoordinator?
private weak var diagnosticsManager: DiagnosticsManaging?
```

### 2b: MapperViewModel
```swift
// Before
var kanataManager: RuntimeCoordinator?

// After
var ruleCollections: RuleCollectionsCoordinator?
```

### 2c: RecordingCoordinator, SimpleModsService, KeyboardCapture
Same pattern — replace RuntimeCoordinator with RuleCollectionsCoordinator.

### 2d: WizardCommunicationPage
Replace RuntimeCoordinator with ServiceLifecycleCoordinator.

### 2e: KanataConfigGenerator
Replace RuntimeCoordinator with RuleCollectionsCoordinator + ConfigurationService.

**Each sub-phase is one PR.** Start with 2a (MainAppStateController) since it's the most impactful — it removes the illusion that MainAppStateController depends on the entire runtime.

---

## Phase 3: Delete Pass-Through Methods

**Risk: Low. Each deletion is a compile-time verification.**

After Phase 2, many RuntimeCoordinator extension methods become dead code. Delete them one domain at a time:

1. **+ServiceManagement.swift** — consumers now call ServiceLifecycleCoordinator directly
2. **+Engine.swift** — same
3. **+Diagnostics.swift** — consumers now call DiagnosticsManager directly
4. **+ConflictResolution.swift** — can be inlined into RuleCollectionsCoordinator
5. **+Output.swift** — already empty

After this, RuntimeCoordinator should be ~400-500 lines: init/wiring, shared UI state, and the callbacks that bridge sub-coordinators.

---

## Phase 4: Extract Shared UI State (Optional)

**Risk: Medium. Changes the ViewModel's data source.**

The remaining RuntimeCoordinator state (`keyMappings`, `currentLayerName`, `diagnostics`, `saveStatus`, `lastError`, `validationError`) is UI-facing and consumed by KanataViewModel. This could be extracted into a `RuntimeUIState` observable that KanataViewModel observes directly, leaving RuntimeCoordinator as a pure wiring/orchestration object.

This is optional because KanataViewModel already wraps RuntimeCoordinator — the extra layer may not reduce complexity enough to justify the churn.

---

## Verification

After each phase, verify:
1. `swift build` passes
2. `swift test` passes
3. The app launches and basic remapping works (dd deploy)
4. Settings Status tab shows correct state
5. Wizard opens and detects system state correctly

## What This Achieves

| Metric | Before | After (Phase 3) |
|--------|--------|-----------------|
| RuntimeCoordinator lines | 1,052 | ~400 |
| Extension files | 11 | ~5 |
| Consumers holding full RuntimeCoordinator | 9 | 1 (KanataViewModel) |
| Methods on RuntimeCoordinator | ~60 | ~15 |
| Time to understand "what does X depend on" | Read 1,052 lines | Read the constructor (5 lines) |

## Not In Scope

- Breaking up KanataViewModel (separate effort, depends on this)
- Eliminating single-conformer protocols (orthogonal)
- Simplifying the startup chain (overlaps but is a separate concern)
- Overlay view decomposition (UI-layer, not coordinator-layer)
