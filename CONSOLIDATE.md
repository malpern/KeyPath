# Wizard Architecture Consolidation Plan

## Problem Analysis

The Installation Wizard currently has **dual detection architectures** created simultaneously on August 9, 2025:

1. **SystemStatusChecker** (ACTIVE) - Used by WizardStateManager
2. **SystemStateDetector** (DEAD CODE) - Not used anywhere in UI

This duplication causes:
- Permission detection bugs (current issue)
- Code confusion and maintenance burden
- Inconsistent detection results
- Performance overhead from redundant checks

## Git History Evidence

```
August 9, 2025 (e603deab): Both systems created simultaneously
August 14, 2025 (bb65af2): SystemStateDetector enhanced (unused)
August 15, 2025 (a4f6a97): SystemStatusChecker enhanced (active)
```

**SystemStatusChecker comment explicitly states**: "Replaces: ComponentDetector, SystemHealthChecker, SystemRequirements, SystemStateDetector"

## Current Usage Analysis

### SystemStatusChecker (✅ KEEP)
- **Used by**: WizardStateManager → InstallationWizardView
- **Features**: Unified detection, functional verification, TCC checking
- **Status**: Actively maintained, recently enhanced
- **Architecture**: Single class handles all detection

### SystemStateDetector (❌ REMOVE)  
- **Used by**: NOWHERE (dead code)
- **Features**: Orchestration layer over multiple detectors
- **Status**: Unused, only has tests
- **Architecture**: Complex orchestration with multiple dependencies

## Consolidation Plan

### Phase 1: Remove Dead Code (IMMEDIATE)

#### Files to Delete
```
Sources/KeyPath/InstallationWizard/Core/SystemStateDetector.swift
Sources/KeyPath/InstallationWizard/Core/ComponentDetector.swift
Sources/KeyPath/InstallationWizard/Core/SystemHealthChecker.swift
Tests/KeyPathTests/SystemStateDetectorTests.swift
```

#### Rationale
- **SystemStateDetector**: Dead code, not used anywhere
- **ComponentDetector**: Logic duplicated in SystemStatusChecker
- **SystemHealthChecker**: Functionality moved to SystemStatusChecker
- **Tests**: Testing unused code

### Phase 2: Consolidate Logic (IMMEDIATE)

#### Extract Useful Patterns Before Deletion

From **SystemStateDetector**:
- Debouncing logic for state changes (prevents UI flicker)
- Orphaned process detection patterns
- Better error aggregation methods

From **ComponentDetector**:
- Any unique permission checking logic not in SystemStatusChecker
- Component detection patterns

#### Integration Tasks
1. Move debouncing logic to SystemStatusChecker
2. Integrate orphaned process detection
3. Consolidate any unique component checking logic
4. Update SystemStatusChecker to be the single source of truth

### Phase 3: Architectural Cleanup (HIGH PRIORITY)

#### Simplify State Management
- Remove unused protocols (SystemStateDetecting)
- Simplify WizardStateManager (direct SystemStatusChecker dependency)
- Clean up wizard component interfaces

#### Improve Detection Pipeline
- Single detection path through SystemStatusChecker
- Consistent error handling and logging
- Optimized caching and performance

### Phase 4: Testing & Validation (MEDIUM TERM)

#### Test Consolidation
- Move useful tests from SystemStateDetectorTests to SystemStatusCheckerTests
- Add integration tests for consolidated system
- Validate permission detection works correctly

#### Documentation Updates
- Update architecture documentation
- Remove references to deleted components
- Document simplified detection flow

## Benefits of Consolidation

### Immediate Benefits
- **Fixes current permission detection bug** (single detection path)
- **Eliminates confusion** about which system is authoritative
- **Improves performance** (no redundant checks)
- **Simplifies debugging** (single code path to trace)

### Long-term Benefits
- **Easier maintenance** (single detection system)
- **Prevents future bugs** (no inconsistent implementations)
- **Better testability** (focused test suite)
- **Cleaner architecture** (clear separation of concerns)

## Implementation Notes

### Current Issue Context
The kanata Input Monitoring permission detection issue is likely caused by:
- Multiple detection paths with different logic
- Inconsistent TCC database checking
- Confidence level filtering in wrong system

### Post-Consolidation
- Single detection path through SystemStatusChecker
- Consistent TCC checking with proper logging
- Clear permission state management

## Validation Checklist

After consolidation:
- [ ] Wizard uses only SystemStatusChecker
- [ ] No references to deleted components
- [ ] Permission detection works correctly
- [ ] All tests pass
- [ ] Performance improved (no redundant checks)
- [ ] Clean architecture with single detection pipeline

## Files Affected

### Deletions
- `Sources/KeyPath/InstallationWizard/Core/SystemStateDetector.swift`
- `Sources/KeyPath/InstallationWizard/Core/ComponentDetector.swift`
- `Sources/KeyPath/InstallationWizard/Core/SystemHealthChecker.swift`
- `Tests/KeyPathTests/SystemStateDetectorTests.swift`

### Updates
- `Sources/KeyPath/InstallationWizard/Core/SystemStatusChecker.swift` (integrate useful patterns)
- `Sources/KeyPath/InstallationWizard/UI/InstallationWizardView.swift` (simplify state management)
- `Sources/KeyPath/InstallationWizard/Core/WizardTypes.swift` (remove unused protocols)

## Success Metrics

1. **Code Reduction**: ~1000+ lines of duplicate code removed
2. **Performance**: Single detection pipeline, no redundant checks
3. **Maintainability**: Clear single source of truth for detection
4. **Bug Resolution**: Current permission detection issue resolved
5. **Architecture**: Clean, simple, and focused wizard system

