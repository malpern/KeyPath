import XCTest
@testable import KeyPath
import KeyPathCore

final class ConfigApplyTypesTests: XCTestCase {
    func testFeatureFlagDefaultsOff() {
        // Ensure default is false when unset
        UserDefaults.standard.removeObject(forKey: "USE_CONFIG_APPLY_PIPELINE")
        XCTAssertFalse(FeatureFlags.useConfigApplyPipeline)
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


