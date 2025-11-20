@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Global test bootstrap to suppress password dialogs in routine tests.
///
/// This class configures the test environment to bypass admin privilege prompts
/// by installing fake executors and overrides. Tests run without interruption
/// unless explicitly opted out.
///
/// ## How It Works
/// - Installs FakeAdminCommandExecutor globally for all tests
/// - Disables real admin operations via TestEnvironment flag
/// - Sets KEYPATH_TEST_MODE=1 for consistent test behavior
/// - Configures LaunchDaemonInstaller to skip authorization scripts
///
/// ## Opting Out
/// Tests that need real Authorization Services behavior (e.g., smoke tests)
/// must explicitly restore the real executor and overrides in their setUp():
///
/// ```swift
/// override func setUp() {
///     super.setUp()
///     AdminCommandExecutorHolder.shared = DefaultAdminCommandExecutor()
///     LaunchDaemonInstaller.authorizationScriptRunnerOverride = realRunner
///     TestEnvironment.allowAdminOperationsInTests = true
/// }
/// ```
///
/// ## Why This Exists
/// Without this bootstrap, running the full test suite triggers multiple
/// password dialogs as tests exercise installation flows. This creates:
/// - Unusable CI/CD pipelines (no way to input passwords)
/// - Developer friction (constant interruptions during local test runs)
/// - Flaky tests (timeouts waiting for human input)
///
/// By default, we want tests to run fast and unattended. Only specific
/// smoke tests should exercise the real authorization code path.
@MainActor
class AdminPromptBypass: XCTestCase {
    /// Runs once for the entire test bundle before any tests execute.
    /// Installs global overrides to suppress password dialogs.
    override class func setUp() {
        super.setUp()

        // Install fake admin executor that succeeds without prompts
        let fakeExecutor = FakeAdminCommandExecutor { _, _ in
            // All admin commands succeed silently in tests
            CommandExecutionResult(exitCode: 0, output: "")
        }
        AdminCommandExecutorHolder.shared = fakeExecutor

        // Configure LaunchDaemonInstaller to skip authorization script execution
        LaunchDaemonInstaller.authorizationScriptRunnerOverride = { _ in
            // Always succeed without running real osascript
            true
        }

        // Disable actual admin operations (file writes to /Library, etc.)
        TestEnvironment.allowAdminOperationsInTests = false

        // Ensure consistent test mode behavior
        setenv("KEYPATH_TEST_MODE", "1", 1)

        print("✅ [TestBootstrap] Admin prompt bypass installed globally")
        print("   - FakeAdminCommandExecutor active")
        print("   - Authorization scripts bypassed")
        print("   - Admin operations disabled")
        print("   - KEYPATH_TEST_MODE=1")
    }
}

/// Fake admin command executor for tests that always succeeds without prompts.
///
/// Used by the global test bootstrap to prevent password dialogs during
/// routine test execution.
private class FakeAdminCommandExecutor: AdminCommandExecutor {
    private let resultProvider: (String, String) -> CommandExecutionResult

    init(resultProvider: @escaping (String, String) -> CommandExecutionResult = { _, _ in
        CommandExecutionResult(exitCode: 0, output: "")
    }) {
        self.resultProvider = resultProvider
    }

    func executeWithAdminPrivileges(
        command: String,
        description: String
    ) async -> CommandExecutionResult {
        // Return fake success without showing password dialog
        resultProvider(command, description)
    }
}
