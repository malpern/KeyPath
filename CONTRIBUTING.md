# Contributing to KeyPath

Welcome! KeyPath is a macOS keyboard remapping app that makes Kanata easy to use. This guide will get you started in **10 minutes**.

## Quick Start (5 minutes)

```bash
# 1. Clone
git clone https://github.com/malpern/KeyPath.git
cd KeyPath

# 2. Build & sign (recommended for accurate testing)
./Scripts/build-and-sign.sh

# 3. Deploy & run
mkdir -p ~/Applications
cp -R dist/KeyPath.app ~/Applications/
osascript -e 'tell application "KeyPath" to quit' || true
open ~/Applications/KeyPath.app
```

### Dev-only quick preview
If you just want a fast local preview (unsigned), you can run the debug app. Note this may not reflect real permissions/signing behavior.

```bash
swift build
open .build/debug/KeyPath.app
```

That's it! You're ready to contribute.

## I Want To...

### Add a keyboard shortcut
**Edit:** `Sources/KeyPath/UI/RecordingCoordinator.swift`
**What:** This handles keyboard input recording for creating mappings.

### Change the main UI
**Edit:** `Sources/KeyPath/UI/ContentView.swift`
**What:** Main app window with status, mappings list, and controls.

### Fix a bug in key mapping
**Edit:** `Sources/KeyPath/Services/KanataConfigGenerator.swift`
**What:** Converts key mappings to Kanata config format.

### Add a new service check to the wizard
**Edit:** `Sources/KeyPath/InstallationWizard/Core/SystemStatusChecker.swift`
**What:** Detects system state and determines wizard flow.

### Add a notification
**Edit:** `Sources/KeyPath/Services/UserNotificationService.swift`
**What:** Handles macOS notifications with actions.

### Improve error handling
**Edit:** `Sources/KeyPath/Core/KeyPathError.swift`
**What:** Centralized error hierarchy for the entire app.

### Add a test
**Edit:** `Tests/KeyPathTests/` (use existing tests as examples)
**Run:** `swift test`

## Architecture (3-minute read)

KeyPath has three main layers:

### 1. Services Layer
Services handle specific responsibilities: `ConfigurationService` manages config files, `PermissionOracle` detects permissions, `KanataManager` coordinates everything. **Pattern:** One service = one responsibility.

### 2. UI Layer (SwiftUI + MVVM)
Views (`ContentView`, `InstallationWizardView`) talk to `KanataViewModel`, which talks to `KanataManager`. **Pattern:** Views never access KanataManager directly—they go through the ViewModel.

### 3. Kanata Integration
KeyPath starts Kanata as a LaunchDaemon service and supports live config reloads. File watching enables hot‑reload.

## Common Patterns

### Pattern 1: Adding a new service
```swift
// 1. Create protocol
@MainActor
protocol MyServiceProtocol {
    func doSomething() async -> Bool
}

// 2. Implement service
@MainActor
final class MyService: MyServiceProtocol {
    func doSomething() async -> Bool {
        // Implementation
    }
}

// 3. Add to KanataManager
private let myService: MyServiceProtocol

init() {
    myService = MyService()
}
```

### Pattern 2: Updating UI from service
```swift
// In KanataManager (business logic)
func startService() async {
    isRunning = true  // Internal state
}

// In KanataViewModel (UI layer)
@Published var isRunning = false  // UI state

func startService() async {
    await manager.startService()
    await syncFromManager()  // Sync UI from manager
}
```

### Pattern 3: Error handling
```swift
// Throw structured errors
throw KeyPathError.configuration(.invalidFormat(reason: "Missing defcfg"))

// Catch and handle
do {
    try await configService.save(config)
} catch let KeyPathError.configuration(error) {
    // Handle config error
} catch {
    // Handle other errors
}
```

### Pattern 4: Permission checking
```swift
// Always use PermissionOracle (single source of truth)
let snapshot = await PermissionOracle.shared.currentSnapshot()
if snapshot.keyPath.inputMonitoring.isReady {
    // Permission granted
}

// NEVER check permissions directly via IOHIDCheckAccess or AXIsProcessTrusted
```

### Pattern 5: Logging
```swift
// Use AppLogger for consistent logging
AppLogger.shared.log("🚀 Starting service...")
AppLogger.shared.log("✅ Service started successfully")
AppLogger.shared.log("❌ Service failed: \(error)")
```

## Testing Guide

### Running Tests
```bash
# Run all tests
swift test

# Run specific test
swift test --filter MyTestClass.testMyFunction

# Run with verbose output
swift test -v
```

### Test Examples

**Example 1: Service Test**
```swift
@MainActor
final class MyServiceTests: XCTestCase {
    func testServiceDoesTask() async throws {
        let service = MyService()
        let result = await service.doTask()
        XCTAssertTrue(result)
    }
}
```

**Example 2: Testing with TestEnvironment**
```swift
override func setUp() async throws {
    TestEnvironment.forceTestMode = true  // Skips admin operations
}

override func tearDown() async throws {
    TestEnvironment.forceTestMode = false
}
```

**Example 3: Testing Permissions (Mock Oracle)**
```swift
func testWithPermissions() async {
    // Oracle will return test-friendly results in test mode
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    // Use snapshot in test
}
```

**Example 4: Testing Errors**
```swift
func testThrowsExpectedError() async {
    do {
        try await service.doInvalidOperation()
        XCTFail("Should have thrown error")
    } catch KeyPathError.configuration(.invalidFormat) {
        // Expected error
    } catch {
        XCTFail("Wrong error type: \(error)")
    }
}
```

**Example 5: Testing Async Operations**
```swift
func testAsyncOperation() async throws {
    let expectation = XCTestExpectation(description: "Async task completes")

    Task {
        await service.doAsyncTask()
        expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 5.0)
}
```

## File Organization

```
Sources/KeyPath/
├── Core/               # Core types and protocols
│   ├── KeyPathError.swift
│   └── Contracts/      # Protocol definitions
├── Services/           # Business logic services
│   ├── ConfigurationService.swift
│   ├── PermissionOracle.swift
│   ├── (Kanata client/IPC implementation)
│   └── ...
├── Managers/           # Coordinators (being refactored)
│   └── KanataManager.swift  # Main coordinator
├── UI/                 # SwiftUI views
│   ├── ContentView.swift
│   ├── ViewModels/
│   └── Components/
├── InstallationWizard/ # Setup wizard
│   ├── Core/           # Wizard logic
│   └── UI/             # Wizard views
└── Utilities/          # Helpers
    ├── Logger.swift
    └── Notifications.swift

Tests/KeyPathTests/     # Test files
```

## Code Style

- **Swift 6 concurrency:** Use `async/await`, actors, and `@MainActor`
- **Error handling:** Use `KeyPathError` for all domain errors
- **Naming:** Clear, descriptive names (`isKarabinerDriverInstalled`, not `checkDriver`)
- **Comments:** Explain *why*, not *what* (code should be self-documenting)
- **Logging:** Use emojis for visibility: 🚀 (start), ✅ (success), ❌ (error), ⚠️ (warning)

## Accessibility Requirements ♿

**All interactive UI elements MUST have accessibility identifiers** for automation and testing.

### Required for:
- ✅ `Button` - All buttons
- ✅ `Toggle` - All toggles/switches
- ✅ `Picker` - All pickers/dropdowns
- ✅ Custom interactive components (add identifiers internally)

### How to Add:

```swift
// ✅ CORRECT
Button("Save") {
    save()
}
.accessibilityIdentifier("settings-save-button")
.accessibilityLabel("Save settings")

// ❌ WRONG - Missing identifier
Button("Save") {
    save()
}
```

### Naming Convention:

- **Format:** `[screen]-[element-type]-[description]`
- **Examples:**
  - `settings-tab-rules` (Settings tab)
  - `rules-create-button` (Rules tab button)
  - `wizard-nav-forward` (Wizard navigation)
  - `overlay-drawer-toggle` (Overlay control)

### Verification:

```bash
# Check before committing
python3 Scripts/check-accessibility.py

# Pre-commit hook runs automatically (warning only for now)
git commit -m "feat: add new feature"
```

### Documentation:

See [ACCESSIBILITY_COVERAGE.md](ACCESSIBILITY_COVERAGE.md) for:
- Complete identifier reference
- Examples for each screen
- Peekaboo automation examples

**Note:** Pre-commit hook currently warns but doesn't block commits. This allows gradual adoption. We plan to make it blocking once all existing elements are covered.

## Pull Request Process

1. **Create a branch:** `git checkout -b feature/my-feature`
2. **Make changes:** Follow patterns above
3. **Test:** `swift test`
4. **Commit:** Use conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`)
5. **Push:** `git push origin feature/my-feature`
6. **Create PR:** Describe what and why

## Getting Help

- **Issues:** Check [GitHub Issues](https://github.com/malpern/KeyPath/issues)
- **Documentation:** See [CLAUDE.md](CLAUDE.md) for detailed architecture
- **Ask:** Create an issue with the `question` label

## Important Notes

### ⚠️ Current Known Issues
- **KanataManager:** 2,828 lines (being refactored to ~800 lines)
- **Build Issue:** Karabiner extraction causing emit-module error (under investigation)

### 🧩 Open Work (tracked as issues/TODOs)
- Privileged helper/XPC path: implement `helperInstallBundledKanata()` (currently falls back to sudo)
- Wizard operations factory: move Core factory to UI layer to avoid Core→UI references
- Wizard critical surfacing: show a blocking issue when the bundled kanata binary is missing
- UI help bubble: switch Core→UI call to a notification-based implementation
- Update `requiredDriverVersionMajor` to 6 in VHIDDeviceManager.swift when kanata v1.10 is released

### ✅ Recently Completed
- ADR-012 wiring: driver version Fix button connected, mismatch dialog shows, downloads v5.0.0

### 🚫 Don't Do These
1. **Don't check permissions directly** - Use `PermissionOracle` only
2. **Don't modify KanataManager** - It's being refactored; put logic in services instead
3. **Don't skip tests** - They prevent regressions
4. **Don't use sudo in tests** - Use `TestEnvironment.forceTestMode`

## What Makes a Good Contribution?

✅ **Good contributions:**
- Fix a bug with a test showing it's fixed
- Add a feature users requested
- Improve documentation or examples
- Refactor code to be simpler
- Add tests for untested code

❌ **Avoid:**
- Large refactorings without discussion
- Breaking changes without migration path
- Features that complicate the UI
- Code without tests

## Roadmap

We're currently working on:
1. **Simplifying KanataManager** (2,828 → ~800 lines)
2. **Fixing build issues** (Karabiner service extraction)
3. **Improving documentation**

See [OVERENGINEERED.md](docs/OVERENGINEERED.md) for detailed roadmap.

---

**Thank you for contributing to KeyPath!** 🎉

Every contribution makes keyboard remapping more accessible to Mac users.