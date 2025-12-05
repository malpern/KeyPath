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

### Category 6: Fix @unchecked Sendable Concurrency Issues
**Difficulty:** 🟡 MODERATE | **Effort:** 4-6 hours | **Files:** 1 | **Instances:** 2

**Why it's complex:**
- Requires understanding of Swift concurrency model
- Must replace manual synchronization with async/await patterns
- Needs comprehensive testing of concurrent scenarios

**Files to modify:**
```
Sources/KeyPathAppKit/Core/HelperManager.swift
  ├─ Line 238: VersionHolder class
  └─ Line 645: CompletionState class
```

**Current problematic pattern:**
```swift
@unchecked Sendable
class VersionHolder {
    private let lock = NSLock()
    var version: String?

    func setVersion(_ v: String) {
        lock.withLock { version = v }
    }
}
```

**What to do:**
1. **Read the context** - Understand why manual synchronization was needed
2. **Identify the XPC call pattern** - What callback/completion is being bridged?
3. **Use CheckedContinuation properly**:
   ```swift
   let result = await withCheckedContinuation { continuation in
       xpcConnection.remoteObjectProxy.getVersion { version in
           continuation.resume(returning: version)
       }
   }
   ```
4. **Remove NSLock and manual state tracking**
5. **Add timeout handling** if needed:
   ```swift
   try await withThrowingTaskGroup { group in
       group.addTask { /* actual XPC call */ }
       group.addTask {
           try await Task.sleep(for: .seconds(5))
           throw TimeoutError()
       }
   }
   ```

**Implementation steps:**
1. Understand the current XPC timeout logic (read the full HelperManager context)
2. Refactor to use structured concurrency
3. Remove @unchecked Sendable completely
4. Add unit tests for timeout scenarios
5. Test with actual XPC communication
6. Commit

**Verification:**
- No @unchecked Sendable in HelperManager
- XPC calls still timeout correctly
- No data races detected by Swift concurrency checker
- All tests pass

---

### Category 7: Simplify XPC Error Handling
**Difficulty:** 🟡 MODERATE | **Effort:** 4-5 hours | **File:** 1 | **Location:** HelperManager.swift:620-683

**Why it's complex:**
- Current implementation has 4+ synchronization primitives mixed together
- Needs careful refactoring to maintain timeout behavior
- Requires understanding of how CheckedContinuation and DispatchQueue interact

**Current problematic pattern:**
```swift
func executeXPCCall(...) async throws {
    // Complex mixture of:
    // - DispatchQueue.global() timer
    // - NSLock for completion state
    // - CheckedContinuation for async bridging
    // - Manual race detection

    // This is hard to understand and maintain
}
```

**What to do:**
1. **Replace manual timeout with structured concurrency:**
   ```swift
   try await withTimeout(seconds: 5) {
       await withCheckedContinuation { continuation in
           xpcConnection.remoteObjectProxy.executeCommand() { result in
               continuation.resume(returning: result)
           }
       }
   }
   ```

2. **Create a reusable timeout helper:**
   ```swift
   func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
       try await withThrowingTaskGroup { group in
           let result = try await operation()
           group.cancelAll()
           return result
       }
   }
   ```

3. **Remove DispatchQueue timer logic**
4. **Remove NSLock for completion tracking**
5. **Keep CheckedContinuation for callback bridging**

**Implementation steps:**
1. Create timeout helper function
2. Refactor executeXPCCall to use it
3. Remove manual synchronization code
4. Test timeout scenarios (let connection hang, verify timeout fires)
5. Test success scenarios (normal XPC communication)
6. Commit

**Verification:**
- executeXPCCall is now 1/3 the complexity
- Timeout still works correctly
- All XPC commands still complete successfully
- No manual synchronization primitives

---

### Category 8: HelperManager State Machine Documentation
**Difficulty:** 🟡 MODERATE | **Effort:** 3-4 hours | **File:** 1 | **Size:** 947 lines

**Why it's complex:**
- Needs to understand implicit state transitions
- Must document fallback chains (helper → sudo)
- Requires clarity on health checking logic

**What to do:**
1. **Create formal state enum:**
   ```swift
   enum HelperHealthState {
       case unknown
       case running(version: String)
       case crashed
       case notInstalled
       case versionMismatch(current: String, expected: String)
   }
   ```

2. **Document state transitions:**
   ```
   unknown → running (on successful connection)
   unknown → crashed (on connection timeout)
   running → versionMismatch (on version check)
   versionMismatch → running (on reinstall)
   ```

3. **Add helper state tracking:**
   ```swift
   private var healthState: HelperHealthState = .unknown

   private func updateHealthState(_ newState: HelperHealthState) {
       let oldState = healthState
       healthState = newState
       logger.info("HelperManager state transition: \(oldState) → \(newState)")
   }
   ```

4. **Document fallback strategy** at top of file:
   ```swift
   // FALLBACK STRATEGY:
   // 1. Try to connect via XPC (requires helper installed and running)
   // 2. If XPC fails or helper not found, fall back to sudo helper
   // 3. If sudo helper fails, report health check failure
   // 4. Return to step 1 after cooldown period
   ```

5. **Add logging for all state transitions**

**Implementation steps:**
1. Define HelperHealthState enum
2. Add state tracking to HelperManager
3. Identify all state transitions
4. Add logging at each transition
5. Update comments to reference state machine
6. Test state transitions (watch logs during different scenarios)
7. Commit

**Verification:**
- State transitions are clear and logged
- Fallback strategy is documented and clear
- All state changes are captured in logs
- No implicit/hidden state changes

---

### Category 9: Extract KanataTCPClient Message Codec
**Difficulty:** 🟡 MODERATE | **Effort:** 4-6 hours | **Files:** 1 → 2 | **Size:** 1,214 → 800+200 lines

**Why it's complex:**
- Must identify message parsing logic vs connection management
- Requires careful API design for the extracted class
- Need to ensure all callers still work correctly

**Current file:** KanataTCPClient.swift (1,214 lines)

**What to extract:**

1. **Create TcpMessageCodec.swift (new file, ~200 lines):**
   ```swift
   struct TcpMessageCodec {
       // All message parsing/encoding logic
       func parseMessage(_ data: Data) throws -> KanataMessage
       func encodeMessage(_ message: KanataMessage) throws -> Data
       func parseJsonResponse(_ json: [String: Any]) throws -> TcpResponse
   }
   ```

2. **Keep in KanataTCPClient.swift:**
   - Connection management
   - Connection state tracking
   - Retry logic
   - Error handling at network level

**Implementation steps:**
1. **Identify all message parsing code** in KanataTCPClient
2. **Create TcpMessageCodec struct** with extracted methods
3. **Update KanataTCPClient** to use `codec.parseMessage()` instead of inline logic
4. **Test all message types** still parse correctly
5. **Verify no behavioral changes**
6. **Commit**

**Verification:**
- KanataTCPClient is now 800 lines (down from 1,214)
- Message parsing is in focused TcpMessageCodec
- All tests pass
- All message types still decode correctly

---

### Category 10: Replace NSLock with @MainActor
**Difficulty:** 🟡 MODERATE | **Effort:** 2-3 hours | **File:** 1 | **Location:** ConfigurationService.swift:732-735

**Why it's complex:**
- Must understand current state isolation
- Need to verify @MainActor is appropriate
- Requires ensuring all accesses are on main thread

**Current code:**
```swift
private let configLock = NSLock()
private var currentConfiguration: Configuration?

public func saveConfiguration(_ config: Configuration) {
    configLock.withLock {
        currentConfiguration = config
        notifyObservers()
    }
}
```

**What to do:**
1. **Remove NSLock**
2. **Add @MainActor to the property:**
   ```swift
   @MainActor
   private var currentConfiguration: Configuration?
   ```

3. **Ensure all accessors are @MainActor:**
   ```swift
   @MainActor
   public func getCurrentConfiguration() -> Configuration? {
       currentConfiguration
   }
   ```

4. **Update all callers** to use `@MainActor` or `Task { @MainActor in ... }`

**Implementation steps:**
1. Identify all places that access currentConfiguration
2. Add @MainActor isolation
3. Verify callers are already on main thread
4. Remove NSLock
5. Test with thread sanitizer
6. Commit

**Verification:**
- No NSLock remaining
- All ConfigurationService methods are @MainActor
- Thread sanitizer reports no issues
- All tests pass

---

## 🔴 COMPLEX REFACTORING TASKS (12 issues, 30-40 hours)

These require significant planning, careful extraction, and comprehensive testing. High risk.

### Category 11: ConfigurationService Extraction
**Difficulty:** 🔴 COMPLEX | **Effort:** 6-8 hours | **Files:** 1 → 5 | **Size:** 1,738 → ~300 lines (main) + 4 supporting

**Why it's complex:**
- Largest single file requiring refactoring
- Multiple concerns mixed (I/O, validation, rendering, backup)
- Many callers depend on current API
- Must maintain backward compatibility

**Current responsibilities (1,738 lines):**
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

### Category 12: RulesSummaryView Extraction
**Difficulty:** 🔴 COMPLEX | **Effort:** 4-6 hours | **Files:** 1 → 13 | **Size:** 2,049 → 150 lines (main) + 12 components

**Why it's complex:**
- Most complex UI view in the codebase
- 12 nested struct types with interdependencies
- Complex state management and layout logic
- High test coverage needed

**Current nested types (2,049 lines):**
1. ToastView
2. RulesTabView
3. ExpandableCollectionRow
4. MappingRowView
5. CreateRuleButton
6. SingleKeyPickerContent
7. TapHoldPickerContent
8. CustomKeyPopover
9. PickerSegment
10. MappingTableContent
11. KeycapStyle
12. AppLaunchChip

**Extraction plan:**

```
RulesSummaryView.swift (Main view, ~150 lines)
├─ Layout and coordination
├─ Call extracted component views
└─ Maintain state

RulesSummaryView/
├─ ToastView.swift
├─ RulesTabView.swift
├─ ExpandableCollectionRow.swift
├─ MappingRowView.swift
├─ CreateRuleButton.swift
├─ SingleKeyPickerContent.swift
├─ TapHoldPickerContent.swift
├─ CustomKeyPopover.swift
├─ PickerSegment.swift
├─ MappingTableContent.swift
├─ KeycapStyle.swift
└─ AppLaunchChip.swift
```

**Implementation steps:**

**Phase 1: Plan extraction (1 hour)**
1. Map dependencies between nested types
2. Identify which types can be extracted independently
3. Identify shared state/resources
4. Plan extraction order

**Phase 2: Extract independent components (2-3 hours)**
1. Extract simple components first (KeycapStyle, PickerSegment)
2. Move to separate files in RulesSummaryView/ folder
3. Test each component independently
4. Update imports in main view
5. Commit after each extraction

**Phase 3: Extract interdependent components (1.5-2 hours)**
1. Extract components that depend on each other
2. Use property passing to maintain communication
3. Test layout interactions
4. Commit after logical groups

**Phase 4: Clean up main view (0.5-1 hour)**
1. Simplify RulesSummaryView
2. Remove nested type definitions
3. Verify layout still correct
4. Final testing
5. Commit

**Verification:**
- Main view is ~150 lines
- Each component file is 50-200 lines
- All components still render correctly
- No layout issues
- All tests pass
- State management still works

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

### After Week 2 (Moderately Complex, 15-20 hours)
- [ ] @unchecked Sendable eliminated (2 instances)
- [ ] XPC error handling simplified
- [ ] HelperManager state machine documented
- [ ] NSLock replaced with @MainActor
- [ ] KanataTCPClient codec extracted
- [ ] 48 issues closed ✓
- [ ] Concurrency safety improved ✓
- [ ] Code quality improved ✓
- [ ] All tests pass ✓

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
