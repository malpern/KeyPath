import Foundation
@testable import KeyPathAppKit
import XCTest

final class QMKKeyboardDatabaseTests: XCTestCase {
    // MARK: - Rate Limit Error Tests

    func testRateLimitedErrorDescription() {
        let resetDate = Date(timeIntervalSince1970: 1_700_000_000)
        let error = QMKDatabaseError.rateLimited(retryAfter: resetDate)
        XCTAssertTrue(error.errorDescription?.contains("rate limit") ?? false)
    }

    func testNetworkErrorDescription() {
        let error = QMKDatabaseError.networkError("Connection refused")
        XCTAssertEqual(error.errorDescription, "Network error: Connection refused")
    }

    func testParseErrorDescription() {
        let error = QMKDatabaseError.parseError("Invalid JSON structure")
        XCTAssertEqual(error.errorDescription, "Parse error: Invalid JSON structure")
    }

    func testInvalidURLErrorDescription() {
        let error = QMKDatabaseError.invalidURL("Bad URL format")
        XCTAssertEqual(error.errorDescription, "Invalid URL: Bad URL format")
    }

    // MARK: - Search Tests

    func testSearchWithSeededCacheReturnsResults() async throws {
        let database = QMKKeyboardDatabase.shared

        // Seed cache with test data to avoid network calls
        let testKeyboard = KeyboardMetadata(
            id: "test-kb",
            name: "Test Corne",
            manufacturer: "TestMfg",
            tags: ["split"],
            infoJsonURL: URL(string: "https://example.com/info.json")
        )
        await database.seedCache(with: [testKeyboard])

        let results = try await database.searchKeyboards("corne")
        XCTAssertTrue(results.contains { $0.id == "test-kb" }, "Should find seeded keyboard by name")
    }

    func testSearchByManufacturer() async throws {
        let database = QMKKeyboardDatabase.shared

        let testKeyboard = KeyboardMetadata(
            id: "mfg-test",
            name: "Some Board",
            manufacturer: "Foostan",
            tags: [],
            infoJsonURL: URL(string: "https://example.com/info.json")
        )
        await database.seedCache(with: [testKeyboard])

        let results = try await database.searchKeyboards("foostan")
        XCTAssertTrue(results.contains { $0.id == "mfg-test" }, "Should find keyboard by manufacturer")
    }

    func testEmptySearchReturnsKeyboards() async throws {
        let database = QMKKeyboardDatabase.shared
        await database.seedCache(with: [
            KeyboardMetadata(id: "kb1", name: "Board 1"),
            KeyboardMetadata(id: "kb2", name: "Board 2"),
        ])

        let results = try await database.searchKeyboards("")
        XCTAssertFalse(results.isEmpty, "Empty search should return keyboards")
    }
}
