# KeyPath Codebase Refactoring Roadmap

**Status:** Phase 1 ✅ Complete | Phase 2 ✅ Complete | Phase 3+ Pending
**Created:** 2026-01-03
**Last Updated:** 2026-01-03

## Executive Summary

The KeyPath codebase has grown organically and now contains several "God classes" exceeding 1,500+ lines, duplicated patterns, and inconsistent architectural approaches. This roadmap outlines a phased refactoring strategy to improve maintainability, testability, and developer experience.

---

## Phase 1: Quick Wins ✅ COMPLETE

### 1.1 NotificationObserverManager ✅

**Created:** `Sources/KeyPathAppKit/Utilities/NotificationObserverManager.swift` (138 lines)

Reusable helper for notification observer lifecycle management:
- Automatic cleanup on deallocation
- Support for multiple NotificationCenters
- Thread-safe observer storage

**Migrated:**
- ✅ `RecentKeypressesService.swift`
- ✅ `AppContextService.swift`
- ✅ `ActivityLogger.swift`

### 1.2 KeyDisplayFormatter ✅

**Created:** `Sources/KeyPathAppKit/Utilities/KeyDisplayFormatter.swift` (215 lines)

Single source of truth for key display formatting:
- `symbol(for:)` - Get symbol for kanata key name
- `format(_:)` - Format key for display
- `tapHoldLabel(for:)` - Format tap-hold output labels

**Consolidated from:**
- ✅ `MapperViewModel.formatKeyForDisplay`
- ✅ `KeyboardVisualizationViewModel.tapHoldOutputDisplayLabel`

### 1.3 Track TODOs as Issues

🔜 Pending - Convert TODO comments to GitHub issues

---

## Phase 2: MapperViewModel Decomposition ✅ COMPLETE

### Results

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| MapperViewModel.swift | 1,764 lines | 1,555 lines | **-209 lines (-12%)** |

### Extracted Components

| Component | Lines | Purpose | Status |
|-----------|-------|---------|--------|
| `AdvancedBehaviorManager.swift` | 208 | Hold behavior, tap-dance, timing, conflict detection | ✅ |
| `MapperActionTypes.swift` | 123 | AppLaunchInfo, SystemActionInfo, AppConditionInfo | ✅ |
| `AppConditionManager.swift` | 123 | Per-app precondition picker and state | ✅ |
| `KeyMappingFormatter.swift` | 78 | Kanata format conversion utilities | ✅ |
| **Total Mapper/** | **532** | | |

### Architecture

```
MapperViewModel (orchestrator, 1,555 lines)
├── AdvancedBehaviorManager (208 lines) ✅
│   └── Hold/tap-dance/timing configuration
├── AppConditionManager (123 lines) ✅
│   └── Per-app precondition handling
├── MapperActionTypes (123 lines) ✅
│   └── Data types for app/system/URL actions
├── KeyMappingFormatter (78 lines) ✅
│   └── Kanata format conversion
└── KeyInputRecorder (~200 lines) 🔜
    └── Key capture, recording state (deferred - tightly coupled)
```

### Implementation Pattern

Used **legacy accessor pattern** for backward compatibility:

```swift
// MapperViewModel delegates to extracted managers
@Published var advancedBehavior = AdvancedBehaviorManager()

// Legacy accessor for backward compatibility
var holdAction: String {
    get { advancedBehavior.holdAction }
    set { advancedBehavior.holdAction = newValue }
}
```

### Deferred: KeyInputRecorder

The key recording logic is tightly coupled to UI state and requires more extensive refactoring. Deferred to future work.

---

## Phase 3: ConfigurationService Decomposition (Pending)

### Current State
`ConfigurationService.swift` - 2,155 lines handling I/O, parsing, validation, generation

### Target Architecture

```
ConfigurationRepository (facade, ~200 lines)
├── ConfigurationFileService (~300 lines)
│   └── Pure I/O: read, write, backup, restore
├── ConfigurationParser (~400 lines)
│   └── Parse .kbd files, extract rules
├── ConfigurationValidator (~200 lines)
│   └── Validate configurations, detect conflicts
└── ConfigurationGenerator (~400 lines)
    └── Generate Kanata config from rules
```

### Benefits
- Testable in isolation (mock file system)
- Clear separation of concerns
- Easier to add new config formats

---

## Phase 4: View Decomposition (Pending)

### Target Files
1. `RulesSummaryView.swift` (3,571 lines)
2. `OverlayKeycapView.swift` (1,985 lines)
3. `InstallationWizardView.swift` (1,849 lines)
4. `SettingsView.swift` (1,757 lines)

### Approach
Extract logical sections into child views:

```swift
// Before: One massive view
struct RulesSummaryView: View {
    var body: some View {
        // 3,571 lines of mixed concerns
    }
}

// After: Composed child views
struct RulesSummaryView: View {
    var body: some View {
        VStack {
            RulesSummaryHeader()
            ActiveRulesSection()
            AvailableRulesSection()
            ConflictResolutionSection()
        }
    }
}
```

---

## Phase 5: State Management Unification (Lower Priority)

### Problem
- `RuntimeCoordinator` uses `StatePublisherService`
- ViewModels use `@Published` directly
- Inconsistent patterns

### Options
1. **Standardize on `@Published`** - Simpler, SwiftUI native
2. **Standardize on `StatePublisherService`** - More testable
3. **Adopt Observation framework** (iOS 17+) - Modern approach

### Recommendation
Wait for broader iOS 17+ adoption, then migrate to `@Observable` macro.

---

## Phase 6: Structured Concurrency Cleanup

### Problem
Manual task management with memory leak risks:
```swift
private var fadeOutTasks: [UInt16: Task<Void, Never>] = [:]
```

### Solution
Use `TaskGroup` or `withTaskCancellationHandler` patterns.

---

## Implementation Summary

| Phase | Status | Risk | Dependencies |
|-------|--------|------|--------------|
| Phase 1 | ✅ Complete | Low | None |
| Phase 2 | ✅ Complete | Medium | Phase 1 |
| Phase 3 | 🔜 Pending | Medium | None |
| Phase 4 | 🔜 Pending | Higher | Phases 1-2 |
| Phase 5 | 🔜 Pending | Medium | All above |
| Phase 6 | 🔜 Pending | Low | None |

---

## Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Max file size | 500 lines | MapperViewModel: 1,555 ⚠️ |
| Single responsibility | Yes | Improved ✅ |
| Test coverage on extracted | 80%+ | Pending |
| Duplicated patterns | Zero | Reduced ✅ |
| TODOs tracked as issues | All | Pending |

---

## Commits (Phase 1 & 2)

```
fb269698 Refactor: Extract KeyMappingFormatter utility
65738b40 Refactor: Extract AppConditionManager from MapperViewModel
6b5fa297 Refactor: Extract Mapper action types to separate file
0e191ccf Refactor: Extract AdvancedBehaviorManager from MapperViewModel
877ed237 Phase 1.2: Add KeyDisplayFormatter utility
31ce808c Phase 1.1: Add NotificationObserverManager utility
edfbbed9 Add activity logging infrastructure and refactoring roadmap
```

---

## Files Created

### Phase 1 - Utilities
- `Sources/KeyPathAppKit/Utilities/NotificationObserverManager.swift`
- `Sources/KeyPathAppKit/Utilities/KeyDisplayFormatter.swift`

### Phase 2 - Mapper Components
- `Sources/KeyPathAppKit/UI/Experimental/Mapper/AdvancedBehaviorManager.swift`
- `Sources/KeyPathAppKit/UI/Experimental/Mapper/MapperActionTypes.swift`
- `Sources/KeyPathAppKit/UI/Experimental/Mapper/AppConditionManager.swift`
- `Sources/KeyPathAppKit/UI/Experimental/Mapper/KeyMappingFormatter.swift`

### Phase 3 (Planned)
- `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationFileService.swift`
- `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationParser.swift`
- `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationValidator.swift`
- `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationGenerator.swift`
