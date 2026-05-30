@testable import KeyPathAppKit
@testable import KeyPathCore
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

        // TestEnvironment flags
        TestEnvironment.forceTestMode = false
    }
}
