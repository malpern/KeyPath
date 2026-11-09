@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
import XCTest

/// Resets shared singleton state to prevent cross-test contamination.
///
/// Called from KeyPathTestCase.setUp and can be called directly by any
/// test that modifies singleton state.
@MainActor
enum TestSingletonReset {
    /// Reset all known mutable singletons to their default state.
    /// Call this in setUp() of any test that touches shared state.
    static func resetAll() {
        // Negative-path tests log expected [ERROR]/[WARN] lines, and the test
        // log guardrail counts them. Keep app logs in the log file unless the
        // run asks for verbose output. (This used to happen by accident: the
        // first CLI test configured CLIRuntimeBootstrap, which turns console
        // logging off process-wide.)
        AppLogger.shared.setConsoleLoggingEnabled(
            ProcessInfo.processInfo.environment["KEYPATH_TEST_VERBOSE_LOGS"] == "1"
        )

        #if DEBUG
            // All configuration-writing harnesses exercise the same fresh real
            // bridge, including services constructed indirectly by managers.
            // An explicit missing/bad path remains a validation failure.
            ConfigurationService.setSessionValidationRuntimeHostForTesting(
                ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"] == nil
                    ? nil : SessionBridgeTestFixture.runtimeHost
            )
        #endif
        // MainAppStateController — most common source of flakiness
        let controller = MainAppStateController.shared
        controller.validationState = nil
        controller.issues = []
        controller.lastValidationDate = nil

        // Device detection caches
        DeviceSelectionCache.shared.reset()
        KeyboardDetectionIndex.resetCache()

        // Session lifecycle tests must never launch or terminate a real application.
        #if DEBUG
            ServiceLifecycleCoordinator.testSessionStart = { _ in false }
            ServiceLifecycleCoordinator.testSessionStop = { true }
            WizardSystemPaths.setBundledKanataPathOverride(nil)
        #endif

        // TestEnvironment flags
        TestEnvironment.forceTestMode = false

        // Feature flags — in tests these live in FeatureFlags' in-memory
        // override store, never UserDefaults (#896); clear to compiled defaults.
        FeatureFlags.resetTestOverrides()
    }
}
