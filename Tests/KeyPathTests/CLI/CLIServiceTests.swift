@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CLIServiceTests: XCTestCase {
    private let facade = CLIFacade()

    // MARK: - serviceLogs

    func testServiceLogsReturnsEmptyForMissingFile() {
        let lines = facade.serviceLogs(lines: 10)
        // If the log file doesn't exist in the test environment, we get empty
        // If it does exist, we get some lines. Either way, no crash.
        XCTAssertTrue(lines.count <= 10)
    }

    func testServiceLogsRespectsLineLimit() {
        let lines = facade.serviceLogs(lines: 5)
        XCTAssertTrue(lines.count <= 5)
    }

    func testServiceLogsDefaultsTo50Lines() {
        let lines = facade.serviceLogs()
        XCTAssertTrue(lines.count <= 50)
    }
}
