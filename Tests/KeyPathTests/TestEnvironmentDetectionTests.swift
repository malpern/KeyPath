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
