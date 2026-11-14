# Contributing to KeyPath

Welcome! KeyPath is a macOS keyboard remapping app that makes Kanata easy to use. This guide will get you started in **10 minutes**.

Development requires an **Apple Silicon (M-series) Mac** running **macOS 27 or later** and a full **Xcode** install (Command Line Tools alone are not enough; the build needs the Metal toolchain). Intel Macs are not supported.

## Quick Start (5 minutes)

```bash
# 1. Clone (the Kanata engine is a submodule)
git clone --recurse-submodules https://github.com/malpern-labs/KeyPath.git
cd KeyPath

# 2. Build and run the fast tests
swift build
./Scripts/test-fast.sh --changed

# 3. Deploy to /Applications and run
./Scripts/quick-deploy.sh
```

`quick-deploy.sh` signs with a Developer ID or Apple Development certificate if
you have one, and falls back to ad-hoc signing if you don't. With ad-hoc
signing macOS forgets the Accessibility grant on every deploy, so you will
re-grant it each time.

That's it! You're ready to contribute. [`AGENTS.md`](AGENTS.md) has the full
build, test and release workflow.

## Security Reporting

For potential vulnerabilities, do **not** open a public issue.

- Preferred: GitHub Security Advisory
  - https://github.com/malpern-labs/KeyPath/security/advisories/new
- Fallback: malpern@gmail.com

See [`SECURITY.md`](SECURITY.md) for full policy and response expectations.

## Community Build Mode vs Release Build

Community contributors can run most checks without signing credentials:

```bash
swift build
./Scripts/test-fast.sh --changed
./Scripts/run-tests-safe.sh
```

Release/distribution validation requires signed/notarized artifacts and Apple credentials:

- `./Scripts/release-candidate.sh` release pipeline
- notarization + signature checks
- installed-app verification (`./Scripts/verify-installed-app.sh`)

## I Want To...

### Add a keyboard shortcut
**Edit:** `Sources/KeyPathAppKit/UI/Pickers/RecordingCoordinator.swift`
**What:** This handles keyboard input recording for creating mappings.

### Change the main UI
**Edit:** `Sources/KeyPathAppKit/App.swift` (root scene) and the modular views under `Sources/KeyPathAppKit/UI/`
**What:** The UI is composed of many SwiftUI views — there is no single `ContentView`.

### Fix a bug in key mapping
**Edit:** `Sources/KeyPathAppKit/Infrastructure/Config/` (config generation and parsing)
**What:** Converts key mappings to Kanata config format. The `(defcfg ...)` header is centralized in `KanataDefcfg.swift`.

### Add a new service check to the wizard
**Edit:** `Sources/KeyPathInstallationWizard/Core/SystemInspector.swift` (and `InstallerEngine.swift`)
**What:** Inspects system state; `WizardStateMachine.swift` determines wizard flow.

### Add a notification
**Edit:** `Sources/KeyPathAppKit/Services/UserNotificationService.swift`
**What:** Handles macOS notifications with actions.

### Improve error handling
**Edit:** `Sources/KeyPathCore/KeyPathError.swift`
**What:** Centralized error hierarchy for the entire app.

### Add a test
**Edit:** `Tests/KeyPathTests/` (use existing tests as examples)
**Run:** `swift test`

## Architecture (3-minute read)

KeyPath has three main layers:

### 1. Services Layer
Services handle specific responsibilities: `ConfigurationService` manages config files, `PermissionOracle` detects permissions, `RuntimeCoordinator` orchestrates the runtime, and `ServiceLifecycleCoordinator` starts, stops and restarts Kanata. **Pattern:** One service = one responsibility.

### 2. UI Layer (SwiftUI + Observation)
Views talk to `KanataViewModel`, which talks to `RuntimeCoordinator`. View models are `@Observable`.

### 3. Kanata Integration
KeyPath has one runtime: Kanata runs as an unprivileged worker in the user's session, launched from KeyPath.app. There is no privileged helper, LaunchDaemon or keyboard driver; that stack was retired ([ADR-045](docs/adr/adr-045-retire-privileged-runtime-stack.md), [ADR-047](docs/adr/adr-047-pre-release-cleanup.md)) and must not be reintroduced. Config changes are applied with a reload over a local TCP connection, through `ConfigReloadCoordinator`. File watching enables hot‑reload.

Install, repair and uninstall go through `InstallerEngine`. See the responsibility map in [`AGENTS.md`](AGENTS.md).

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

// 3. Inject it where it is used
private let myService: MyServiceProtocol

init(myService: MyServiceProtocol = MyService()) {
    self.myService = myService
}
```

Before adding a new Manager, Coordinator or Service, check whether an existing
owner should take the responsibility
([ADR-043](docs/adr/adr-043-opportunistic-manager-consolidation.md)).

### Pattern 2: Updating UI from service
```swift
// UI state lives in an @Observable type; views read it directly.
@Observable
@MainActor
final class MyViewModel {
    var isRunning = false

    func refresh(from status: RuntimeStatus) {
        isRunning = status.isRunning
    }
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
if snapshot.isSystemReady {
    // KeyPath has Accessibility and the runtime confirms key access
}

// NEVER check permissions directly via IOHIDCheckAccess or AXIsProcessTrusted,
// and never read the TCC database (ADR-044)
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
├── KeyPathApp/                 # App entry point and Info.plist
├── KeyPathAppKit/              # Most of the app
│   ├── Infrastructure/Config/  # Config generation and parsing
│   ├── Managers/               # RuntimeCoordinator, lifecycle, reload
│   ├── Services/               # Business logic (SessionRuntime, Networking, ...)
│   └── UI/                     # SwiftUI views and view models
├── KeyPathCore/                # Shared types, errors, logging, paths
├── KeyPathPermissions/         # PermissionOracle
├── KeyPathRulesCore/           # Rule and collection model
├── KeyPathInstallationWizard/  # Setup wizard and InstallerEngine
├── KeyPathWizardCore/          # Wizard types shared with the app
├── KeyPathCLI/                 # keypath-cli
└── KeyPathInsights/            # Activity Insights plugin

Tests/KeyPathTests/             # Main test target
```

## Code Style

- **Swift 6 concurrency:** Use `async/await`, actors, and `@MainActor`
- **Error handling:** Use `KeyPathError` for all domain errors
- **Naming:** Clear, descriptive names (`isRuntimeReady`, not `checkRuntime`)
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

**Note:** Pre-commit hook currently warns but doesn't block commits.

## Pull Request Process

1. **Create a branch:** `git checkout -b feature/my-feature`
2. **Make changes:** Follow patterns above
3. **Test:** `swift test`
4. **Commit:** Use conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`)
5. **Push:** `git push origin feature/my-feature`
6. **Create PR:** Describe what and why

## Getting Help

- **Issues:** Check [GitHub Issues](https://github.com/malpern-labs/KeyPath/issues)
- **Documentation:** See [AGENTS.md](AGENTS.md) for architecture and workflow, and [docs/adr/](docs/adr/README.md) for design decisions
- **Ask:** Create an issue with the `question` label

## Important Notes

### 🚫 Don't Do These
1. **Don't check permissions directly** - Use `PermissionOracle` only
2. **Don't add privileged paths** - No `sudo`, `launchctl`, LaunchDaemon or privileged-helper code; install and repair go through `InstallerEngine`
3. **Don't start, stop or reload Kanata yourself** - Use `ServiceLifecycleCoordinator` and `ConfigReloadCoordinator`
4. **Don't skip tests** - They prevent regressions

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

---

**Thank you for contributing to KeyPath!** 🎉

Every contribution makes keyboard remapping more accessible to Mac users.
