@testable import KeyPathCLI
import XCTest

final class CLIErrorTests: XCTestCase {
    func testErrorEncodesAsJSON() throws {
        let error = CLIError(
            code: .notFound,
            message: "Collection not found",
            hint: "Run 'keypath collection list'",
            details: ["query: 'vim'"],
            docsUrl: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(error)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["code"] as? Int, 5)
        XCTAssertEqual(dict["message"] as? String, "Collection not found")
        XCTAssertEqual(dict["hint"] as? String, "Run 'keypath collection list'")
        XCTAssertNotNil(dict["details"])
    }

    func testAllExitCodesHaveUniqueValues() {
        let allCodes = CLIExitCode.allCases.map(\.rawValue)
        XCTAssertEqual(allCodes.count, Set(allCodes).count, "Exit codes must have unique raw values")
    }

    func testExitCodeRawValues() {
        XCTAssertEqual(CLIExitCode.success.rawValue, 0)
        XCTAssertEqual(CLIExitCode.usage.rawValue, 2)
        XCTAssertEqual(CLIExitCode.validation.rawValue, 3)
        XCTAssertEqual(CLIExitCode.conflict.rawValue, 4)
        XCTAssertEqual(CLIExitCode.notFound.rawValue, 5)
        XCTAssertEqual(CLIExitCode.serviceUnreachable.rawValue, 6)
        XCTAssertEqual(CLIExitCode.permissionBlocked.rawValue, 7)
        XCTAssertEqual(CLIExitCode.kanataInvalid.rawValue, 8)
    }

    func testNotFoundErrorSuggestsListCommand() {
        let error = CLIError.notFound("Collection", query: "vim", listCommand: "keypath collection list")
        XCTAssertEqual(error.code, .notFound)
        XCTAssertTrue(error.hint?.contains("keypath collection list") ?? false)
    }

    func testServiceUnreachableHasHint() {
        let error = CLIError.serviceUnreachable()
        XCTAssertEqual(error.code, .serviceUnreachable)
        XCTAssertNotNil(error.hint)
        XCTAssertFalse(error.hint!.isEmpty)
    }

    func testValidationErrorHasCode3() {
        let error = CLIError.validation("bad config")
        XCTAssertEqual(error.code, .validation)
        XCTAssertEqual(error.code.rawValue, 3)
    }

    func testInvalidKeyErrorHasValidationCode() {
        let error = CLIError.invalidKey("blah", label: "input")
        XCTAssertEqual(error.code, .validation)
        XCTAssertTrue(error.message.contains("blah"))
        XCTAssertTrue(error.message.contains("input"))
    }

    func testKanataInvalidErrorIncludesDetails() {
        let error = CLIError.kanataInvalid(errors: ["line 5: unknown key", "line 12: syntax error"])
        XCTAssertEqual(error.code, .kanataInvalid)
        XCTAssertEqual(error.details?.count, 2)
    }
}
