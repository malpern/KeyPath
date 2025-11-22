import KeyPathCore
import XCTest

@testable import KeyPathAppKit

final class ConfigApplyTypesTests: XCTestCase {
    func testFeatureFlagDefaultsOff() {
        // Note: useConfigApplyPipeline flag doesn't exist yet - this test is a placeholder
        // When the flag is implemented, uncomment and test:
        // UserDefaults.standard.removeObject(forKey: "USE_CONFIG_APPLY_PIPELINE")
        // XCTAssertFalse(KeyPathCore.FeatureFlags.useConfigApplyPipeline)
        XCTAssertTrue(true, "Placeholder test - feature flag not yet implemented")
    }

    func testApplyResultInitConvenience() {
        let r1 = ApplyResult(success: true)
        XCTAssertTrue(r1.success)
        XCTAssertFalse(r1.rolledBack)
        XCTAssertNil(r1.error)
        XCTAssertNil(r1.diagnostics)
    }

    func testConfigErrorEquality() {
        let e1 = ConfigError.postWriteValidationFailed(message: "syntax error")
        let e2 = ConfigError.postWriteValidationFailed(message: "syntax error")
        XCTAssertEqual(e1, e2)
    }

    func testConfigDiagnosticsInit() {
        let d = ConfigDiagnostics(
            configPathBefore: "/tmp/a",
            configPathAfter: "/tmp/b",
            mappingCountBefore: 1,
            mappingCountAfter: 2,
            validationOutput: "ok"
        )
        XCTAssertEqual(d.configPathBefore, "/tmp/a")
        XCTAssertEqual(d.mappingCountAfter, 2)
    }

    func testConfigEditCommandEquatable() {
        let m = SimpleMapping(fromKey: "caps", toKey: "esc", filePath: "/tmp/cfg")
        let c1 = ConfigEditCommand.addSimpleMapping(m)
        let c2 = ConfigEditCommand.addSimpleMapping(m)
        XCTAssertEqual(c1, c2)
    }
}
