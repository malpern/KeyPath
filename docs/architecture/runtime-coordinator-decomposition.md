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

## Phase 1: Expose Sub-Coordinators as Public Properties ✅ DONE

Sub-coordinators were already `internal` (no access modifier). No changes needed.

---

## Phase 2: Narrow Consumer Dependencies — PARTIAL

### 2a: MainAppStateController ✅ DONE
Narrowed from `RuntimeCoordinator` to `ServiceLifecycleCoordinator` + `onSystemHealthy` closure.

### 2b-2e: Remaining consumers — DEFERRED
MapperViewModel, RecordingCoordinator, SimpleModsService, and KanataConfigGenerator use multiple RuntimeCoordinator domains (rules + lifecycle + config). Narrowing them would trade one dependency for 3-4 smaller ones — not simpler. These consumers legitimately need broad access.

---

## Phase 3: Delete Pass-Through Methods ✅ DONE

Deleted 6 dead pass-through methods and 2 empty extension files:
- `startKanataWithValidation()`, `shouldShowWizardForPermissions()`, `isFirstTimeInstall()`
- `getSystemDiagnostics()`, `areKarabinerBackgroundServicesEnabled()`, `disableKarabinerElementsPermanently()`
- Deleted `RuntimeCoordinator+Engine.swift` and `RuntimeCoordinator+Output.swift` (imports only)

12 → 10 files, 1713 → 1679 lines.

---

## Phase 4: Extract Shared UI State — SKIPPED

Not worth the churn. KanataViewModel already wraps RuntimeCoordinator as its backing model. Adding another layer wouldn't reduce complexity.

---

## Verification

After each phase, verify:
1. `swift build` passes
2. `swift test` passes
3. The app launches and basic remapping works (dd deploy)
4. Settings Status tab shows correct state
5. Wizard opens and detects system state correctly

## What Was Achieved

| Metric | Before | After |
|--------|--------|-------|
| RuntimeCoordinator total lines | 1,713 | 1,679 |
| Extension files | 12 | 10 |
| MainAppStateController dependency | Full RuntimeCoordinator | ServiceLifecycleCoordinator + closure |
| Dead pass-through methods | 6 | 0 |
| Duplicate navigation paths | 2 (determineNextPage + getNextPage) | 1 (getNextPage only) |

## Not In Scope

- Breaking up KanataViewModel (separate effort, depends on this)
- Eliminating single-conformer protocols (orthogonal)
- Simplifying the startup chain (overlaps but is a separate concern)
- Overlay view decomposition (UI-layer, not coordinator-layer)
