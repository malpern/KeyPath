# Service Management State Machine Design

## Problem Statement

We need a robust, centralized system for managing the Kanata LaunchDaemon that prevents accidental fallback to legacy `launchctl` after migration to `SMAppService`. The current implementation has guards scattered throughout the codebase, creating opportunities for inconsistencies and race conditions.

## Current Issues

1. **Inconsistent State Detection**: Multiple methods check different conditions:
   - `isUsingSMAppService` (feature flag + SMAppService status)
   - `isRegisteredViaSMAppService()` (SMAppService status only)
   - `hasLegacyInstallation()` (legacy plist existence)
   - `isServiceLoaded()` (complex logic mixing all three)

2. **No Single Source of Truth**: State determination logic is duplicated across multiple files

3. **Race Conditions**: Checks happen at different times, allowing state to change between checks

4. **Reactive Guards**: Guards are placed at each decision point rather than having a centralized decision function

5. **Ambiguous States**: No clear enum representing all possible system states

## Proposed Solution: Centralized State Machine

### Core Principles

1. **Single Source of Truth**: One function determines the current state
2. **Explicit State Enum**: All possible states are clearly defined
3. **State-Aware Guards**: State is checked, then guards use state + feature flag to make decisions
4. **Defensive Re-checks**: Critical operations re-check state immediately before acting
5. **Clear State Transitions**: Only specific operations can change state

### Architecture Decision

**Hybrid Approach**: State determination is centralized, but feature flag still drives primary routing. State is used for guards and validation.

- **Feature flag** determines which path to attempt (SMAppService vs launchctl)
- **State** determines if that path is allowed (guards prevent conflicts)
- **State** is re-checked at critical action points (defensive)

This preserves existing behavior while adding safety guards.

### State Enum

```swift
enum ServiceManagementState {
    case legacyActive          // Legacy plist exists, launchctl managing
    case smappserviceActive    // No legacy plist, SMAppService .enabled
    case smappservicePending  // No legacy plist, SMAppService .requiresApproval
    case uninstalled          // No legacy plist, SMAppService .notFound, process not running
    case conflicted           // Both legacy plist AND SMAppService active (error state)
    case unknown              // Ambiguous state requiring investigation
    
    // Note: No .migrated state - migration is a transition, not a persistent state
    // After migration, state becomes .smappserviceActive or .smappservicePending
}
```

### State Determination Logic

**Priority Order (most reliable first):**
1. **Conflict Check**: Both legacy plist AND SMAppService `.enabled` → `conflicted` (error state)
2. **Legacy Plist Exists**: → `legacyActive` (most reliable indicator)
3. **SMAppService `.enabled`**: → `smappserviceActive`
4. **SMAppService `.requiresApproval`**: → `smappservicePending`
5. **Process Running but No Clear Management**: → `unknown` (investigate)
6. **Nothing Found**: → `uninstalled`

### Centralized Decision Function

```swift
nonisolated static func determineServiceManagementState() -> ServiceManagementState {
    let hasLegacy = FileManager.default.fileExists(atPath: legacyPlistPath)
    let svc = smServiceFactory(kanataPlistName)
    let smStatus = svc.status
    let isProcessRunning = pgrepKanataProcess()
    
    // Check for conflicts first (both methods active - error state)
    if hasLegacy && smStatus == .enabled {
        return .conflicted
    }
    
    // Priority 1: Legacy plist existence (most reliable check)
    if hasLegacy {
        return .legacyActive
    }
    
    // Priority 2: SMAppService status
    switch smStatus {
    case .enabled:
        return .smappserviceActive
    case .requiresApproval:
        return .smappservicePending
    case .notFound, .notRegistered:
        // No legacy plist and SMAppService not registered
        if isProcessRunning {
            // Process running but unclear management - investigate
            return .unknown
        }
        return .uninstalled
    @unknown default:
        return .unknown
    }
}
```

### Decision Matrix for Operations

**Key Principle**: Feature flag determines which path to attempt, state determines if it's allowed.

| Current State | Feature Flag | Operation Attempted | Allowed? | Action |
|--------------|--------------|-------------------|----------|--------|
| `legacyActive` | OFF | Install via launchctl | ✅ | Create legacy plist |
| `legacyActive` | ON | Install via SMAppService | ❌ | **GUARD**: Return false, must migrate first |
| `legacyActive` | ON | Install via launchctl | ❌ | **GUARD**: Return false, feature flag requires SMAppService |
| `smappserviceActive` | ON/OFF | Install via launchctl | ❌ | **GUARD**: Return false, SMAppService is active |
| `smappserviceActive` | ON | Install via SMAppService | ⚠️ | Skip (already installed) |
| `smappservicePending` | ON/OFF | Install via launchctl | ❌ | **GUARD**: Return false, SMAppService is pending |
| `smappservicePending` | ON | Install via SMAppService | ⚠️ | Skip (already registered, approval pending) |
| `uninstalled` | OFF | Install via launchctl | ✅ | Create legacy plist |
| `uninstalled` | ON | Install via SMAppService | ✅ | Register via SMAppService |
| `conflicted` | ON/OFF | Any install | ❌ | **ERROR**: Resolve conflict first (auto-resolve: remove legacy if flag ON) |
| `unknown` | ON/OFF | Any install | ⚠️ | **WARN**: Investigate first (check process owner, make best guess) |

### Error Handling Strategy

#### `.conflicted` State
**Auto-resolution**: If feature flag is ON, automatically remove legacy plist and unload service.
```swift
if state == .conflicted && FeatureFlags.useSMAppServiceForDaemon {
    // Auto-resolve: remove legacy, keep SMAppService
    removeLegacyPlist()
    return .smappserviceActive
}
```

#### `.unknown` State
**Investigation**: Check process owner, check launchctl, make best guess.
```swift
if state == .unknown {
    // Check if process is owned by launchd (legacy) or app (SMAppService)
    let processOwner = getProcessOwner()
    if processOwner == "root" {
        // Likely legacy launchctl
        return .legacyActive
    } else {
        // Likely SMAppService but status unclear
        return .smappservicePending
    }
}
```

#### SMAppService Registration Failures
**No Fallback**: If feature flag is ON and registration fails, do NOT fall back to launchctl.
- Return false/error
- Log detailed error
- User must approve in System Settings or resolve issue

### Implementation Strategy

1. **Create `ServiceManagementState` enum** in `KanataDaemonManager`
2. **Add `determineServiceManagementState()`** as single source of truth
3. **Replace all scattered checks** with calls to this function
4. **Add guards** at all installation points using the state
5. **Add state transition functions** for migration/rollback

### Key Guards Implementation

**Hybrid Approach**: Feature flag drives routing, state provides guards.

```swift
func createKanataLaunchDaemon() async -> Bool {
    // Feature flag determines which path to attempt
    let featureFlagValue = FeatureFlags.useSMAppServiceForDaemon
    
    if featureFlagValue {
        // Attempt SMAppService path
        // GUARD: Check state before proceeding
        let state = KanataDaemonManager.determineServiceManagementState()
        
        switch state {
        case .smappserviceActive, .smappservicePending:
            // Already managed - skip
            return true
        case .legacyActive:
            // Legacy exists - must migrate first, don't install
            AppLogger.shared.log("⚠️ Legacy plist exists - must migrate first")
            return false
        case .conflicted:
            // Auto-resolve: remove legacy
            await resolveConflict()
            return await createKanataLaunchDaemonViaSMAppService()
        case .unknown:
            // Investigate and make best guess
            let resolvedState = await investigateUnknownState()
            if resolvedState.isSMAppServiceManaged {
                return true  // Already managed
            }
            // Fall through to registration
        case .uninstalled:
            // Fresh install - proceed
            break
        }
        
        // DEFENSIVE: Re-check state immediately before acting
        let finalState = KanataDaemonManager.determineServiceManagementState()
        if finalState.isSMAppServiceManaged {
            return true  // State changed, already managed
        }
        
        return await createKanataLaunchDaemonViaSMAppService()
    } else {
        // Attempt launchctl path
        // GUARD: Check state before proceeding
        let state = KanataDaemonManager.determineServiceManagementState()
        
        switch state {
        case .smappserviceActive, .smappservicePending:
            // SMAppService is active - don't create legacy plist
            AppLogger.shared.log("⚠️ SMAppService is active - cannot use launchctl")
            return false
        case .legacyActive:
            // Already managed by legacy - skip
            return true
        case .conflicted:
            // Error state - log and return false
            AppLogger.shared.error("Conflicted state detected")
            return false
        case .unknown, .uninstalled:
            // Proceed with launchctl installation
            break
        }
        
        // DEFENSIVE: Re-check state immediately before acting
        let finalState = KanataDaemonManager.determineServiceManagementState()
        if finalState.isSMAppServiceManaged {
            return false  // State changed, SMAppService now active
        }
        
        return createKanataLaunchDaemonViaLaunchctl()
    }
}
```

### Benefits

1. **Single Source of Truth**: One function determines state
2. **Explicit States**: All states clearly defined
3. **Consistent Behavior**: All code paths use same logic
4. **Easier Debugging**: State is logged and traceable
5. **Prevents Accidents**: Guards prevent wrong operations
6. **Defensive Re-checks**: Critical operations verify state before acting
7. **Backward Compatible**: Feature flag still drives primary routing

## Implementation Plan: 3 Phases

### Phase 1: Foundation (State Machine Core)
**Goal**: Add state machine infrastructure without changing behavior

**Tasks**:
1. ✅ Add `ServiceManagementState` enum to `KanataDaemonManager`
2. ✅ Add `determineServiceManagementState()` function
3. ✅ Add state convenience properties (`isSMAppServiceManaged`, etc.)
4. Add comprehensive logging to state determination
5. Add unit tests for state determination logic

**Testable Results**:
- [ ] State enum compiles and all cases are defined
- [ ] `determineServiceManagementState()` returns correct state for all scenarios:
  - [ ] Legacy plist exists → `.legacyActive`
  - [ ] SMAppService `.enabled` → `.smappserviceActive`
  - [ ] SMAppService `.requiresApproval` → `.smappservicePending`
  - [ ] Both exist → `.conflicted`
  - [ ] Neither exists, process running → `.unknown`
  - [ ] Neither exists, no process → `.uninstalled`
- [ ] State determination logs all inputs and decision
- [ ] Unit tests pass for all state scenarios
- [ ] No behavior changes (existing code still works)

**Validation**:
```bash
# Test state determination
swift test --filter KanataDaemonManagerTests.testStateDetermination
# Verify no regressions
swift test --filter LaunchDaemonInstallerTests
```

---

### Phase 2: Critical Guards (Prevent Accidents)
**Goal**: Add state-based guards to prevent accidental fallback to legacy

**Tasks**:
1. Update `createKanataLaunchDaemonViaLaunchctl()` to check state
   - Guard: If state is `.smappserviceActive` or `.smappservicePending`, return false
2. Update `createKanataLaunchDaemonViaSMAppService()` to check state
   - Guard: If state is `.legacyActive`, return false (must migrate first)
   - Guard: If state is `.conflicted`, auto-resolve
3. Update `isServiceLoaded()` to use state determination
   - Replace scattered checks with state-based logic
4. Add defensive re-checks before critical actions

**Testable Results**:
- [ ] `createKanataLaunchDaemonViaLaunchctl()` returns false when SMAppService is active
- [ ] `createKanataLaunchDaemonViaSMAppService()` returns false when legacy is active
- [ ] `isServiceLoaded()` correctly identifies SMAppService-managed services
- [ ] Legacy plist is NOT recreated after migration
- [ ] App restart doesn't revert to legacy after migration
- [ ] All existing tests pass

**Validation**:
```bash
# Test guards
swift test --filter LaunchDaemonInstallerTests.testGuardsPreventLegacyFallback
# Test migration persistence
./test-migration-persistence.sh
# Verify no regressions
swift test
```

**Manual Test Scenarios**:
1. Migrate to SMAppService → Restart app → Verify still using SMAppService
2. Migrate to SMAppService → Delete legacy plist → Restart app → Verify no legacy plist recreated
3. Fresh install with feature flag ON → Verify uses SMAppService
4. Fresh install with feature flag OFF → Verify uses launchctl

---

### Phase 3: Complete Migration (Replace All Checks)
**Goal**: Replace all scattered state checks with centralized state machine

**Tasks**:
1. Update `restartUnhealthyServices()` to use state
   - Remove Kanata from `toInstall` if state is SMAppService-managed
2. Update `createAllLaunchDaemonServicesInstallOnly()` to use state
   - Skip Kanata if state is SMAppService-managed
3. Update `createConfigureAndLoadAllServices()` to use state
   - Use state for guards and validation
4. Update `WizardAutoFixer` to use state
   - Use state for migration detection
5. Update UI (`DiagnosticsView`) to use state
   - Display state instead of calculating separately
6. Deprecate old methods (keep as wrappers for compatibility)
   - `isUsingSMAppService` → wrapper around state
   - `hasLegacyInstallation()` → wrapper around state
   - `isRegisteredViaSMAppService()` → wrapper around state

**Testable Results**:
- [ ] All installation paths use state machine
- [ ] All status checks use state machine
- [ ] UI correctly displays state
- [ ] No legacy plist recreation in any scenario
- [ ] Migration persists across restarts
- [ ] Rollback works correctly
- [ ] All existing tests pass
- [ ] Performance is acceptable (state determination < 10ms)

**Validation**:
```bash
# Test all paths
swift test --filter ServiceManagementStateTests
# Test UI
swift test --filter DiagnosticsViewTests
# Test end-to-end
./test-complete-migration.sh
# Performance test
swift test --filter PerformanceTests.testStateDeterminationPerformance
```

**Manual Test Scenarios**:
1. **Migration Flow**: Legacy → Migrate → Restart → Verify SMAppService active
2. **Rollback Flow**: SMAppService → Rollback → Restart → Verify legacy active
3. **Conflict Resolution**: Create conflict → Verify auto-resolution
4. **Unknown State**: Simulate unknown → Verify investigation logic
5. **Fresh Install**: No existing installation → Verify correct path chosen

---

## Success Criteria

### Phase 1 Complete When:
- State machine compiles and tests pass
- State determination is accurate for all scenarios
- No behavior changes observed

### Phase 2 Complete When:
- Guards prevent legacy fallback in all tested scenarios
- Migration persists across app restarts
- No regressions in existing functionality

### Phase 3 Complete When:
- All code paths use state machine
- Old methods are deprecated but still work
- Performance is acceptable
- All tests pass
- Manual testing confirms robustness

## Rollback Plan

If issues arise:
- **Phase 1**: State machine is additive, can be disabled via feature flag
- **Phase 2**: Guards can be disabled individually, old code paths still exist
- **Phase 3**: Old methods remain as wrappers, can revert to direct calls

## Performance Considerations

- State determination involves: file check (~0.1ms), SMAppService status (~0.1ms), pgrep (~5-10ms)
- Total: ~5-10ms per call
- **Caching Strategy**: Cache state for 1 second, invalidate on state-changing operations
- **Optimization**: Skip pgrep if legacy plist exists or SMAppService is enabled

