# KeyPath Manager Consolidation Analysis & Plan

**Milestone 3 Deliverable**  
**Date:** August 26, 2025  
**Status:** Analysis Complete - Implementation Ready  

## Executive Summary

KeyPath currently has **3 overlapping managers** handling Kanata lifecycle operations, creating complexity, duplication, and potential inconsistencies. This analysis identifies consolidation opportunities while preserving all current functionality.

### Current State Overview

| Manager | Lines | Purpose | Dependencies |
|---------|-------|---------|--------------|
| **KanataManager** | 3,298 | Core service management, configuration, diagnostics | ProcessLifecycleManager |
| **SimpleKanataManager** | 712 | User-focused UI state management | KanataManager |  
| **KanataLifecycleManager** | 426 | State machine coordination | KanataManager |

**Total:** 4,436 lines across 3 managers with significant overlap

## Detailed Analysis

### 1. Functionality Overlap Matrix

#### Lifecycle Operations
| Operation | KanataManager | SimpleKanataManager | KanataLifecycleManager | Overlap Level |
|-----------|---------------|--------------------|-----------------------|---------------|
| **Start Kanata** | ✅ `startKanata()` | ✅ `manualStart()` | ✅ `startKanata()` | **HIGH** |
| **Stop Kanata** | ✅ `stopKanata()` | ✅ `manualStop()` | ✅ `stopKanata()` | **HIGH** |
| **Restart Kanata** | ✅ `restartKanata()` | ❌ | ✅ `restartKanata()` | **MEDIUM** |
| **Status Monitoring** | ✅ `updateStatus()` | ✅ `forceRefreshStatus()` | ✅ State machine | **HIGH** |

#### State Management
| State | KanataManager | SimpleKanataManager | KanataLifecycleManager | Overlap Level |
|-------|---------------|--------------------|-----------------------|---------------|
| **isRunning** | ✅ `@Published var isRunning` | ✅ `currentState.isWorking` | ✅ `@Published var isRunning` | **CRITICAL** |
| **Error Handling** | ✅ `@Published var lastError` | ✅ `@Published var errorReason` | ✅ `@Published var errorMessage` | **HIGH** |
| **Busy State** | ✅ `isStartingKanata` | ✅ `currentState == .starting` | ✅ `@Published var isBusy` | **HIGH** |

#### Permission Checking
| Check | KanataManager | SimpleKanataManager | KanataLifecycleManager | Bypass Pattern |
|-------|---------------|--------------------|-----------------------|----------------|
| **Input Monitoring** | ✅ `hasInputMonitoringPermission()` | ✅ `updatePermissionState()` | ❌ | Direct API calls |
| **Accessibility** | ❌ | ✅ `updatePermissionState()` | ✅ `checkAccessibilityPermissions()` | Direct API calls |
| **System Requirements** | ✅ `getSystemDiagnostics()` | ✅ `updateLaunchStatus()` | ✅ `checkRequirements()` | Mixed approaches |

### 2. Dependency Analysis

```
App.swift
├── KanataManager (Primary - @StateObject)
└── SimpleKanataManager (UI Layer - depends on KanataManager)
    
InstallationWizard/
├── Uses KanataManager directly
└── Creates temporary instances

KanataLifecycleManager
├── Wraps KanataManager
└── Adds state machine layer
```

**Key Finding:** `SimpleKanataManager` and `KanataLifecycleManager` are **wrapper layers** around `KanataManager`, not independent services.

### 3. Permission Checking Bypass Patterns

#### Direct API Bypasses (Violate PermissionOracle Centralization)
1. **SimpleKanataManager.swift:425-440**
   ```swift
   private func checkInputMonitoringPermission() -> Bool {
       // Direct IOHIDCheckAccess call - bypasses PermissionOracle
   }
   ```

2. **KanataLifecycleManager.swift:347-350**
   ```swift
   private func checkAccessibilityPermissions() async -> Bool {
       // TODO: Direct accessibility check - bypasses PermissionOracle
   }
   ```

3. **KanataManager.swift:1376-1385**
   ```swift
   func hasInputMonitoringPermission() async -> Bool {
       // Uses WizardSystemPaths instead of PermissionOracle
   }
   ```

#### Recommended Fixes
- All permission checks should delegate to `PermissionOracle.shared`
- Remove direct `IOHIDCheckAccess` and `AXIsProcessTrusted` calls
- Use standardized permission checking patterns

### 4. Shared Lifecycle Logic Patterns

#### Common Patterns Across Managers
1. **Start Sequence**
   ```
   Check Prerequisites → Validate Config → Start Service → Update State → Monitor Health
   ```

2. **State Transitions**
   ```
   Idle → Starting → Running → [Error/Stopped]
   ```

3. **Error Recovery**
   ```
   Detect Issue → Diagnose → Attempt Auto-Fix → Fallback to Manual
   ```

#### Duplication Hotspots
- **Configuration validation** (3 different implementations)
- **Service status checking** (3 different approaches)
- **Error message formatting** (inconsistent patterns)
- **Permission requirement checking** (bypasses central oracle)

## Consolidation Strategy

### Phase 1: Eliminate Wrapper Managers (Recommended)

#### 1.1 Absorb SimpleKanataManager into KanataManager
- **Rationale:** SimpleKanataManager is purely a UI state wrapper
- **Approach:** Add UI-focused properties and methods to KanataManager
- **Impact:** Reduces complexity, eliminates state synchronization issues

#### 1.2 Deprecate KanataLifecycleManager
- **Rationale:** State machine adds complexity without clear benefit
- **Approach:** Move useful state tracking directly into KanataManager
- **Impact:** Simplifies call chains, reduces indirection

#### 1.3 Enhanced KanataManager
```swift
class KanataManager: ObservableObject {
    // Core functionality (existing)
    @Published var isRunning = false
    @Published var lastError: String?
    
    // UI-focused additions (from SimpleKanataManager)
    @Published var currentState: LifecycleState = .idle
    @Published var autoStartAttempts: Int = 0
    @Published var showWizard: Bool = false
    
    // Lifecycle coordination (from KanataLifecycleManager)
    @Published var canPerformActions: Bool = true
    @Published var shouldShowWizard: Bool = false
    
    // Unified interface
    func startKanata() async { /* existing implementation */ }
    func stopKanata() async { /* existing implementation */ }
    func restartKanata() async { /* existing implementation */ }
    
    // UI helpers
    func startAutoLaunch() async { /* from SimpleKanataManager */ }
    func manualStart() async { /* delegates to startKanata */ }
    func manualStop() async { /* delegates to stopKanata */ }
    
    // Permission integration
    private let permissionOracle = PermissionOracle.shared
    func checkPermissions() async -> PermissionStatus { /* unified approach */ }
}
```

### Phase 2: Permission Integration (Required for Architecture Compliance)

#### 2.1 Replace Direct Permission Checks
- Remove all `IOHIDCheckAccess` calls
- Remove all `AXIsProcessTrusted` calls  
- Use `PermissionOracle.shared.checkPermission(_:for:)` exclusively

#### 2.2 Standardized Permission Patterns
```swift
// Before (bypasses Oracle)
func hasInputMonitoring() -> Bool {
    return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}

// After (uses Oracle)
func hasInputMonitoring() async -> Bool {
    let status = await PermissionOracle.shared.checkPermission(
        .inputMonitoring, 
        for: .currentApp
    )
    return status.isGranted
}
```

## Implementation Plan

### Milestone 3 Completion Tasks

#### Task 1: Create Unified KanataManager Interface
- [ ] Add SimpleKanataManager UI properties to KanataManager
- [ ] Add KanataLifecycleManager state tracking to KanataManager  
- [ ] Create delegation methods for UI operations
- [ ] Preserve all existing public APIs for compatibility

#### Task 2: Update Permission Checking
- [ ] Replace all direct permission API calls with PermissionOracle
- [ ] Remove permission checking duplication
- [ ] Standardize permission error handling
- [ ] Add permission change observation

#### Task 3: Migration Path
- [ ] Create compatibility shims for existing code
- [ ] Update App.swift to use unified manager
- [ ] Update InstallationWizard integration
- [ ] Maintain backward compatibility during transition

### Migration Strategy

#### Step 1: Internal Consolidation (Safe)
1. Move UI state from SimpleKanataManager into KanataManager
2. Keep SimpleKanataManager as thin wrapper (compatibility)
3. Redirect KanataLifecycleManager calls to KanataManager
4. Test all existing functionality

#### Step 2: Permission Oracle Integration (Required)
1. Replace permission checking bypasses with Oracle calls
2. Update error handling to use standardized patterns
3. Test permission flow integration
4. Validate with existing permission requirements

#### Step 3: API Cleanup (Breaking Changes)
1. Remove SimpleKanataManager entirely
2. Remove KanataLifecycleManager entirely  
3. Update all call sites to use KanataManager directly
4. Remove compatibility shims
5. Full integration testing

## Risk Assessment

### Low Risk Changes
- ✅ Moving properties between managers
- ✅ Adding delegation methods
- ✅ Permission Oracle integration
- ✅ Internal restructuring with compatibility shims

### Medium Risk Changes  
- ⚠️ Removing wrapper managers entirely
- ⚠️ Changing App.swift state management
- ⚠️ Modifying InstallationWizard integration

### High Risk Changes
- ❌ Breaking existing public APIs (avoided in this plan)
- ❌ Removing established UI patterns (preserved)
- ❌ Changing observable object relationships (handled carefully)

## Success Criteria

### Functional Preservation
- [ ] All existing UI behavior preserved
- [ ] All lifecycle operations work identically  
- [ ] All permission flows function correctly
- [ ] All error handling maintains user experience
- [ ] All diagnostic capabilities retained

### Code Quality Improvements
- [ ] Reduced line count (target: 20-30% reduction)
- [ ] Eliminated state synchronization bugs
- [ ] Consistent permission checking patterns
- [ ] Improved error message consistency
- [ ] Simplified call chains and dependencies

### Architecture Compliance
- [ ] Single responsibility principle maintained
- [ ] PermissionOracle centralization enforced
- [ ] Clean separation of concerns
- [ ] Proper observable object relationships
- [ ] Consistent async/await patterns

## Next Steps (Milestone 4+)

After manager consolidation, the unified KanataManager will be ready for:
- **Service extraction** (Configuration, Event Processing, etc.)
- **Protocol adoption** (LifecycleControlling, PermissionChecking, etc.)
- **Dependency injection** integration
- **Testing infrastructure** improvements

This consolidation creates the foundation for the remaining milestones while immediately reducing complexity and improving maintainability.