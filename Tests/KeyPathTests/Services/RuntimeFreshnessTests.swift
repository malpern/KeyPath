import KeyPathWizardCore
import XCTest

final class RuntimeFreshnessTests: XCTestCase {
    func testRuntimeFreshnessClassifiesMatchingMismatchedAndMissingEvidence() {
        XCTAssertEqual(RuntimeFreshness.classify(actual: "1.1.0", expected: "1.1.0"), .fresh)
        XCTAssertEqual(RuntimeFreshness.classify(actual: "1.0.0", expected: "1.1.0"), .stale)
        XCTAssertEqual(RuntimeFreshness.classify(actual: nil, expected: "1.1.0"), .unknown)
    }

    func testKanataFreshnessIsDiagnosticAndUsesLiveServiceIdentity() {
        let health = HealthStatus(
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            activeRuntimePathDetail: "com.keypath.KeyPath build 3 · Contents/Library/KeyPath/kanata-launcher",
            kanataServiceFreshness: .stale
        )

        XCTAssertTrue(health.isHealthy)
        XCTAssertEqual(health.kanataServiceFreshness, .stale)
        XCTAssertEqual(
            RuntimeFreshness.classify(
                actual: RuntimeIdentity(
                    programIdentifier: "Contents/Library/KeyPath/kanata-launcher",
                    parentBundleIdentifier: "com.keypath.KeyPath",
                    parentBundleVersion: "3"
                ),
                expected: RuntimeIdentity(
                    programIdentifier: "Contents/Library/KeyPath/kanata-launcher",
                    parentBundleIdentifier: "com.keypath.KeyPath",
                    parentBundleVersion: "4"
                )
            ),
            .stale
        )
    }
}
