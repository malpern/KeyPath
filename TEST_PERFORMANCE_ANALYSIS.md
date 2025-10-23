# Test Performance Analysis

## 🐌 **Current Issues**

### Problem: Tests are slow or getting stuck

**Evidence found:**
1. **Sleep operations:** 12 instances totaling ~7+ seconds
2. **Real system calls:** Some tests may be hitting actual system APIs
3. **Integration tests:** Not properly separated from unit tests

## 📊 **Sleep Operations Found**

### Critical (2.5 seconds!)
```swift
// ServiceHealthMonitorTests.swift:103
try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
```

### Moderate (0.5 seconds each)
```swift
// KeyPathTests.swift
try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s - Multiple instances
```

### Minor (0.05-0.3 seconds)
```swift
// RecordingCoordinatorTests.swift
try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

// KeyboardCaptureTests.swift
Thread.sleep(forTimeInterval: 0.1) // 0.1s - Multiple instances
```

**Total minimum sleep time:** ~7-10 seconds per full test run

## 🏗️ **Test Architecture Issues**

### Files analyzed:
- **34 test files** totaling ~6,341 lines
- **Largest files:**
  - KeyPathTests.swift (669 lines)
  - ErrorHandlingTests.swift (484 lines)  
  - KeyboardCaptureTests.swift (478 lines)
  - IntegrationTestSuite.swift (318 lines)

### Problems:
1. **Integration tests mixed with unit tests** - No clear separation
2. **Real system calls** in some tests (launchctl references, file system operations)
3. **Sleeps used for synchronization** instead of proper async patterns
4. **No test performance budgets** - Tests can take arbitrary time

## 🎯 **Root Causes**

### 1. Timing-Based Synchronization
Tests use `sleep()` to wait for async operations instead of:
- Expectations
- Async/await properly
- Mock time control

**Example (ServiceHealthMonitorTests.swift:103):**
```swift
// ❌ BAD - Waits arbitrary 2.5 seconds
try? await Task.sleep(nanoseconds: 2_500_000_000)
await monitor.recordStartAttempt(timestamp: Date())

// ✅ GOOD - Mock time or use expectations
await monitor.recordStartAttempt(timestamp: mockClock.now())
```

### 2. Real System Calls
Some tests reference:
- `/usr/local/bin/` paths
- `launchctl` commands
- File system operations
- Real process management

These should be mocked but may be hitting real APIs.

### 3. No Test Categories
Tests aren't separated into:
- **Fast unit tests** (<100ms total)
- **Integration tests** (can be slower, run separately)
- **Manual tests** (require real system setup)

## 💡 **Recommendations**

### Immediate Fixes (Get tests fast)

#### 1. Remove Unnecessary Sleeps
```swift
// ServiceHealthMonitorTests.swift - Replace sleep with mock time
// BEFORE: 2.5 second sleep
try? await Task.sleep(nanoseconds: 2_500_000_000)

// AFTER: Inject controllable clock
monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-2.5))
```

#### 2. Use Proper Async Patterns
```swift
// RecordingCoordinatorTests - Replace sleep with expectations
// BEFORE:
coordinator.start()
try? await Task.sleep(nanoseconds: 150_000_000)
XCTAssertTrue(coordinator.isRecording)

// AFTER:
await coordinator.start()
XCTAssertTrue(coordinator.isRecording) // No sleep needed
```

#### 3. Separate Test Categories
```bash
# Fast tests only (unit)
swift test --filter KeyPathTests --filter ErrorHandlingTests

# Slow tests (integration)  
swift test --filter IntegrationTestSuite --filter ProcessLifecycleIntegrationTests
```

### Long-term Improvements

#### 1. Test Performance Budget
```swift
// Every test should complete in <10ms
func testExample() async {
    let start = Date()
    defer {
        let duration = Date().timeIntervalSince(start)
        XCTAssertLessThan(duration, 0.01, "Test exceeded 10ms budget")
    }
    // ... test code
}
```

#### 2. Mock Time Control
```swift
protocol Clock {
    func now() -> Date
    func sleep(seconds: TimeInterval) async throws
}

class MockClock: Clock {
    var currentTime = Date()
    func now() -> Date { currentTime }
    func sleep(seconds: TimeInterval) async throws {
        currentTime.addTimeInterval(seconds) // Instant!
    }
}
```

#### 3. Test Categories via Naming
```swift
// UnitTests/ - Fast, no I/O, complete in ms
KeyPathUnitTests.swift
ErrorHandlingUnitTests.swift

// IntegrationTests/ - Can hit mocked services
ServiceIntegrationTests.swift  
ProcessLifecycleIntegrationTests.swift

// ManualTests/ - Require real system (not in CI)
RealSystemTests.swift (excluded from normal runs)
```

## 🚀 **Quick Win Plan**

### Phase 1: Remove the 2.5s sleep (30 seconds of work)
```swift
// ServiceHealthMonitorTests.swift:103
// Delete the sleep, use backdated timestamp
await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-2.5))
```

### Phase 2: Fix other sleeps (10 minutes)
- RecordingCoordinatorTests: Use await instead of sleep
- KeyboardCaptureTests: Mock event timing
- KeyPathTests: Remove initialization waits

### Phase 3: Create fast test target (5 minutes)
```swift
// Package.swift
.testTarget(
    name: "KeyPathUnitTests", 
    dependencies: ["KeyPath"],
    path: "Tests/KeyPathTests",
    exclude: [
        "IntegrationTestSuite.swift",
        "ProcessLifecycleIntegrationTests.swift"
    ]
)
```

## 📈 **Expected Results**

### Current State
```
swift test: ~10-30 seconds (with sleeps and potential hangs)
```

### After Phase 1-2
```
swift test: ~2-5 seconds (sleeps removed)
```

### After Phase 3
```
swift test --filter UnitTests: <1 second (unit tests only)
swift test --filter IntegrationTests: ~3-5 seconds (when needed)
```

## 🎯 **Philosophy**

**Personal project pragmatism:**
- Unit tests should be instant feedback (<1s total)
- Integration tests can exist but run separately
- Manual/system tests should be opt-in only

**Test performance = Development velocity**

If tests are slow, you won't run them. If you don't run them, they provide no value.

**Target: Every test run completes in <1 second.**
