@testable import KeyPathCore
import XCTest

/// Tests for TestEnvironment detection logic.
/// Verifies that test mode is correctly detected when running tests,
/// and documents the detection mechanism to prevent regressions.
final class TestEnvironmentDetectionTests: XCTestCase {
    func testIsRunningTests_TrueInTestContext() {
        XCTAssertTrue(
            TestEnvironment.isRunningTests,
            "Should detect test environment when running inside XCTest"
        )
    }

    func testIsTestMode_TrueInTestContext() {
        XCTAssertTrue(TestEnvironment.isTestMode)
    }

    func testDetection_UsesXCTestBundleNotClassCheck() {
        // The detection should use Bundle.allBundles checking for .xctest suffix,
        // NOT NSClassFromString("XCTestCase"), because on macOS 26+ the system
        // loads XCTestSupport.framework into all apps, making the class check
        // unreliable (returns true in production).
        let hasXCTestBundle = Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
        XCTAssertTrue(
            hasXCTestBundle,
            "Should find .xctest bundle when running tests (this is how detection works)"
        )
    }

    func testDetection_StrongSignalsSufficeWithoutLeakProneEnvVars() {
        // isRunningTests must never rely on env vars that can leak from a dev
        // shell into a real app launch (KEYPATH_USE_SUDO,
        // __XCODE_BUILT_PRODUCTS_DIR_PATHS, DYLD_LIBRARY_PATH containing
        // ".build"). A false positive redirects real user data into a purgeable
        // temp sandbox via AppPaths. This test verifies every real test run
        // carries at least one strong signal besides the CI env vars, so the
        // leak-prone vars are never needed for detection.
        let strongSignals = TestEnvironment.detectionSignals.filter { $0.name != "ci-environment" }
        XCTAssertTrue(
            strongSignals.contains(where: \.present),
            """
            No strong test signal present in this test run. If detection needs a \
            new signal for this runner, add an in-process or explicitly \
            test-scoped one — do NOT reintroduce leak-prone env vars like \
            KEYPATH_USE_SUDO or DYLD_LIBRARY_PATH.
            """
        )
        XCTAssertTrue(TestEnvironment.isRunningTests)
    }

    @MainActor
    func testForceTestMode_CanBeToggled() {
        let original = TestEnvironment.forceTestMode
        defer { TestEnvironment.forceTestMode = original }

        TestEnvironment.forceTestMode = true
        XCTAssertTrue(TestEnvironment.isTestMode)

        TestEnvironment.forceTestMode = false
        // isTestMode is still true because isRunningTests is true
        XCTAssertTrue(TestEnvironment.isTestMode)
    }
}
