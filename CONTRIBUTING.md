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
**Edit:** `Sources/KeyPathAppKit/UI/RecordingCoordinator.swift`<br>
**What:** This handles keyboard input recording for creating mappings.

### Change the main UI
**Edit:** `Sources/KeyPathAppKit/UI/ContentView.swift`<br>
**What:** Main app window with status, mappings list, and controls.

### Fix a bug in key mapping
**Edit:** `Sources/KeyPathAppKit/Services/KanataConfigGenerator.swift`<br>
**What:** Converts key mappings to Kanata config format.

### Add a new service check to the wizard
**Edit:** `Sources/KeyPathAppKit/InstallationWizard/Core/InstallerEngine.swift`<br>
**What:** Unified façade for installation, repair, and system inspection.

### Add a notification
**Edit:** `Sources/KeyPathAppKit/Services/UserNotificationService.swift`<br>
**What:** Handles macOS notifications with actions.

### Improve error handling
**Edit:** `Sources/KeyPathCore/KeyPathError.swift`<br>
**What:** Centralized error hierarchy for the entire app.

### Add a test
**Edit:** `Tests/KeyPathTests/` (use existing tests as examples)<br>
**Run:** `swift test`

## Architecture (3-minute read)

KeyPath has three main layers:

### 1. Services Layer
Services handle specific responsibilities: `ConfigurationService` manages config files, `PermissionOracle` detects permissions, `RuntimeCoordinator` coordinates everything. **Pattern:** One service = one responsibility.

### 2. UI Layer (SwiftUI + MVVM)
Views (`ContentView`, `InstallationWizardView`) talk to `KanataViewModel`, which talks to `RuntimeCoordinator`. **Pattern:** Views never access RuntimeCoordinator directly—they go through the ViewModel.

### 3. Kanata Integration
KeyPath starts Kanata as a LaunchDaemon service and communicates via TCP for layer changes and config reloads.

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

// 3. Add to RuntimeCoordinator
private let myService: MyServiceProtocol

init() {
    myService = MyService()
}
```

### Pattern 2: Updating UI from service
```swift
// In RuntimeCoordinator (business logic)
func startService() async {
    isRunning = true  // Internal state
}

// In KanataViewModel (UI layer)
@Published var isRunning = false  // UI state

func startService() async {
    await manager.startService()
    // ViewModel observes manager.stateChanges AsyncStream
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
Sources/
├── KeyPathApp/             # App executable entry point
│   └── Main.swift          # Dispatches to CLI or GUI based on args
├── KeyPathAppKit/          # Main app code (shared library)
│   ├── App.swift           # SwiftUI app definition
│   ├── CLI/                # CLI commands (install, repair, status, etc.)
│   ├── Core/               # Core types, protocols, helper manager
│   ├── Infrastructure/     # Config service, key converter
│   ├── InstallationWizard/ # Setup wizard (Core/ and UI/)
│   ├── Managers/           # RuntimeCoordinator, diagnostics, recovery
│   ├── MenuBar/            # Menu bar controller
│   ├── Models/             # Data models (CustomRule, VirtualKey, etc.)
│   ├── Resources/          # Assets and resources
│   ├── Services/           # Business logic services
│   ├── UI/                 # SwiftUI views and ViewModels
│   └── Utilities/          # Helpers (Logger, FeatureFlags, etc.)
├── KeyPathCLI/             # Standalone CLI executable entry point
├── KeyPathCore/            # Shared core utilities
├── KeyPathDaemonLifecycle/ # LaunchDaemon management
├── KeyPathHelper/          # Privileged helper (XPC)
├── KeyPathPermissions/     # PermissionOracle
└── KeyPathWizardCore/      # Wizard shared types (SystemSnapshot, WizardTypes)

Tests/KeyPathTests/         # Test files
```

## Code Style

- **Swift 6 concurrency:** Use `async/await`, actors, and `@MainActor`
- **Error handling:** Use `KeyPathError` for all domain errors
- **Naming:** Clear, descriptive names (`isKarabinerDriverInstalled`, not `checkDriver`)
- **Comments:** Explain *why*, not *what* (code should be self-documenting)
- **Logging:** Use emojis for visibility: 🚀 (start), ✅ (success), ❌ (error), ⚠️ (warning)

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

### 🚫 Don't Do These
1. **Don't check permissions directly** - Use `PermissionOracle` only
2. **Don't skip tests** - They prevent regressions
3. **Don't use sudo in tests** - Use `TestEnvironment.forceTestMode`

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

**Current Release: R1 (Installer + Custom Rules)**
- Visual rule editor with tap-hold and tap-dance
- Installation wizard with auto-remediation
- LaunchDaemon service management

**In Progress: R2 (Full Features)**
- Live Keyboard Overlay - visual feedback showing active layer and key mappings
- Mapper UI - graphical keyboard layout editor
- Simulator Tab - test configs without applying them
- Rule Collections - pre-built rule sets (Vim, Caps Lock, Home Row Mods)

Use `Ctrl+Option+Cmd+R` to toggle between R1 and R2 feature sets during development.

---

**Thank you for contributing to KeyPath!** 🎉

Every contribution makes keyboard remapping more accessible to Mac users.
