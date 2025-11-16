# Test Support Infrastructure

This directory contains global test infrastructure that runs before any tests execute.

## AdminPromptBypass

**Purpose:** Eliminates password dialogs during test execution by installing fake admin executors globally.

### How It Works

The `AdminPromptBypass` class uses XCTest's `class func setUp()` to configure the test environment before any tests run:

1. **Installs FakeAdminCommandExecutor** - All admin commands succeed silently without prompts
2. **Bypasses authorization scripts** - LaunchDaemonInstaller skips osascript execution
3. **Disables real admin operations** - TestEnvironment prevents actual /Library writes
4. **Sets KEYPATH_TEST_MODE=1** - Ensures consistent test behavior

### Why This Exists

Running the full test suite without this bootstrap triggers multiple password dialogs:

- **CI/CD failure** - No way to input passwords in automated environments
- **Developer friction** - Constant interruptions during local development
- **Flaky tests** - Timeouts waiting for human input
- **Slow execution** - Each prompt adds seconds/minutes

By default, tests should run **fast and unattended**. Only specific smoke tests should exercise real authorization flows.

### Opting Out (For Smoke Tests)

Tests that need real Authorization Services behavior must explicitly restore the real executor in `setUp()`:

```swift
@MainActor
final class AuthorizationServicesSmokeTests: XCTestCase {
    private var originalAdminExecutor: AdminCommandExecutor!

    override func setUp() async throws {
        try await super.setUp()

        // Opt out of global bootstrap - restore real auth behavior
        originalAdminExecutor = AdminCommandExecutorHolder.shared
        AdminCommandExecutorHolder.shared = DefaultAdminCommandExecutor()

        // ... rest of setup
    }

    override func tearDown() async throws {
        // Restore global bootstrap state
        AdminCommandExecutorHolder.shared = originalAdminExecutor

        // ... rest of teardown
        try await super.tearDown()
    }
}
```

### Test Patterns

**Most tests** - Use the global bootstrap (no special setup needed):
```swift
final class MyFeatureTests: XCTestCase {
    func testSomething() {
        // Just write your test - no password prompts!
        let installer = LaunchDaemonInstaller()
        // ... test runs with fake admin executor
    }
}
```

**Tests with custom fakes** - Temporarily replace the executor:
```swift
final class MyEdgeCaseTests: XCTestCase {
    private var originalExecutor: AdminCommandExecutor!

    override func setUp() {
        super.setUp()
        originalExecutor = AdminCommandExecutorHolder.shared
    }

    override func tearDown() {
        AdminCommandExecutorHolder.shared = originalExecutor
        super.tearDown()
    }

    func testFailureCase() {
        // Install custom fake that simulates failure
        let fake = FakeAdminCommandExecutor { _, _ in
            CommandExecutionResult(exitCode: 1, output: "Permission denied")
        }
        AdminCommandExecutorHolder.shared = fake

        // ... test the failure path
    }
}
```

**Smoke tests** - Restore real executors (see "Opting Out" above)

### Verification

After implementation, verify zero password prompts:

```bash
# Run full test suite - should complete without prompts
swift test --parallel

# Run subset that would normally prompt
swift test --filter HelperMaintenanceTests
swift test --filter LogRotationTests

# Run smoke tests that DO use real auth (will prompt)
swift test --filter AuthorizationServicesSmokeTests
```

### Benefits

✅ **CI/CD ready** - Tests run unattended in automation
✅ **Fast local development** - No interruptions during TDD
✅ **Consistent behavior** - Same test results everywhere
✅ **Selective realism** - Smoke tests can still exercise real auth

### Implementation Details

- **Location:** `Tests/TestSupport/AdminPromptBypass.swift`
- **Trigger:** XCTest calls `class func setUp()` once per test bundle
- **Scope:** Global - affects all tests unless explicitly opted out
- **Restoration:** Tests can save/restore executors in their setUp/tearDown

### Related Files

- `AdminPromptBypass.swift` - The global bootstrap implementation
- `AuthorizationServicesSmokeTests.swift` - Example of opting out
- `HelperMaintenanceTests.swift` - Example of custom fake usage
- `LogRotationTests.swift` - Example of custom fake usage
