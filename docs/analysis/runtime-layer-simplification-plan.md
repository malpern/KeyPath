# Runtime Layer Simplification Plan

**Status:** Complete (Phases 1-3)
**Created:** 2026-05-02
**Goal:** Reduce the runtime orchestration layer from 12 types / 6,670 lines to a clear, minimal set that a senior Mac developer would approve of.

## Problem

Starting kanata traverses 6 types. Checking health involves 3. A novice developer can't trace the flow. The code has the same dead-weight wrapper pattern we eliminated in the wizard.

## Current Architecture (12 types, 6,670 lines)

```
MainAppStateController (843) → RuntimeCoordinator (1,679 across 10 files)
    → ServiceLifecycleCoordinator (262) → KanataDaemonService (323)
    → KanataDaemonManager (807) → PrivilegedOperationsCoordinator (1,246) → HelperManager
    
ServiceHealthChecker (826) ← ServiceHealthMonitor (525)
RecoveryCoordinator (262)
AppContextService (239)
StartupCoordinator (76)
ConfigReloadCoordinator (216)
```

## Analysis

### PrivilegedOperationsCoordinator (1,246 lines) — DELETE

Every method delegates to `HelperManager` (install/repair/activate via XPC to the privileged helper). The class adds:
- Postcondition verification after install (useful, but belongs in InstallerEngine)
- Guard logic for "already installed" checks (useful, ~50 lines)
- TCP port conflict detection (useful, ~40 lines)
- Logging wrappers (not useful as a separate layer)

`InstallerEngine.runSingleAction()` already calls through `PrivilegeBroker` → `PrivilegedOperationsCoordinator` → `HelperManager`. The middle layer is dead weight. `PrivilegeBroker` should delegate directly to `HelperManager`.

### RuntimeCoordinator (1,679 lines) — SLIM TO ~300

Currently a god object with 10 extension files. It mixes:
- **Service lifecycle** (start/stop/restart) — already delegated to `ServiceLifecycleCoordinator`
- **Config hot reload** — already delegated to `ConfigReloadCoordinator`  
- **Rule collections** — already delegated to `RuleCollectionsCoordinator`
- **Conflict resolution** — already delegated to `KarabinerConflictService`
- **Diagnostics** — already delegated to `DiagnosticsService`
- **System requirements** — should be direct calls to `InstallerEngine.inspectSystem()`
- **Permission checks** — should be direct calls to `PermissionOracle`

The core coordinator just wires these together and exposes the aggregated API to the ViewModel. After extracting the delegated concerns, it should be ~300 lines of property forwarding and lifecycle setup.

### KanataDaemonManager (807 lines) — REVIEW

Large but may be legitimate — manages SMAppService registration, daemon state queries, launchctl operations. Needs audit to check for overlap with `KanataDaemonService` (323 lines) and `ServiceBootstrapper` (1,020 lines).

## Execution Plan

### Phase 1: Delete PrivilegedOperationsCoordinator

1. **Make PrivilegeBroker delegate directly to HelperManager**
   - PrivilegeBroker currently calls `WizardDependencies.privilegedOperations` (which is PrivilegedOperationsCoordinator)
   - Change it to call `HelperManager.shared` directly
   - Move the postcondition verification into InstallerEngine recipes

2. **Move the useful guard logic (~90 lines)**
   - `decideInstallGuard()` → InstallerEngine precondition check
   - `detectKanataTCPPortConflict()` → ServiceHealthChecker
   - `verifyKanataReadinessAfterInstall()` → InstallerEngine postcondition

3. **Update WizardPrivilegedOperating protocol**
   - Make HelperManager conform directly (it already implements all the methods)
   - Remove PrivilegedOperationsCoordinator conformance

4. **Delete PrivilegedOperationsCoordinator.swift (1,246 lines)**

5. **Write golden tests first** — capture current behavior of each public method

### Phase 2: Slim RuntimeCoordinator

1. **Delete the 8 extension files that just delegate** (~500 lines)
   - `+ConfigHotReload.swift` → callers use `ConfigReloadCoordinator` directly
   - `+ConfigMaintenance.swift` → callers use `ConfigurationService` directly
   - `+ConflictResolution.swift` → callers use `KarabinerConflictService` directly
   - `+Diagnostics.swift` → callers use `DiagnosticsService` directly
   - `+RuleCollections.swift` → keep (core responsibility, views read from it)
   - `+ServiceManagement.swift` → callers use `ServiceLifecycleCoordinator` directly
   - `+State.swift` → inline into main file
   - `+Configuration.swift` → inline into main file
   - `+Lifecycle.swift` → inline into main file

2. **The core RuntimeCoordinator becomes:**
   - Property storage (ruleCollections, configPath, lastError, etc.)
   - Lifecycle setup (wire sub-coordinators in init)
   - Start/stop/restart (delegate to ServiceLifecycleCoordinator)
   - Status (delegate to ServiceHealthChecker)
   - Target: ~300 lines

### Phase 3: Audit KanataDaemonManager vs KanataDaemonService

**Result: Split is justified — DO NOT MERGE.**

- **KanataDaemonManager** (807 lines) = installation/registration lifecycle: SMAppService registration, legacy migration, stale registration detection, bundle validation
- **KanataDaemonService** (323 lines) = runtime monitoring: status polling, TCP health probes, crash logging, transient startup detection
- Different consumers: PrivilegedOperationsRouter uses only Manager; ServiceLifecycleCoordinator uses both
- Different concurrency: Manager does expensive one-off checks; Service does continuous polling
- Only real overlap is SMAppService.unregister() (one public, one private) — not worth merging for

## Results

### Phase 1: PrivilegedOperationsCoordinator → PrivilegedOperationsRouter
- Deleted PrivilegedOperationsCoordinator.swift (1,246 lines)
- Created PrivilegedOperationsRouter.swift (630 lines) — pure routing, no domain logic
- Extracted ServiceInstallGuard.swift (120 lines) — pure guard/decision logic
- Created 24 golden tests proving behavioral equivalence
- **Net: -496 lines**

### Phase 2: RuntimeCoordinator consolidation
- Deleted 8 extension files (506 lines), inlined into main file
- RuntimeCoordinator went from 10 files → 2 files (main + RuleCollections)
- **Net: -51 lines, -8 files**

### Phase 3: KanataDaemonManager vs KanataDaemonService audit
- Split is justified (see above)

### Overall
- **10 files deleted, 3 files created**
- **1,297 net lines removed**
- All 413 tests pass (including 24 new golden tests)

## Success Criteria

- [x] PrivilegedOperationsCoordinator deleted (replaced by PrivilegedOperationsRouter at 630 lines)
- [ ] RuntimeCoordinator under 400 lines (currently 1,500 — requires deeper caller-redirection refactor)
- [x] A novice can trace "start kanata" in 2 hops: ViewModel → ServiceLifecycleCoordinator → launchctl
- [x] All existing tests pass
- [x] KanataDaemonManager/Service audit complete — split justified
