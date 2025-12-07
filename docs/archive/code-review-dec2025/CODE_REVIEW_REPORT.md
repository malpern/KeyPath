# KeyPath Code Review Report

**Date:** December 5, 2025
**Scope:** Comprehensive module-by-module review
**Focus Areas:** Structure, code quality, dead code, documentation, Swift patterns, architecture, API design

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Critical Issues](#critical-issues)
3. [Module-by-Module Analysis](#module-by-module-analysis)
   - [KeyPathCore](#keypathcore)
   - [KeyPathPermissions](#keypathpermissions)
   - [KeyPathDaemonLifecycle](#keypathdaemonlifecycle)
   - [KeyPathWizardCore](#keypathwizardcore)
   - [KeyPathHelper](#keypathhelper)
   - [KeyPathAppKit/Core](#keypathappkitcore)
   - [KeyPathAppKit/Services](#keypathappkitservices)
   - [KeyPathAppKit/Managers](#keypathappkitmanagers)
   - [KeyPathAppKit/InstallationWizard](#keypathappkitinstallationwizard)
   - [KeyPathAppKit/UI](#keypathappkitui)
4. [Cross-Cutting Concerns](#cross-cutting-concerns)
5. [Recommendations](#recommendations)

---

## Executive Summary

The KeyPath codebase shows clear signs of **organic growth** with several well-designed components alongside areas of significant technical debt. The codebase totals approximately **50,000+ lines** across 100+ Swift files.

### Overall Health: ⚠️ Moderate Concern

| Category | Rating | Notes |
|----------|--------|-------|
| **Architecture** | 🟡 Mixed | Good patterns (InstallerEngine façade, PermissionOracle) coexist with God classes |
| **Code Quality** | 🟡 Mixed | Some excellent code, some files need significant refactoring |
| **Swift Patterns** | 🟡 Mixed | Modern async/await usage, but Timer-based patterns and @unchecked Sendable |
| **Documentation** | 🟢 Good | CLAUDE.md is excellent; inline docs vary by module |
| **Test Coverage** | 🟢 Good | Test seams exist, KeyPathTestCase base class |
| **Dead Code** | 🟡 Mixed | Some deprecated methods, unused parameters |

### Key Metrics

- **God Classes (>1,000 lines):** 7 files requiring immediate attention
- **Critical Refactoring Needed:** 3 files (InstallationWizardView, RulesSummaryView, RuntimeCoordinator)
- **Estimated Technical Debt:** 40-60 hours of focused refactoring

---

## Critical Issues

### 🔴 Priority 1: God Classes Requiring Extraction

| File | Lines | Issue |
|------|-------|-------|
| `RulesSummaryView.swift` | 2,048 | 12 embedded View structs, mixed responsibilities |
| `InstallationWizardView.swift` | 1,774 | 40+ @State properties, business logic in view |
| `RuntimeCoordinator.swift` | 1,297 | Fragmented extensions, overlapping responsibilities |
| `KanataTCPClient.swift` | 1,215 | Connection + protocol + commands in one class |
| `HelperService.swift` | 1,078 | Acceptable for XPC helper scope |
| `WizardDesignSystem.swift` | 1,088 | Acceptable - cohesive design tokens |
| `PrivilegedOperationsCoordinator.swift` | 992 | Dual operation modes need separation |

### 🔴 Priority 2: Architecture Anti-Patterns

1. **3-Layer Process Abstraction**: `KanataService` → `ProcessCoordinator` → `RuntimeCoordinator` → `ProcessManager`
   - Each layer adds minimal value
   - Same operation traverses 3-4 classes
   - **Recommendation:** Collapse to 2 layers maximum

2. **Test Seams via Unsafe Statics**: Multiple uses of `nonisolated(unsafe) static var testXXX`
   - `VHIDDeviceManager.testPIDProvider`
   - `HelperManager.testXPCProvider`
   - **Recommendation:** Use proper dependency injection protocols

3. **Callback Explosion**: `RuleCollectionsManager` has 6 callback properties
   - `onCollectionsChanged`, `onCurrentCollectionChanged`, `onConfigurationError`, etc.
   - **Recommendation:** Use Combine publishers or AsyncStream

### 🔴 Priority 3: Swift Concurrency Issues

1. **@unchecked Sendable Usage**: 8+ occurrences across codebase
   - Masks potential data races
   - Often wrapping `Process` or `NSLock`

2. **Timer-Based Delays**: Should use `Task.sleep(for:)` instead of `Timer`
   - `RecordingCoordinator.swift`: Complex timer management
   - `ServiceHealthMonitor.swift`: Hardcoded timeouts

3. **Mixed Async/Sync Patterns**: Inconsistent use of `await` vs callbacks

---

## Module-by-Module Analysis

### KeyPathCore

**Size:** ~800 lines across 8 files
**Rating:** 🟢 Good

| File | Lines | Assessment |
|------|-------|------------|
| `KeyPathError.swift` | 150 | Clean error definitions |
| `FeatureFlags.swift` | 60 | Simple, effective |
| `KeyPathConstants.swift` | 120 | Well-organized constants |
| `Logger.swift` | 180 | Good structured logging |
| `TestEnvironment.swift` | 80 | Effective test isolation |
| `SubprocessRunner.swift` | 200 | Solid process execution |
| `WizardSystemPaths.swift` | 150 | Clear path management |
| `PrivilegedCommandRunner.swift` | 180 | Dual sudo/osascript approach |

**Strengths:**
- Clear single responsibilities
- Good error handling patterns
- Effective test isolation via `TestEnvironment`

**Issues:**
- `PrivilegedCommandRunner`: Dual sudo/osascript approach adds complexity
- Some error types could use `LocalizedError` conformance

**Dead Code:** None identified

---

### KeyPathPermissions

**Size:** ~400 lines (1 file)
**Rating:** 🟢 Excellent

| File | Lines | Assessment |
|------|-------|------------|
| `PermissionOracle.swift` | 400 | Single source of truth, well-documented |

**Strengths:**
- Clear architecture (Apple API → TCC fallback)
- Excellent documentation
- Proper singleton usage
- Good test seams

**Issues:**
- Minor: Some internal methods could be private

**Dead Code:** None

---

### KeyPathDaemonLifecycle

**Size:** ~600 lines across 4 files
**Rating:** 🟢 Good

| File | Lines | Assessment |
|------|-------|------------|
| `ProcessLifecycleManager.swift` | 200 | Clean state management |
| `LifecycleStateMachine.swift` | 180 | Clear state transitions |
| `PIDFileManager.swift` | 120 | Simple file operations |
| `LaunchDaemonPIDCache.swift` | 100 | Effective caching |

**Strengths:**
- Clear separation of concerns
- Well-defined state machine
- Good async patterns

**Issues:**
- `PIDFileManager`: Could use FileManager injection for testing

**Dead Code:** None

---

### KeyPathWizardCore

**Size:** ~400 lines across 3 files
**Rating:** 🟢 Good

| File | Lines | Assessment |
|------|-------|------------|
| `WizardTypes.swift` | 200 | Clean type definitions |
| `SystemSnapshot.swift` | 150 | Good value type design |
| `WizardStep.swift` | 50 | Simple enum |

**Strengths:**
- Value types for state
- Clear step progression model
- Good separation from UI

**Issues:**
- Some types could benefit from Codable conformance

**Dead Code:** None

---

### KeyPathHelper

**Size:** ~1,200 lines across 2 files
**Rating:** 🟡 Acceptable

| File | Lines | Assessment |
|------|-------|------------|
| `HelperService.swift` | 1,078 | Large but acceptable for XPC scope |
| `HelperProtocol.swift` | 118 | Well-documented protocol |

**Strengths:**
- Comprehensive XPC implementation
- Good security practices (signature validation)
- Extensive logging
- Clear method organization

**Issues:**
- **Deprecated methods kept for compatibility:**
  - `uninstallLaunchDaemon(daemonLabel:plistPath:)` - deprecated but retained
  - Some legacy code paths
- **Error handling:** Some methods return generic NSError

**Dead Code:**
- Deprecated XPC methods could be removed after migration period

**Documentation:** Good - protocol well-documented

---

### KeyPathAppKit/Core

**Size:** ~2,500 lines across 3 major files
**Rating:** 🟡 Needs Improvement

| File | Lines | Assessment |
|------|-------|------------|
| `PrivilegedOperationsCoordinator.swift` | 992 | Complex dual-mode logic |
| `HelperManager.swift` | 948 | Actor with XPC complexity |
| `HelperProtocol.swift` | 118 | Duplicate (see ADR-018) |

**Strengths:**
- Actor-based concurrency in HelperManager
- Good timeout handling
- Fallback mechanisms

**Issues:**

1. **PrivilegedOperationsCoordinator (992 lines):**
   - Dual operation modes (helper vs sudo) interleaved
   - Complex retry logic
   - **Recommendation:** Extract `HelperModeCoordinator` and `SudoModeCoordinator`

2. **HelperManager (948 lines):**
   - Test seams via `nonisolated(unsafe) static var`
   - Connection state management complexity
   - Version checking logic mixed with connection logic

3. **Protocol Duplication:**
   - `HelperProtocol.swift` exists in two locations (intentional per ADR-018)
   - Risk of divergence (mitigated by `HelperProtocolSyncTests`)

**Dead Code:**
- Some unused completion handler overloads

---

### KeyPathAppKit/Services

**Size:** ~4,500 lines across 8 files
**Rating:** 🟠 Needs Significant Work

| File | Lines | Assessment |
|------|-------|------------|
| `KanataTCPClient.swift` | 1,215 | 🔴 God class - needs extraction |
| `RuleCollectionsManager.swift` | 727 | 🔴 35+ methods, callback explosion |
| `DiagnosticsService.swift` | 677 | 🟠 18 methods, 5+ domains |
| `LayerKeyMapper.swift` | 643 | 🟡 Complex but focused |
| `SystemValidator.swift` | 593 | 🟡 Good validation logic |
| `MainAppStateController.swift` | 543 | 🟠 4 overlapping validation methods |
| `ConfigFileWatcher.swift` | 532 | 🟠 Atomic write handling bugs |
| `ServiceHealthMonitor.swift` | 485 | 🟡 Complex state machine |

**Critical Issues:**

1. **KanataTCPClient.swift (1,215 lines):**
   - Mixed responsibilities: connection lifecycle, protocol handling, command execution
   - Complex reconnection logic
   - **Recommendation:** Extract:
     - `TCPConnection` (connection management)
     - `KanataProtocol` (message parsing)
     - `KanataCommandExecutor` (command dispatch)

2. **RuleCollectionsManager.swift (727 lines):**
   - 35+ methods
   - 6 callback properties (`onCollectionsChanged`, `onCurrentCollectionChanged`, etc.)
   - Mixed async/sync patterns
   - **Recommendation:** Use Combine publishers, extract rule operations

3. **ConfigFileWatcher.swift (532 lines):**
   - `pendingAtomicWriteEvent` flag not cleared in all paths
   - Complex debouncing logic
   - **Bug:** Atomic write handling can miss events

4. **MainAppStateController.swift (543 lines):**
   - 4 validation methods with overlapping behavior
   - Unclear which to call when
   - **Recommendation:** Consolidate to single validation entry point

**Documentation Issues:**
- `KanataTCPClient`: Missing public API documentation
- Unclear callback contracts in `RuleCollectionsManager`

---

### KeyPathAppKit/Managers

**Size:** ~4,700 lines across 6 files
**Rating:** 🟠 Needs Significant Work

| File | Lines | Assessment |
|------|-------|------------|
| `RuntimeCoordinator.swift` | 1,297 | 🔴 God class, fragmented extensions |
| `KanataDaemonManager.swift` | 661 | 🟢 Cleanest manager |
| `ConfigurationManager.swift` | 426 | 🟠 Blurs with ConfigurationService |
| `ProcessManager.swift` | 247 | 🟠 Unused parameters, over-abstraction |
| `InstallationCoordinator.swift` | 171 | 🟠 Misleading success results |
| `ProcessCoordinator.swift` | 124 | 🔴 Unnecessary wrapper layer |

**Critical Issues:**

1. **RuntimeCoordinator.swift (1,297 lines):**
   - Fragmented across 5+ extension files
   - Overlaps with ProcessCoordinator responsibilities
   - Complex state management
   - **Recommendation:** Extract clear subsystems

2. **3-Layer Process Abstraction:**
   ```
   KanataService
       → ProcessCoordinator (124 lines - just delegates)
           → RuntimeCoordinator
               → ProcessManager (247 lines)
   ```
   - Each layer adds minimal value
   - **Recommendation:** Collapse to `KanataService` → `RuntimeCoordinator`

3. **ProcessManager.swift (247 lines):**
   - Unused `reason` parameter in multiple methods
   - Over-abstracted for simple operations

4. **InstallationCoordinator.swift (171 lines):**
   - Returns success even when operations partially fail
   - Misleading error handling

**Dead Code:**
- `ProcessCoordinator` largely redundant
- Unused parameters in `ProcessManager`

---

### KeyPathAppKit/InstallationWizard

**Size:** ~6,500 lines across 8 files
**Rating:** 🟡 Mixed

| File | Lines | Assessment |
|------|-------|------------|
| `InstallationWizardView.swift` | 1,774 | 🔴 CRITICAL - 40+ @State |
| `WizardDesignSystem.swift` | 1,088 | 🟢 Clean, cohesive |
| `ServiceBootstrapper.swift` | 834 | 🟠 Mixed responsibilities |
| `WizardAsyncOperationManager.swift` | 713 | 🟢 Well-designed |
| `PackageManager.swift` | 712 | 🟠 Cache issues |
| `InstallerEngine.swift` | 691 | 🟢 Good façade pattern |
| `VHIDDeviceManager.swift` | 645 | 🟠 Test seam concerns |
| `IssueGenerator.swift` | 492 | 🟡 Data coupling |

**Critical Issues:**

1. **InstallationWizardView.swift (1,774 lines):**
   - **40+ @State properties** - violates SwiftUI best practices
   - Business logic mixed with view code
   - Should be max 200-300 lines
   - **Recommendation:** Extract:
     - `WizardViewModel` (all state management)
     - `WizardStepViews/` directory (individual step views)
     - Keep `InstallationWizardView` as thin coordinator

2. **ServiceBootstrapper.swift (834 lines):**
   - Handles installation, repair, and uninstallation
   - Single responsibility violated
   - **Recommendation:** Should delegate to `InstallerEngine`

3. **VHIDDeviceManager.swift (645 lines):**
   - Test seams via static properties instead of DI
   - Complex retry logic with hardcoded delays
   - **Note:** ADR-021 documents why delays are intentional (11s total)

**Strengths:**
- `InstallerEngine.swift`: Excellent façade pattern
- `WizardDesignSystem.swift`: Clean, reusable design tokens
- `WizardAsyncOperationManager.swift`: Good async operation handling

---

### KeyPathAppKit/UI

**Size:** ~19,610 lines across 49 files
**Rating:** 🟠 Needs Work

#### Critical Files

| File | Lines | Assessment |
|------|-------|------------|
| `RulesSummaryView.swift` | 2,048 | 🔴 CRITICAL - needs extraction |
| `MapperView.swift` | 1,704 | 🟠 Oversized but reasonable |
| `ContentView.swift` | 920 | 🟠 Lifecycle complexity |
| `KeyboardVisualizationViewModel.swift` | 799 | 🟠 Complex event handling |
| `OverlayKeycapView.swift` | 778 | 🟡 Well-structured |
| `SettingsView.swift` | 741 | 🟢 Good structure |
| `SimpleModsView.swift` | 691 | 🟠 State duplication |
| `RecordingCoordinator.swift` | 688 | 🟠 Timer complexity |

**Critical Issues:**

1. **RulesSummaryView.swift (2,048 lines):**
   - 12 embedded View structs
   - Mixed presentation and logic
   - **Recommendation:** Extract into 4-5 separate files:
     - `RulesSummaryView.swift` (coordinator, ~200 lines)
     - `RuleCollectionCard.swift`
     - `RuleDetailSheet.swift`
     - `RuleSummaryRow.swift`
     - `RulesSummaryViewModel.swift`

2. **ContentView.swift (920 lines):**
   - 10+ `.onReceive` handlers
   - 3+ `.onChange` handlers
   - Complex lifecycle management
   - **Recommendation:** Extract event handling to ViewModel

3. **Toast Manager Duplication:**
   - 4+ files implement their own toast/notification logic
   - **Recommendation:** Create shared `ToastManager` service

4. **Permission Checking Inconsistency:**
   - Different files check permissions differently
   - Some bypass `PermissionOracle`
   - **Recommendation:** Audit and consolidate through Oracle

**SwiftUI Anti-Patterns:**
- Excessive `@State` in views (should be in ViewModels)
- Business logic in view bodies
- Missing `@ViewBuilder` extraction for complex conditionals

**Good Examples:**
- `SettingsView.swift`: Clean structure, good separation
- `WizardDesignSystem.swift`: Cohesive design tokens
- `OverlayKeycapView.swift`: Well-structured despite size

---

## Cross-Cutting Concerns

### 1. Concurrency

**Issues:**
- `@unchecked Sendable` used to bypass compiler checks (8+ occurrences)
- Mixed Timer and async/await patterns
- Some `DispatchQueue.main.async` instead of `@MainActor`

**Recommendations:**
- Audit all `@unchecked Sendable` usages
- Replace Timer with `Task.sleep(for:)`
- Use `@MainActor` consistently for UI updates

### 2. Error Handling

**Issues:**
- Inconsistent error types (some `NSError`, some custom errors)
- Some methods swallow errors silently
- Error messages not always user-friendly

**Recommendations:**
- Standardize on `KeyPathError` where possible
- Add `LocalizedError` conformance
- Log all errors, even when recovered

### 3. Testing

**Strengths:**
- `KeyPathTestCase` base class
- Test seams exist throughout
- Good use of `TestEnvironment`

**Issues:**
- Test seams via `nonisolated(unsafe) static var` instead of DI
- Some test pollution between tests

**Recommendations:**
- Migrate to protocol-based DI for major components
- Document test seam usage patterns

### 4. Documentation

**Strengths:**
- Excellent `CLAUDE.md` with ADRs
- Good protocol documentation
- Test naming conventions

**Issues:**
- Public API documentation spotty
- Some complex methods lack explanations
- Inline comments sometimes stale

---

## Recommendations

### Immediate Actions (1-2 weeks)

1. **Extract InstallationWizardView state** to `WizardViewModel`
   - Reduces 40+ @State to ~5
   - Enables proper testing
   - Estimated: 4-6 hours

2. **Split RulesSummaryView** into 4-5 files
   - Improves maintainability
   - Enables focused testing
   - Estimated: 3-4 hours

3. **Fix ConfigFileWatcher atomic write bug**
   - Clear `pendingAtomicWriteEvent` in all code paths
   - Add tests for atomic write scenarios
   - Estimated: 1-2 hours

### Short-Term (1 month)

4. **Extract KanataTCPClient responsibilities**
   - `TCPConnection`, `KanataProtocol`, `KanataCommandExecutor`
   - Estimated: 6-8 hours

5. **Collapse process abstraction layers**
   - Remove `ProcessCoordinator` wrapper
   - Simplify `KanataService` → `RuntimeCoordinator` path
   - Estimated: 4-6 hours

6. **Create shared ToastManager**
   - Consolidate 4+ toast implementations
   - Estimated: 2-3 hours

### Medium-Term (3 months)

7. **Audit @unchecked Sendable usage**
   - Replace with proper actor isolation where possible
   - Document remaining cases

8. **Standardize error handling**
   - Migrate to `KeyPathError` throughout
   - Add `LocalizedError` conformance

9. **Replace Timer patterns with Task.sleep**
   - Modernize async patterns
   - Improve testability

### Long-Term Considerations

10. **Protocol-based dependency injection**
    - Replace static test seams with injected protocols
    - Improves testability and modularity

11. **Consider module extraction**
    - `KeyPathTCP` module for all TCP communication
    - `KeyPathRules` module for rule management

---

## Appendix: File Size Distribution

### Files > 1,000 Lines (Requiring Attention)

```
2,048  RulesSummaryView.swift          🔴 Extract
1,774  InstallationWizardView.swift    🔴 Extract
1,704  MapperView.swift                🟠 Monitor
1,297  RuntimeCoordinator.swift        🔴 Refactor
1,215  KanataTCPClient.swift           🔴 Extract
1,088  WizardDesignSystem.swift        🟢 OK (cohesive)
1,078  HelperService.swift             🟢 OK (XPC scope)
 992   PrivilegedOperationsCoordinator 🟠 Consider split
 948   HelperManager.swift             🟡 Monitor
```

### Module Size Summary

| Module | Lines | Files | Avg/File |
|--------|-------|-------|----------|
| UI | 19,610 | 49 | 400 |
| InstallationWizard | 6,500 | 8 | 812 |
| Services | 4,500 | 8 | 562 |
| Managers | 4,700 | 6 | 783 |
| Core | 2,500 | 3 | 833 |
| Helper | 1,200 | 2 | 600 |
| KeyPathCore | 800 | 8 | 100 |
| DaemonLifecycle | 600 | 4 | 150 |
| Permissions | 400 | 1 | 400 |
| WizardCore | 400 | 3 | 133 |

**Total: ~41,210 lines** (excludes tests)

---

*Report generated by Claude Code review - December 5, 2025*
