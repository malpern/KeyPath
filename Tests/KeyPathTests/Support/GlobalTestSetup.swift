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
        // MainAppStateController — most common source of flakiness
        let controller = MainAppStateController.shared
        controller.validationState = nil
        controller.issues = []
        controller.lastValidationDate = nil

        // Device detection caches
        DeviceSelectionCache.shared.reset()
        KeyboardDetectionIndex.resetCache()

        // Authoritative kanata grab status (#630) — read by ServiceHealthChecker,
        // so a value left by one test must not bleed into another's health check.
        KanataGrabStatusStore.shared.reset()

        // Wait-for-exit seams (#625 part-1): safe defaults so any test reaching
        // ServiceLifecycleCoordinator.startKanata neither spawns real `pgrep`
        // (parallel-run deadlock risk) nor waits real time. Tests that exercise the
        // wait-for-exit logic override these explicitly and rely on this reset to
        // avoid bleeding into the next test.
        #if DEBUG
            ServiceLifecycleCoordinator.testPgrepProvider = { _ in [] }
            ServiceLifecycleCoordinator.testLivenessProbe = nil
            ServiceLifecycleCoordinator.testSignal = nil
            ServiceLifecycleCoordinator.testTCPProbe = nil
            ServiceLifecycleCoordinator.testSleep = { _ in }
            ServiceLifecycleCoordinator.testRunningKanataIdentityProvider = nil
            WizardSystemPaths.setBundledKanataPathOverride(nil)

            // ServiceHealthChecker.shared is a process-wide singleton with its own
            // short-lived cache; a real (or forced) health result from one test must
            // not bleed into another's health check.
            ServiceHealthChecker.shared.invalidateHealthCache()
            ServiceHealthChecker.testForcedServiceHealth = nil
            ServiceHealthChecker.runtimeSnapshotOverride = nil
            ServiceHealthChecker.recentlyRestartedOverride = nil
            ServiceHealthChecker.inputCaptureStatusOverride = nil
            ServiceHealthChecker.vhidDriverExtensionEnabledOverride = nil
            ServiceHealthChecker.vhidDriverExtensionStatusOverride = nil
        #endif

        // TestEnvironment flags
        TestEnvironment.forceTestMode = false

        // Feature flags — in tests these live in FeatureFlags' in-memory
        // override store, never UserDefaults (#896); clear to compiled defaults.
        FeatureFlags.resetTestOverrides()
    }
}
