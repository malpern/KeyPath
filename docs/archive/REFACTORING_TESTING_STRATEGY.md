# Build-Safe Refactoring Testing Strategy

**Created:** August 26, 2025  
**Purpose:** Enable confident refactoring without constant accessibility permission re-grants  
**Status:** Implementation Ready  

## Problem Analysis

### Why Accessibility Permissions Reset After Each Build

1. **Code Signing Changes**: Development builds use different signing identities than production
2. **Bundle Path Changes**: Each build may create a new app bundle location  
3. **TCC Database Identity**: macOS TCC tracks apps by (Team ID + Bundle ID + Path + Code Signature)
4. **Development vs Production**: `swift build` creates unsigned binaries, triggering permission resets

### Current Pain Points

- Manual accessibility permission re-grants after every build
- Integration tests require live system permissions  
- CGEvent tap testing breaks when permissions missing
- Fear of breaking stable, signed builds during refactoring

## Build-Safe Testing Architecture

### 1. Tiered Testing Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                     TIER 1: Unit Tests                     │
│              No Permissions Required (95% of tests)        │
│  ✅ Manager class logic, state machines, configurations    │
│  ✅ Protocol conformance, dependency injection             │
│  ✅ Data transformations, error handling                   │
└─────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────▼─────────────────────────────────┐
│                 TIER 2: Mock Integration Tests             │
│            Mocked System Calls (90% coverage)              │
│  ✅ CGEvent tap creation (mocked)                          │
│  ✅ Process lifecycle management (stubbed)                 │
│  ✅ File system operations (temporary dirs)               │
└─────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────▼─────────────────────────────────┐
│                TIER 3: Smoke Tests (Minimal)               │
│           Real System Integration (Manual Only)            │
│  ⚠️ End-to-end keyboard capture validation                 │
│  ⚠️ Production build permission verification               │
└─────────────────────────────────────────────────────────────┘
```

### 2. Permission-Free Unit Testing

**Focus Areas:**
- Manager class refactoring (95% of PLAN.md work)
- Protocol extraction and service delegation
- State machine logic and transitions
- Configuration parsing and validation
- Error handling and recovery

**Test Approach:**
```swift
// Example: Test KanataManager delegation without CGEvent taps
class MockEventTapping: EventTapping {
    var installCalled = false
    var uninstallCalled = false
    
    func install() throws -> TapHandle {
        installCalled = true
        return TapHandle(tap: nil, runLoopSource: nil) // Mock handle
    }
    
    func uninstall() { uninstallCalled = true }
    var isInstalled: Bool { installCalled && !uninstallCalled }
}

func testKanataManagerDelegation() {
    let mockTap = MockEventTapping()
    let manager = KanataManager(eventTap: mockTap)
    
    manager.startEventProcessing()
    XCTAssertTrue(mockTap.installCalled)
}
```

### 3. Mocked System Integration

**Mock Targets:**
- `CGEvent.tapCreate()` → Return mock CFMachPort
- `AXIsProcessTrusted()` → Return configurable boolean
- Process execution (`pgrep`, `launchctl`) → Return canned output
- File system operations → Use temporary directories

**Implementation Pattern:**
```swift
protocol SystemInterface {
    func createEventTap(options: EventTapOptions) throws -> TapHandle
    func checkAccessibilityPermissions() -> Bool
    func executeCommand(_ command: String) throws -> String
}

class MockSystemInterface: SystemInterface {
    var mockPermissionState = true
    var mockEventTapSuccess = true
    
    func createEventTap(options: EventTapOptions) throws -> TapHandle {
        guard mockEventTapSuccess else { throw SystemError.tapCreationFailed }
        return TapHandle(tap: mockCFMachPort, runLoopSource: mockRunLoopSource)
    }
    
    func checkAccessibilityPermissions() -> Bool { mockPermissionState }
    func executeCommand(_ command: String) throws -> String { "mocked output" }
}
```

## Refactoring-Specific Testing Plan

### Phase 1: File Splitting (Milestone 1)
**Tests Required:**
- [ ] Build compilation (automated)
- [ ] All existing unit tests pass (automated)
- [ ] No functional behavior changes (automated)
- [ ] Import statements resolve correctly (automated)

**No Permissions Needed:** ✅ Pure code organization

### Phase 2: Protocol Extraction (Milestones 2-3)
**Tests Required:**
- [ ] Protocol conformance compilation (automated)
- [ ] Mock implementations for all protocols (automated)  
- [ ] EventTag system unit tests (automated)
- [ ] TapSupervisor registration logic (mocked CGEvent taps)

**Permissions Required:** ❌ None - all mocked

### Phase 3: Service Extraction (Milestones 4-8)
**Tests Required:**
- [ ] ConfigurationService file operations (temp dirs)
- [ ] EventRouter chain processing (mocked events)
- [ ] LifecycleOrchestrator state transitions (mocked dependencies)
- [ ] Manager delegation behavior (dependency injection)

**Permissions Required:** ❌ None - all mocked or sandboxed

### Phase 4: Integration Validation (Milestone 9)
**Tests Required:**
- [ ] End-to-end smoke test (manual only)
- [ ] Production build verification (manual only)

**Permissions Required:** ⚠️ Manual testing only

## Build Configuration Strategy

### 1. Development Build Pipeline
```bash
# Fast development cycle (no signing, no permissions)
swift build                    # Unit tests only
swift test                     # Mocked integration tests
./Scripts/verify-refactor.sh   # Custom validation script
```

### 2. Integration Testing Pipeline  
```bash
# Use signed build for permission testing (less frequent)
./Scripts/build-and-sign.sh    # Only when needed
cp -r dist/KeyPath.app /Applications/
# Manual smoke test with preserved permissions
```

### 3. CI/CD Pipeline
```yaml
# GitHub Actions - no permissions needed
- name: Build
  run: swift build -c release
  
- name: Unit Tests  
  run: swift test
  
- name: Mock Integration Tests
  run: ./Scripts/test-mocked-integration.sh
  
- name: Refactor Validation
  run: ./Scripts/verify-refactor.sh
```

## Implementation: Permission-Free Test Infrastructure

### 1. System Interface Abstraction
```swift
// Sources/KeyPath/Core/System/SystemInterface.swift
protocol SystemInterface {
    func createEventTap(options: EventTapOptions) async throws -> TapHandle
    func checkAccessibilityPermissions() async -> Bool
    func executeProcess(_ command: String, args: [String]) async throws -> ProcessResult
    func writeFile(content: String, to path: URL) async throws
}

// Real implementation for production
class RealSystemInterface: SystemInterface { /* ... */ }

// Mock implementation for tests  
class MockSystemInterface: SystemInterface { /* ... */ }
```

### 2. Dependency Injection Pattern
```swift
// Modify managers to accept SystemInterface
class KanataManager {
    private let systemInterface: SystemInterface
    
    init(systemInterface: SystemInterface = RealSystemInterface()) {
        self.systemInterface = systemInterface
    }
    
    func startEventProcessing() async throws {
        let tap = try await systemInterface.createEventTap(options: .default)
        // ... rest of logic
    }
}

// Tests inject mock
func testKanataManagerStart() async throws {
    let mockSystem = MockSystemInterface()
    mockSystem.mockEventTapSuccess = true
    
    let manager = KanataManager(systemInterface: mockSystem)
    try await manager.startEventProcessing()
    
    XCTAssertTrue(mockSystem.createEventTapCalled)
}
```

### 3. Build Verification Script
```bash
#!/bin/bash
# Scripts/verify-refactor.sh

echo "🔍 Verifying refactoring integrity..."

# 1. Build check
echo "Building..."
if ! swift build -c release; then
    echo "❌ Build failed"
    exit 1
fi

# 2. Unit test check  
echo "Running unit tests..."
if ! swift test; then
    echo "❌ Unit tests failed"
    exit 1
fi

# 3. Mock integration tests
echo "Running mock integration tests..."
if ! ./Scripts/test-mocked-integration.sh; then
    echo "❌ Mock integration tests failed"
    exit 1
fi

# 4. Line count validation
echo "Checking KanataManager line count..."
LINES=$(wc -l Sources/KeyPath/Managers/KanataManager.swift | awk '{print $1}')
if [ $LINES -gt 1000 ]; then
    echo "⚠️ KanataManager still has $LINES lines (target: <1000)"
else
    echo "✅ KanataManager line count: $LINES"
fi

echo "✅ Refactoring verification complete"
```

## Confidence Building Strategy

### 1. Frequent Verification Points
- **Every commit:** Build + unit tests (automated)
- **Every milestone:** Mock integration tests (automated)  
- **Major milestones:** Manual smoke test with signed build (weekly)

### 2. Rollback Safety
- **Git branches:** One branch per milestone
- **Automated checks:** Prevent merge if tests fail
- **Quick rollback:** `git checkout previous-working-commit`

### 3. Progressive Validation
```
Week 1: File splitting → Build test only
Week 2: Protocols added → Mock tests added  
Week 3: Services extracted → Integration mocks
Week 4: Full refactor → Manual smoke test
```

## Tools and Scripts

### 1. Mock Integration Test Runner
```bash
#!/bin/bash
# Scripts/test-mocked-integration.sh

export KEYPATH_TEST_MODE=mocked
swift test --filter MockIntegrationTests
```

### 2. Permission-Free CI Configuration
```yaml
# .github/workflows/refactor-validation.yml
name: Refactor Validation
on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v3
    - name: Build
      run: swift build -c release
    - name: Unit Tests
      run: swift test
    - name: Mock Integration Tests  
      run: ./Scripts/test-mocked-integration.sh
    - name: Verify Refactoring
      run: ./Scripts/verify-refactor.sh
```

## Expected Benefits

### ✅ Fast Development Cycle
- No permission re-grants during development
- Unit tests run in <30 seconds
- Mock integration tests run in <2 minutes
- Build verification in <5 minutes

### ✅ High Confidence Refactoring
- 95%+ test coverage without system permissions
- Automated verification of each milestone
- Quick rollback capability
- CI/CD validation on every commit

### ✅ Preserved Production Stability
- Signed builds only when needed
- Manual testing on stable builds
- TCC-safe deployment process maintained

## Next Steps

1. **Implement SystemInterface** abstraction layer
2. **Create MockSystemInterface** for all system calls
3. **Update existing tests** to use mocked dependencies
4. **Set up build verification** script
5. **Begin Milestone 1** file splitting with confidence

---

**This strategy eliminates the accessibility permission pain while enabling confident, rapid refactoring with comprehensive test coverage.**