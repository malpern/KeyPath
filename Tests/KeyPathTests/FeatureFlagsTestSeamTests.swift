@testable import KeyPathCore
import XCTest

/// Regression tests for the FeatureFlags test seam (#896 class of bug):
/// while running tests, flag writes must go to an in-memory override store —
/// never process-global `UserDefaults.standard` — and resetTestOverrides()
/// must return every flag to its compiled default.
final class FeatureFlagsTestSeamTests: XCTestCase {
    override func tearDown() {
        FeatureFlags.resetTestOverrides()
        super.tearDown()
    }

    func testSetterDoesNotTouchUserDefaults() {
        let key = "SIMULATOR_AND_VIRTUAL_KEYS_ENABLED"
        let persistedBefore = UserDefaults.standard.object(forKey: key)

        FeatureFlags.setSimulatorAndVirtualKeysEnabled(false)

        XCTAssertFalse(FeatureFlags.simulatorAndVirtualKeysEnabled, "Override must be visible to readers")
        let persistedAfter = UserDefaults.standard.object(forKey: key)
        XCTAssertEqual(
            persistedBefore as? Bool, persistedAfter as? Bool,
            "Setting a flag in tests must not write to UserDefaults.standard"
        )
    }

    func testResetRestoresCompiledDefaults() {
        FeatureFlags.setSimulatorAndVirtualKeysEnabled(false)
        FeatureFlags.setCaptureListenOnlyEnabled(false)
        FeatureFlags.setLearningTipsMode(.alwaysOn)

        FeatureFlags.resetTestOverrides()

        XCTAssertTrue(FeatureFlags.simulatorAndVirtualKeysEnabled, "default ON")
        XCTAssertTrue(FeatureFlags.captureListenOnlyEnabled, "default ON")
        XCTAssertEqual(FeatureFlags.learningTipsMode, .off, "default off")
    }

    func testReadsIgnorePersistedUserDefaultsInTests() {
        // Even if a value is persisted (e.g. left behind by an older test run or
        // the developer's real app), test reads must resolve override-or-default.
        XCTAssertTrue(
            FeatureFlags.simulatorAndVirtualKeysEnabled,
            "With no override set, reads must return the compiled default regardless of UserDefaults"
        )
    }
}
