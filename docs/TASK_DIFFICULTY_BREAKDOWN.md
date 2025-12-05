# Task Difficulty Breakdown - Mechanical vs. Complex Refactoring

## Overview

The 53 issues identified in the comprehensive review fall into two categories:

1. **MECHANICAL TASKS** - Straightforward replacements, minimal thinking required
2. **COMPLEX REFACTORING** - Requires careful planning, architectural decisions, thorough testing

This document separates them clearly so you can tackle quick wins first, then schedule complex work.

---

## 🟢 MECHANICAL TASKS (28 issues, 12-14 hours)

These are safe, repeatable changes with clear patterns. Low risk, high impact.

### Category 1: Task.sleep(nanoseconds:) → Task.sleep(for:)
**Difficulty:** 🟢 EASY | **Effort:** 1 hour | **Files:** 17 | **Instances:** 35

**Why it's mechanical:**
- Exact same pattern everywhere
- Pure string replacement with math conversion
- No side effects or behavioral changes
- Easy to verify correctness

**Files to modify:**

**Services Layer (30 instances, 12 files):**
```
Sources/KeyPathAppKit/Services/
  ├─ KanataTCPClient.swift (8 instances)
  ├─ KanataService.swift (4 instances)
  ├─ SimpleModsService.swift (3 instances)
  ├─ KarabinerConflictService.swift (2 instances)
  ├─ KanataErrorMonitor.swift (1 instance)
  ├─ KanataEventListener.swift (2 instances)
  ├─ MainAppStateController.swift (2 instances)
  ├─ ConfigFileWatcher.swift (2 instances)
  ├─ SafetyTimeoutService.swift (1 instance)
  ├─ PermissionGate.swift (2 instances)
  ├─ PermissionRequestService.swift (1 instance)
  └─ ServiceHealthMonitor.swift (1 instance)
```

**Core/Infrastructure (5 instances, 2 files):**
```
  ├─ PrivilegedOperationsCoordinator.swift (4 instances: lines 589, 594, 834, 877)
  └─ ConfigurationService.swift (1 instance: line 1052)
```

**UI Layer (2 instances, 2 files):**
```
  ├─ ContentView.swift (1 instance: line 692)
  └─ KanataViewModel.swift (1 instance: line 339)
```

**Pattern to replace:**
```swift
// CONVERSION FORMULA: nanoseconds ÷ 1,000,000,000 = seconds OR ÷ 1,000,000 = milliseconds

// Examples:
// 500,000,000 ns → 0.5 sec → .milliseconds(500)
// 1,000,000,000 ns → 1 sec → .seconds(1)
// 3,000,000,000 ns → 3 sec → .seconds(3)

// Replace: Task.sleep(nanoseconds: UInt64(X * 1_000_000_000))
// With: Task.sleep(for: .seconds(X))

// Replace: Task.sleep(nanoseconds: 500_000_000)
// With: Task.sleep(for: .milliseconds(500))
```

**Implementation steps:**
1. Find line with `Task.sleep(nanoseconds:`
2. Calculate duration value
3. Replace with `Task.sleep(for:)`
4. Test with `swift test`

**Verification:** All tests pass, no behavioral changes

---

### Category 2: DispatchQueue.main.async → async/await
**Difficulty:** 🟡 MODERATE-EASY | **Effort:** 2-3 hours | **Files:** 6 | **Instances:** 8

**Why it's mostly mechanical (with context):**
- Consistent pattern across files
- Clear mapping: `DispatchQueue.main.async {}` → `Task { @MainActor in }`
- For delayed dispatch: combine with `Task.sleep`

**Files to modify:**

**Services (6 instances, 5 files):**
```
Sources/KeyPathAppKit/Services/
  ├─ ConfigHotReloadService.swift (1 instance: line 207) - asyncAfter with delay
  ├─ KeyboardCapture.swift (4 instances: lines 396, 400, 464, 692)
  ├─ KarabinerConflictService.swift (1 instance: line 277)
  ├─ SystemRequirementsChecker.swift (1 instance: line 184) - asyncAfter with delay
  ├─ ActionDispatcher.swift (1 instance: line 368) - asyncAfter with delay
  └─ UserNotificationService.swift (1 instance: line 257)
```

**Patterns:**

Pattern 1 - Simple main thread call:
```swift
// OLD
DispatchQueue.main.async {
    self.callback()
}

// NEW (if already @MainActor)
callback()

// OR (if in async context)
Task { @MainActor in
    callback()
}
```

Pattern 2 - Delayed execution:
```swift
// OLD
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    self.callback()
}

// NEW
Task { @MainActor in
    try await Task.sleep(for: .milliseconds(500))
    callback()
}
```

Pattern 3 - With weak self:
```swift
// OLD
DispatchQueue.main.async { [weak self] in
    self?.updateUI()
}

// NEW
Task { @MainActor in
    updateUI()  // self is implicit
}
```

**Implementation steps:**
1. Find `DispatchQueue.main.async` or `asyncAfter`
2. Check if it has a delay
3. Apply appropriate pattern
4. Test with `swift test`

**Verification:** All tests pass, callback behavior identical

---

### Category 3: onTapGesture → Button
**Difficulty:** 🟡 MODERATE-EASY | **Effort:** 1-2 hours | **Files:** 12 | **Instances:** 12

**Why it's mechanical:**
- Straightforward view replacement
- Same action closure
- Just need to wrap in Button

**Files to modify:**
Scattered across UI layer. Use Xcode Find to locate all `onTapGesture` instances.

**Patterns:**

Pattern 1 - Image + Text:
```swift
// OLD
HStack {
    Image(systemName: "heart")
    Text("Like")
}
.onTapGesture {
    toggleLike()
}

// NEW
Button(action: toggleLike) {
    Label("Like", systemImage: "heart")
}
```

Pattern 2 - Custom styling needed:
```swift
// OLD
HStack {
    Image(systemName: "heart")
    Text("Like")
}
.onTapGesture {
    toggleLike()
}

// NEW
Button(action: toggleLike) {
    HStack {
        Image(systemName: "heart")
        Text("Like")
    }
}
.buttonStyle(.plain)  // Preserve custom styling if needed
```

Pattern 3 - Icon only:
```swift
// OLD
Image(systemName: "trash")
    .onTapGesture { delete() }

// NEW
Button(action: delete) {
    Label("Delete", systemImage: "trash")
}
```

**Implementation steps:**
1. Find `onTapGesture` in code
2. Extract the closure action
3. Create Button with same action
4. Test VoiceOver with Accessibility Inspector
5. Commit

**Verification:** VoiceOver reads the label, keyboard navigation works

---

### Category 4: Add Accessibility Labels
**Difficulty:** 🟢 EASY | **Effort:** 1-2 hours | **Files:** 8-12 | **Instances:** 15-20

**Why it's mechanical:**
- Simple modifier addition
- No behavioral changes
- Just add descriptive text

**Pattern:**
```swift
// Missing label - icon only
Button(action: delete) {
    Image(systemName: "trash")
}

// Fixed - with accessibility label
Button(action: delete) {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete item")

// OR - Better: use Label
Button(action: delete) {
    Label("Delete", systemImage: "trash")
}
```

**Implementation steps:**
1. Find all icon-only buttons (use Xcode search)
2. Add `.accessibilityLabel("descriptive text")` OR convert to `Label`
3. Test with VoiceOver
4. Commit

**Verification:** VoiceOver announces the button purpose

---

### Category 5: Model Validation Addition
**Difficulty:** 🟡 MODERATE-EASY | **Effort:** 2-3 hours | **Files:** 4 | **Instances:** 4 models

**Why it's mostly mechanical:**
- Same validation pattern for each model
- Clear validation rules
- No existing validation to work around

**Files to modify:**
```
Sources/KeyPathAppKit/Models/
  ├─ KeyMapping.swift
  ├─ CustomRule.swift
  ├─ RuleCollection.swift
  └─ DualRoleBehavior.swift
```

**Pattern:**
```swift
// Add to each model:
public func validate() throws -> Void {
    guard !input.isEmpty else { throw ValidationError.emptyInput }
    guard !output.isEmpty else { throw ValidationError.emptyOutput }
    guard !title.isEmpty else { throw ValidationError.emptyTitle }
}

// Create validation error enum
enum ValidationError: LocalizedError {
    case emptyInput
    case emptyOutput
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "Input cannot be empty"
        case .emptyOutput: return "Output cannot be empty"
        case .emptyTitle: return "Title cannot be empty"
        }
    }
}
```

**Implementation steps:**
1. Create ValidationError enum
2. Add validate() method to each model
3. Call validate() in factory functions
4. Test with invalid inputs
5. Commit

**Verification:** Invalid models throw ValidationError

---

## 🟡 MODERATELY COMPLEX TASKS (13 issues, 15-20 hours)

These require some thinking but have clear scope and patterns. Medium risk.

### Category 6: ~~Fix @unchecked Sendable Concurrency Issues~~ ✅ RESOLVED - Documented as Legitimate
**Difficulty:** 🟢 RESOLVED | **Effort:** 1 hour (documentation) | **Files:** 1 | **Instances:** 2

**Status: December 2025 - CANNOT BE ELIMINATED**

After attempting to refactor with `withTaskGroup`, Swift 6's strict concurrency checking reveals these `@unchecked Sendable` usages are **legitimate and necessary**:

**Why structured concurrency doesn't work here:**
1. XPC proxy objects (`HelperProtocol`) are NOT Sendable in Swift 6
2. `withTaskGroup` requires captured values to be Sendable
3. We must capture the proxy to call XPC methods
4. Attempting `group.addTask { proxy.getVersion... }` fails with:
   ```
   error: passing closure as a 'sending' parameter risks causing data races
   closure captures 'proxy' which is accessible to code in the current task
   ```

**Why the current pattern is correct:**
- `VersionHolder`: Single writer (XPC callback), single reader (timeout path)
- `CompletionState`: NSLock guards boolean for atomic try-complete between two racers
- Both are standard patterns for callback→async bridge with timeout
- Thread safety is guaranteed by the implementation

**Files documented:**
```
Sources/KeyPathAppKit/Core/HelperManager.swift
  ├─ Line 238: VersionHolder class - documented with MARK comment
  └─ Line 661: CompletionState class - documented with MARK comment
```

**Resolution:**
- Added comprehensive MARK comments explaining why @unchecked Sendable is required
- Referenced Swift Forums discussion on Sendable + Objective-C types
- No code changes needed - pattern is already correct

**Verification:** ✅
- Build passes with Swift 6.2
- All 181 tests pass
- Documentation explains the legitimate use case

---

### Category 7: ~~Simplify XPC Error Handling~~ ✅ RESOLVED - Already Optimal
**Difficulty:** 🟢 RESOLVED | **Effort:** 0 hours (no changes needed) | **File:** 1 | **Location:** HelperManager.swift:632-699

**Status: December 2025 - ALREADY OPTIMAL GIVEN CONSTRAINTS**

After analysis, the suggested structured concurrency refactoring **cannot work** (see Category 6). The current implementation uses the **minimal required primitives**:

**Actual pattern (not "4+ primitives mixed together"):**
1. `CompletionState` with NSLock - **Required** for race detection between callback vs timeout
2. `DispatchQueue.global().asyncAfter` - **Required** for timeout scheduling (can't use Task.sleep with non-Sendable proxy)
3. `withCheckedThrowingContinuation` - **Required** for callback→async bridging

**Why structured concurrency won't work:**
- XPC proxy objects are NOT Sendable
- `withThrowingTaskGroup` requires Sendable captured values
- Therefore, we can't use task groups for timeout with XPC

**What WAS done:**
- Added comprehensive documentation explaining why the pattern is necessary
- Documented the thread safety guarantees (CompletionState's NSLock)
- The code is clear, well-documented, and ~67 lines

**Verification:** ✅
- Code reviewed and documented in Category 6 work
- All 181 tests pass
- No refactoring needed - pattern is already correct

---

### Category 8: ~~HelperManager State Machine Documentation~~ ✅ COMPLETE
**Difficulty:** 🟢 COMPLETE | **Effort:** 1 hour | **File:** 1 | **Size:** ~1000 lines

**Status: December 2025 - DOCUMENTATION COMPLETE**

The state machine was already partially implemented (`HealthState` enum existed). Added comprehensive documentation:

**What was done:**
1. **Enhanced file-level doc comment** with ASCII art state diagram:
   ```
   notInstalled → requiresApproval → registeredButUnresponsive → healthy
   ```
2. **Documented state determination algorithm** (4 priority-ordered steps)
3. **Added recovery strategies** for each state
4. **Documented XPC timeout strategy**
5. **Added doc comments to `HealthState` enum cases**
6. **Enhanced `getHelperHealth()` with detailed step comments**

**Files modified:**
```
Sources/KeyPathAppKit/Core/HelperManager.swift
  ├─ Lines 6-54: Comprehensive type-level documentation
  ├─ Lines 58-71: HealthState enum with case documentation
  └─ Lines 599-634: getHelperHealth() with step comments
```

**Key insight:** The state machine was already correctly implemented - it just needed documentation. The `HealthState` enum already had the right cases:
- `notInstalled` - Helper not found
- `requiresApproval` - Needs System Settings approval
- `registeredButUnresponsive` - XPC communication failing
- `healthy` - Working correctly

**Verification:** ✅
- Build passes
- All 181 tests pass
- State diagram clearly shows transitions
- Recovery strategies documented

---

### Category 9: ~~Extract KanataTCPClient Message Codec~~ ⏸️ DEFERRED - Low Value
**Difficulty:** 🟡 DEFERRED | **Effort:** 4-6 hours | **Files:** 1 → 2 | **Size:** 1,214 lines

**Status: December 2025 - DEFERRED (Optional Refactoring)**

After analysis, this extraction provides **low value** relative to effort:

**Why extraction is unnecessary:**
1. **Already well-organized** - Protocol models are nested types (lines 297-382)
2. **Good test coverage** - 7 test files cover TCP functionality
3. **Swift-idiomatic** - Nested types inside actor is standard Swift pattern
4. **MARK comments** - File navigation is easy with section markers
5. **Extraction adds complexity** - Would require updating 7 test files, managing imports

**Current file structure (1,214 lines):**
```
KanataTCPClient.swift
├─ TcpServerResponse (struct, lines 7-35)
├─ CompletionFlag (private class, lines 37-49)
├─ KanataTCPClient (actor, lines 78+)
│   ├─ Connection management (lines 78-294)
│   ├─ Protocol Models (nested structs, lines 297-382)
│   │   ├─ TcpHelloOk
│   │   ├─ TcpLastReload
│   │   ├─ TcpStatusInfo
│   │   ├─ TcpValidationItem
│   │   └─ TcpValidationResult
│   ├─ Handshake/Status operations (lines 383-683)
│   ├─ Virtual key operations (lines 684-760)
│   └─ Core send/receive (lines 761-1133)
└─ Result Types + Timeout Helper (lines 1134-1214)
```

**Test files that would need updates:**
- TcpServerResponseTests.swift
- TCPConnectionLeakTests.swift
- TCPClientIntegrationTests.swift
- TCPClientRequestIDTests.swift
- TCPReadBufferTests.swift
- SimpleModsSmokeTests.swift

**Decision: DEFERRED**
The file is large but well-organized. Extracting the codec would:
- Add import complexity
- Require test file updates
- Not significantly improve maintainability

**Revisit if:**
- File grows beyond 1,500 lines
- Multiple developers need to work on TCP code simultaneously
- Protocol models need to be shared with other modules

---

### Category 10: ~~Replace NSLock with @MainActor~~ ✅ RESOLVED - Documented as Legitimate
**Difficulty:** 🟢 RESOLVED | **Effort:** 30 minutes (documentation) | **File:** 1 | **Location:** ConfigurationService.swift:734-748

**Status: December 2025 - CANNOT BE REPLACED WITH @MainActor**

After analysis, the NSLock is **legitimate and necessary** for cross-queue synchronization:

**Why @MainActor won't work here:**
1. `ConfigurationService` intentionally uses `ioQueue` for file I/O to avoid blocking UI
2. The `stateLock` protects `currentConfiguration` and `observers` accessed from:
   - Main thread (via `observe()`, UI updates)
   - `ioQueue` (via `loadConfiguration()`, `saveConfiguration()`)
3. Making the class `@MainActor` would either:
   - Force file I/O onto main thread (causes UI stutters)
   - Require complex `Task.detached` patterns for background work

**Current pattern is correct:**
- `stateLock` serializes access to shared mutable state
- File I/O runs on background queue
- Observers are notified on `@MainActor`
- Thread safety via accessor methods: `withLockedCurrentConfig()`, `setCurrentConfiguration()`, `observersSnapshot()`

**What WAS done:**
- Added comprehensive MARK comment explaining why NSLock is appropriate
- Documented the cross-queue access pattern
- Listed the thread-safe accessor methods

**Files modified:**
```
Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationService.swift
  └─ Lines 734-748: Documentation explaining legitimate NSLock use
```

**Verification:** ✅
- Build passes
- All 181 tests pass
- Documentation explains the legitimate use case

---

## 🔴 COMPLEX REFACTORING TASKS (12 issues, 30-40 hours)

These require significant planning, careful extraction, and comprehensive testing. High risk.

### Category 11: ConfigurationService Extraction (PARTIAL - December 2025)
**Difficulty:** 🔴 COMPLEX | **Effort:** 6-8 hours | **Files:** 1 → 5 | **Size:** 1,753 → 1,571 lines (after KanataKeyConverter extraction)

**Progress:**
- ✅ **KanataKeyConverter extracted** to `KanataKeyConverter.swift` (209 lines)
- 🔄 **Remaining:** ConfigurationValidator, KanataConfigGenerator, BackupManager

**Why it's complex:**
- Large file requiring refactoring
- Multiple concerns mixed (I/O, validation, rendering, backup)
- Many callers depend on current API
- Must maintain backward compatibility

**Current responsibilities (1,571 lines after first extraction):**
1. Configuration I/O operations (~300 lines)
2. Configuration validation (~250 lines)
3. Kanata config file rendering (~450 lines)
4. Key conversion/formatting (~200 lines)
5. Backup/recovery logic (~150 lines)
6. ~450 lines of private helpers

**Extraction plan:**

```
ConfigurationService.swift (Facade, ~300 lines)
├─ Coordinate between other services
├─ Maintain public API (no breaking changes)
└─ Delegate to: Validator, Generator, FileManager, BackupManager

ConfigurationValidator.swift (NEW, ~250 lines)
├─ Validate rule collections
├─ Check for conflicts
└─ Report validation errors

KanataConfigGenerator.swift (NEW, ~450 lines)
├─ Generate kanata config from rule collections
├─ Render layers, rules, key mappings
└─ Format output with proper syntax

ConfigurationFileManager.swift (NEW, ~200 lines)
├─ File I/O operations
├─ Read/write to disk
└─ Handle file watching (move from ConfigFileWatcher)

ConfigurationBackupManager.swift (NEW, ~150 lines)
├─ Backup strategies
├─ Recovery logic
└─ Cleanup old backups
```

**Implementation steps:**

**Phase 1: Validator extraction (2 hours)**
1. Identify all validation code
2. Create ConfigurationValidator
3. Move validation methods
4. Update ConfigurationService to call validator
5. Test validation still works
6. Commit

**Phase 2: Generator extraction (2 hours)**
1. Identify all rendering/generation code
2. Create KanataConfigGenerator
3. Move generation methods
4. Update ConfigurationService to call generator
5. Test config generation still works
6. Commit

**Phase 3: FileManager extraction (1.5 hours)**
1. Identify I/O operations
2. Create ConfigurationFileManager
3. Move file operations
4. Update ConfigurationService to call FileManager
5. Test file operations
6. Commit

**Phase 4: BackupManager extraction (1 hour)**
1. Identify backup logic
2. Create ConfigurationBackupManager
3. Move backup methods
4. Update ConfigurationService
5. Test backup/recovery
6. Commit

**Phase 5: API cleanup (1.5 hours)**
1. Ensure no breaking changes
2. Update all callers if needed
3. Clean up ConfigurationService facade
4. Comprehensive testing
5. Final commit

**Verification:**
- All files under 400 lines
- Each file has single responsibility
- Public API unchanged
- All tests pass
- Configuration still works end-to-end

---

### Category 12: RulesSummaryView Extraction ✅ COMPLETE (December 2025)
**Difficulty:** 🔴 COMPLEX | **Effort:** 4-6 hours | **Files:** 1 → 13 | **Size:** 2,051 → 442 lines (main) + 11 components

**Status: COMPLETE** - Extracted 11 nested types to separate files in `RulesSummaryView/` folder.

**Results:**
- **Original file:** 2,051 lines
- **Main file after:** 442 lines (78% reduction)
- **11 extracted components** in `RulesSummaryView/` folder

**File structure created:**
```
RulesSummaryView.swift (442 lines - HomeRowModsEditState + RulesTabView)
RulesSummaryView/
├─ ToastView.swift (48 lines)
├─ ExpandableCollectionRow.swift (364 lines)
├─ MappingRowView.swift (272 lines)
├─ CreateRuleButton.swift (85 lines)
├─ SingleKeyPickerContent.swift (101 lines)
├─ TapHoldPickerContent.swift (191 lines)
├─ CustomKeyPopover.swift (97 lines)
├─ PickerSegment.swift (79 lines - includes SegmentShape)
├─ MappingTableContent.swift (285 lines)
├─ KeycapStyle.swift (30 lines)
└─ AppLaunchChip.swift (99 lines)
```

**Bonus cleanup performed:**
- Removed duplicate `ToastView` from `ContentView.swift` (~40 lines)
- Removed duplicate `AppLaunchChip` from `CustomRulesView.swift` (~90 lines)

**Verification:** ✅
- Build passes
- All 181 tests pass
- Components properly imported across codebase
- No visual regression (same UI behavior)

---

### Category 13: MapperView Extraction
**Difficulty:** 🔴 COMPLEX | **Effort:** 4-6 hours | **Files:** 1 → 4 | **Size:** 1,714 → 200 lines (main) + 3 components

**Why it's complex:**
- Large ViewModel inside view (955 lines)
- Complex key mapping logic
- Interactive UI with state management
- Performance-sensitive (keyboard rendering)

**Current structure:**
- MapperView (main view, ~200 lines)
- MapperViewModel (nested, ~955 lines)
- Supporting views (nested, ~500+ lines)

**Extraction plan:**

```
MapperView.swift (Main view, ~200 lines)
├─ Layout and coordination
└─ Reference MapperViewModel

MapperViewModel.swift (EXTRACTED, ~955 lines)
├─ State management
├─ Key mapping logic
└─ Update handlers

MapperView/
├─ ResetButton.swift
├─ MapperKeycapView.swift
└─ MappingOutputView.swift
```

**Implementation steps:**

**Phase 1: Extract ViewModel (2-3 hours)**
1. Move MapperViewModel to separate file
2. Update @StateObject initialization
3. Test ViewModel logic
4. Verify model updates
5. Commit

**Phase 2: Extract component views (1-2 hours)**
1. Extract ResetButton
2. Extract MapperKeycapView
3. Extract MappingOutputView
4. Update property passing
5. Test rendering
6. Commit

**Phase 3: Clean up main view (0.5-1 hour)**
1. Simplify MapperView
2. Remove nested definitions
3. Verify layout
4. Final testing
5. Commit

**Verification:**
- Main view is ~200 lines
- ViewModel is in separate file
- All components render correctly
- Keyboard input still responsive
- All tests pass

---

### Category 14: PrivilegedOperationsCoordinator Refactoring
**Difficulty:** 🔴 COMPLEX | **Effort:** 8-10 hours | **Files:** 1 → 4 | **Size:** 991 → 250 lines (main) + 3 implementations

**Why it's complex:**
- ~600 lines of duplicated VHID restart logic
- Complex fallback chains (helper → sudo)
- Multiple operation types mixed together
- Needs careful error handling

**Current issues:**
- Helper and sudo paths have duplicate restart logic
- Fallback strategy is implicit (not documented)
- 25+ private helper methods scattered through file
- 14 public methods doing different things

**Extraction plan:**

```
PrivilegedOperationsCoordinator.swift (Facade, ~250 lines)
├─ Route operations to implementation
├─ Handle fallback logic (helper → sudo)
└─ Maintain public API

HelperOperationsImpl.swift (NEW, ~300 lines)
├─ All XPC helper-based operations
├─ Helper-specific error handling
└─ Helper restart logic

SudoOperationsImpl.swift (NEW, ~250 lines)
├─ All sudo-based operations
├─ Sudo-specific error handling
└─ Sudo restart logic

VHIDRestartStrategy.swift (NEW, ~150 lines)
├─ Specialized VHID restart logic
├─ Timing constants and retry logic
└─ Both helper and sudo paths use this
```

**Implementation steps:**

**Phase 1: Create strategy pattern (2 hours)**
1. Define PrivilegedOperationStrategy protocol
2. Create abstract operation types
3. Plan fallback chain
4. Document state machine
5. Commit

**Phase 2: Extract helper operations (3 hours)**
1. Move all helper-specific code to HelperOperationsImpl
2. Update Coordinator to route to HelperOperationsImpl
3. Test helper operations
4. Commit

**Phase 3: Extract sudo operations (2 hours)**
1. Move all sudo-specific code to SudoOperationsImpl
2. Update Coordinator to route to SudoOperationsImpl
3. Test sudo operations
4. Test fallback (helper fail → sudo succeed)
5. Commit

**Phase 4: Extract VHID restart (1.5 hours)**
1. Create VHIDRestartStrategy for shared restart logic
2. Remove duplication
3. Document timing rationale
4. Test restart scenarios
5. Commit

**Phase 5: Coordinator cleanup (1.5 hours)**
1. Simplify Coordinator (now just routing + fallback)
2. Add fallback chain logging
3. Document operation flow
4. Final testing
5. Commit

**Verification:**
- Coordinator is ~250 lines (down from 991)
- No code duplication
- Fallback logic is clear and tested
- All operations still work
- Both helper and sudo paths tested
- All tests pass

---

## 📊 Summary Table

| Task Type | Count | Effort | Complexity | Risk |
|-----------|-------|--------|-----------|------|
| **Mechanical** | 28 | 12-14 hrs | Low | Low |
| **Moderately Complex** | 13 | 15-20 hrs | Medium | Medium |
| **Complex Refactoring** | 12 | 30-40 hrs | High | High |
| **TOTAL** | 53 | 65-85 hrs | Mixed | Mixed |

---

## Recommended Execution Order

### Week 1: All Mechanical Tasks (12-14 hours)
Focus on quick wins to build momentum and confidence.

1. **Task.sleep modernization** (1 hour) - Easiest, highest visibility
2. **DispatchQueue modernization** (2-3 hours) - Mostly straightforward
3. **onTapGesture → Button** (1-2 hours) - High impact, straightforward
4. **Add accessibility labels** (1-2 hours) - Easy, high value
5. **Model validation** (2-3 hours) - Mechanical, clear scope

**Checkpoint:** 38 issues closed, build passing, tests 100% passing ✓

### Week 2: Moderately Complex Tasks (15-20 hours)
Now tackle medium-difficulty issues that require more thought but are well-scoped.

1. **Concurrency fix: @unchecked Sendable** (4-6 hours) - Start with this, critical issue
2. **Simplify XPC error handling** (4-5 hours) - Follows naturally from above
3. **HelperManager state machine** (3-4 hours) - Documentation + refactoring
4. **Replace NSLock with @MainActor** (2-3 hours) - Smaller, complementary to above
5. **Extract KanataTCPClient codec** (4-6 hours) - Self-contained refactoring

**Checkpoint:** 48 issues closed, concurrency improved, better documentation ✓

### Weeks 3-4: Complex Refactoring (30-40 hours)
Schedule larger refactoring tasks when you have dedicated time.

1. **ConfigurationService extraction** (6-8 hours) - Largest, do first for momentum
2. **RulesSummaryView extraction** (4-6 hours) - Complex but isolated to UI
3. **MapperView extraction** (4-6 hours) - Similar to RulesSummaryView, follows naturally
4. **PrivilegedOperationsCoordinator refactoring** (8-10 hours) - Save for end, very complex

**Checkpoint:** 53 issues closed, architecture significantly improved ✓

---

## Key Rules for Success

### When Doing Mechanical Tasks:
- ✅ Batch similar changes (all Task.sleep in one session)
- ✅ Run tests after each file to catch mistakes early
- ✅ Use find-and-replace with caution (verify each change)
- ✅ Commit frequently (one file per commit if it's a large batch)

### When Doing Moderately Complex Tasks:
- ✅ Create a small plan before starting
- ✅ Extract one component at a time
- ✅ Test thoroughly after each extraction
- ✅ Keep commit history clean (one logical change per commit)

### When Doing Complex Refactoring:
- ✅ Spend 1 hour planning before writing code
- ✅ Do one phase per day/session
- ✅ Get code review between phases if possible
- ✅ Test integration between extracted components
- ✅ Keep related changes in single PR (don't mix unrelated extractions)

### General Rules:
- ✅ Never refactor code you don't understand (read first, understand, THEN refactor)
- ✅ Always run full test suite after changes
- ✅ Make small commits with clear messages
- ✅ Don't combine multiple refactorings in one PR (hard to review)
- ✅ If a task seems stuck, switch to a different one and come back with fresh eyes

---

## Success Metrics by Phase

### After Week 1 (Mechanical, 12-14 hours)
- [ ] All Task.sleep calls modernized (35 instances)
- [ ] All DispatchQueue.main.async modernized (8 instances)
- [ ] All onTapGesture converted to Button (12 instances)
- [ ] All icon buttons have accessibility labels (15-20)
- [ ] Model validation added (4 models)
- [ ] 38 issues closed ✓
- [ ] Build: 15.41s (same)
- [ ] Tests: 181 passing, 100% pass rate ✓
- [ ] No regressions ✓

### After Week 2 (Moderately Complex, 15-20 hours) ✅ COMPLETE (December 2025)
- [x] @unchecked Sendable - **DOCUMENTED AS LEGITIMATE** (XPC requires it in Swift 6)
- [x] XPC error handling - **ALREADY OPTIMAL** (pattern is minimal required)
- [x] HelperManager state machine - **DOCUMENTED** with ASCII diagram + recovery strategies
- [x] NSLock in ConfigurationService - **DOCUMENTED AS LEGITIMATE** (cross-queue sync)
- [x] KanataTCPClient codec - **DEFERRED** (low value, file already well-organized)
- [x] Concurrency patterns documented ✓
- [x] Code quality improved ✓
- [x] All 181 tests pass ✓

**Key Findings:**
- Swift 6 strict concurrency prevents eliminating some @unchecked Sendable (XPC proxies aren't Sendable)
- NSLock is legitimate for cross-queue synchronization in ConfigurationService
- HelperManager already had HealthState enum - just needed documentation
- KanataTCPClient extraction deferred as low value (nested types are Swift-idiomatic)

### After Weeks 3-4 (Complex Refactoring, 30-40 hours)
- [ ] ConfigurationService split into 5 files
- [ ] RulesSummaryView split into 13 files
- [ ] MapperView split into 4 files
- [ ] PrivilegedOperationsCoordinator split into 4 files
- [ ] All god classes eliminated ✓
- [ ] 53 issues closed ✓
- [ ] Technical debt reduced by 80% ✓
- [ ] All tests pass ✓
- [ ] Build and test times improved ✓

---

## Next Steps

1. **This week:** Do Week 1 mechanical tasks (12-14 hours)
2. **Next week:** Schedule Week 2 moderately complex tasks
3. **Weeks 3-4:** Schedule complex refactoring in dedicated blocks

**Start with Task.sleep modernization today!** It's only 1 hour and gives you quick momentum.

---

**Generated with Claude Code**
**December 5, 2025**
