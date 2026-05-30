@testable import KeyPathAppKit
import XCTest

final class ConfigApplyTypesExtendedTests: XCTestCase {
    // MARK: - ApplyResult

    func testApplyResult_SuccessDefaults() {
        let result = ApplyResult(success: true)
        XCTAssertTrue(result.success)
        XCTAssertFalse(result.rolledBack)
        XCTAssertNil(result.error)
        XCTAssertNil(result.diagnostics)
    }

    func testApplyResult_FailureWithRollback() {
        let result = ApplyResult(
            success: false,
            rolledBack: true,
            error: .writeFailed(message: "disk full")
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.rolledBack)
        XCTAssertEqual(result.error, .writeFailed(message: "disk full"))
    }

    func testApplyResult_Equality() {
        let a = ApplyResult(success: true)
        let b = ApplyResult(success: true)
        let c = ApplyResult(success: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ConfigError

    func testConfigError_AllCasesAreDistinct() {
        let errors: [ConfigError] = [
            .preWriteValidationFailed(message: "bad"),
            .writeFailed(message: "bad"),
            .postWriteValidationFailed(message: "bad"),
            .reloadFailed(message: "bad"),
            .readinessTimeout(message: "bad"),
            .healthCheckFailed(message: "bad"),
        ]
        for (i, a) in errors.enumerated() {
            for (j, b) in errors.enumerated() where i != j {
                XCTAssertNotEqual(a, b, "Error cases \(i) and \(j) should differ")
            }
        }
    }

    func testConfigError_Equality_SameCase() {
        XCTAssertEqual(
            ConfigError.writeFailed(message: "x"),
            ConfigError.writeFailed(message: "x")
        )
        XCTAssertNotEqual(
            ConfigError.writeFailed(message: "x"),
            ConfigError.writeFailed(message: "y")
        )
    }

    // MARK: - ConfigDiagnostics

    func testConfigDiagnostics_DefaultTimestamp() {
        let before = Date()
        let diag = ConfigDiagnostics()
        let after = Date()
        XCTAssertGreaterThanOrEqual(diag.timestamp, before)
        XCTAssertLessThanOrEqual(diag.timestamp, after)
    }

    func testConfigDiagnostics_AllFields() {
        let diag = ConfigDiagnostics(
            configPathBefore: "/old/path",
            configPathAfter: "/new/path",
            mappingCountBefore: 5,
            mappingCountAfter: 7,
            validationOutput: "all good"
        )
        XCTAssertEqual(diag.configPathBefore, "/old/path")
        XCTAssertEqual(diag.configPathAfter, "/new/path")
        XCTAssertEqual(diag.mappingCountBefore, 5)
        XCTAssertEqual(diag.mappingCountAfter, 7)
        XCTAssertEqual(diag.validationOutput, "all good")
    }

    func testConfigDiagnostics_Equality() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = ConfigDiagnostics(mappingCountBefore: 3, timestamp: date)
        let b = ConfigDiagnostics(mappingCountBefore: 3, timestamp: date)
        XCTAssertEqual(a, b)
    }

    // MARK: - ConfigEditCommand

    func testConfigEditCommand_ReplaceConfigText_Equality() {
        let a = ConfigEditCommand.replaceConfigText("hello")
        let b = ConfigEditCommand.replaceConfigText("hello")
        let c = ConfigEditCommand.replaceConfigText("world")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testConfigEditCommand_ToggleSimpleMapping_Equality() {
        let id = UUID()
        let a = ConfigEditCommand.toggleSimpleMapping(id: id, enabled: true)
        let b = ConfigEditCommand.toggleSimpleMapping(id: id, enabled: true)
        let c = ConfigEditCommand.toggleSimpleMapping(id: id, enabled: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testConfigEditCommand_RemoveSimpleMapping_Equality() {
        let id = UUID()
        let a = ConfigEditCommand.removeSimpleMapping(id: id)
        let b = ConfigEditCommand.removeSimpleMapping(id: id)
        let c = ConfigEditCommand.removeSimpleMapping(id: UUID())
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
