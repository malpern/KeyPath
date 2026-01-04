# KeyPath Codebase Refactoring Roadmap

**Status:** Ready to implement Phase 1
**Created:** 2026-01-03

## Executive Summary

The KeyPath codebase has grown organically and now contains several "God classes" exceeding 1,500+ lines, duplicated patterns, and inconsistent architectural approaches. This roadmap outlines a phased refactoring strategy to improve maintainability, testability, and developer experience.

---

## Phase 1: Quick Wins (Low Risk, High Impact)

### 1.1 Create `NotificationObserverManager` Helper
**Files affected:** 7+ ViewModels
**Risk:** Low

Extract duplicated observer pattern into reusable helper:

```swift
// New file: Sources/KeyPathAppKit/Utilities/NotificationObserverManager.swift
@MainActor
final class NotificationObserverManager {
    private var observers: [NSObjectProtocol] = []

    func observe(_ name: Notification.Name, handler: @escaping (Notification) -> Void) {
        let observer = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main, using: handler
        )
        observers.append(observer)
    }

    func removeAll() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}
```

**Migrate these files:**
- `KeyboardVisualizationViewModel.swift` (6 observers)
- `TypingSoundsManager.swift`
- `RecentKeypressesService.swift`
- `AppContextService.swift`
- `ContentView.swift`

### 1.2 Consolidate Key Display Formatting
**Files affected:** 2-3 files
**Risk:** Low

Create single source of truth for key display formatting:

```swift
// New file: Sources/KeyPathAppKit/Utilities/KeyDisplayFormatter.swift
enum KeyDisplayFormatter {
    static func format(_ key: String) -> String { ... }
    static func symbol(for key: String) -> String { ... }
}
```

**Remove duplicates from:**
- `MapperViewModel.swift:467-525` (formatKeyForDisplay)
- `KeyboardVisualizationViewModel.swift:274+` (tapHoldOutputDisplayLabel)

### 1.3 Track TODOs as Issues
**Risk:** None

Convert 21 TODO comments into GitHub issues with proper tracking.

---

## Phase 2: MapperViewModel Decomposition (Medium Risk, High Impact)

### Current State
`MapperViewModel.swift` - 1,764 lines with 15+ responsibilities

### Target Architecture

```
MapperViewModel (orchestrator, ~400 lines)
├── KeyInputRecorder (~200 lines)
│   └── Handles key capture, recording state, finalization
├── AdvancedBehaviorManager (~250 lines)
│   └── Hold/tap-dance/timing configuration
├── ActionSelector (~200 lines)
│   └── App launch, URL, system action selection
├── AppConditionManager (~150 lines)
│   └── Per-app precondition handling
└── KeyMappingFormatter (~100 lines)
    └── Kanata format conversion
```

### Implementation Steps

1. **Extract `KeyInputRecorder`**
   - Move lines 527-687 (recording logic)
   - Move `inputSequence`, `outputSequence`, `isRecordingInput/Output`
   - Keep reference in MapperViewModel

2. **Extract `AdvancedBehaviorManager`**
   - Move lines 256-301 (hold behavior, tap-dance state)
   - Move `holdAction`, `doubleTapAction`, `tappingTerm`, `tapDanceSteps`

3. **Extract `ActionSelector`**
   - Move lines 1299-1654 (app/URL/system selection)
   - Move `selectedApp`, `selectedSystemAction`, `selectedURL`

4. **Extract `AppConditionManager`**
   - Move lines 1377-1452 (per-app logic)
   - Move `selectedAppCondition`

5. **Extract `KeyMappingFormatter`**
   - Move lines 1720-1748 (Kanata conversion)
   - Move lines 467-525 (display formatting)

### Testing Strategy
- Create unit tests for each extracted component
- Integration test for MapperViewModel orchestration
- UI tests for full workflow

---

## Phase 3: ConfigurationService Decomposition (Medium Risk)

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

## Phase 4: View Decomposition (Higher Risk)

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

| Phase | Risk | Dependencies |
|-------|------|--------------|
| Phase 1 | Low | None |
| Phase 2 | Medium | Phase 1 |
| Phase 3 | Medium | None |
| Phase 4 | Higher | Phases 1-2 |
| Phase 5 | Medium | All above |
| Phase 6 | Low | None |

---

## Success Metrics

- No file exceeds 500 lines (target: 300-400)
- Each class has single responsibility
- 80%+ test coverage on extracted components
- Zero duplicated patterns
- All TODOs tracked as issues

---

## Files to Modify

### Phase 1
- Create: `Sources/KeyPathAppKit/Utilities/NotificationObserverManager.swift`
- Create: `Sources/KeyPathAppKit/Utilities/KeyDisplayFormatter.swift`
- Modify: `KeyboardVisualizationViewModel.swift`, `TypingSoundsManager.swift`, etc.

### Phase 2
- Create: `Sources/KeyPathAppKit/UI/Experimental/Mapper/KeyInputRecorder.swift`
- Create: `Sources/KeyPathAppKit/UI/Experimental/Mapper/AdvancedBehaviorManager.swift`
- Create: `Sources/KeyPathAppKit/UI/Experimental/Mapper/ActionSelector.swift`
- Create: `Sources/KeyPathAppKit/UI/Experimental/Mapper/AppConditionManager.swift`
- Create: `Sources/KeyPathAppKit/UI/Experimental/Mapper/KeyMappingFormatter.swift`
- Modify: `Sources/KeyPathAppKit/UI/Experimental/MapperViewModel.swift`

### Phase 3
- Create: `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationFileService.swift`
- Create: `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationParser.swift`
- Create: `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationValidator.swift`
- Create: `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationGenerator.swift`
- Modify: `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationService.swift`
