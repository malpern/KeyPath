@testable import KeyPathCore
import OSLog
import XCTest

/// AppLogger also writes to the unified log, so Console can filter KeyPath by
/// subsystem, category (source file) and level.
final class AppLoggerSystemLogTests: XCTestCase {
    func testWarningsReachTheUnifiedLogWithTheSourceFileAsCategory() throws {
        let token = "applogger-oslog-\(UUID().uuidString)"
        let start = Date().addingTimeInterval(-1)

        AppLogger.writeToSystemLog("warning \(token)", level: .warn, category: "AppLoggerSystemLogTests")

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.composedMessage.contains(token) }
        let entry = try XCTUnwrap(entries.first, "the warning was not found in the unified log")
        XCTAssertEqual(entry.category, "AppLoggerSystemLogTests")
        XCTAssertEqual(entry.level, .error, "os.Logger.warning is recorded at the error level")
    }
}
