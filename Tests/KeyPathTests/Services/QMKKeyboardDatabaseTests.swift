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

    // MARK: - Search with Custom Layouts

    func testSearchIncludesCustomLayouts() async throws {
        // Create a sample custom layout in the store (uses .standard, matching QMKKeyboardDatabase)
        let sampleJSON = """
        {
          "id": "test-custom",
          "name": "My Custom Board",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "keyCode": 18, "label": "1"},
                {"row": 0, "col": 1, "x": 1, "y": 0, "keyCode": 19, "label": "2"}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let storedLayout = StoredLayout(
            id: "test-uuid",
            name: "My Custom Board",
            sourceURL: nil,
            layoutJSON: sampleJSON,
            layoutVariant: nil
        )

        let store = CustomLayoutStore(layouts: [storedLayout])
        store.save()

        defer {
            CustomLayoutStore(layouts: []).save()
        }

        // Seed the cache so searchKeyboards doesn't trigger network calls
        let database = QMKKeyboardDatabase.shared
        await database.seedCache(with: [])

        let results = try await database.searchKeyboards("My Custom Board")

        // Custom layouts matching the query should appear in results
        let customResults = results.filter { $0.id.hasPrefix("custom-") }
        XCTAssertFalse(customResults.isEmpty, "Search should include matching custom layouts")
        XCTAssertTrue(customResults.contains { $0.name == "My Custom Board" })
    }

    func testEmptySearchIncludesCustomLayouts() async throws {
        let sampleJSON = """
        {
          "id": "empty-search-test",
          "name": "Empty Search Test Board",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "keyCode": 18, "label": "1"}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let storedLayout = StoredLayout(
            id: "empty-search-uuid",
            name: "Empty Search Test Board",
            sourceURL: nil,
            layoutJSON: sampleJSON,
            layoutVariant: nil
        )

        let store = CustomLayoutStore(layouts: [storedLayout])
        store.save()

        defer {
            CustomLayoutStore(layouts: []).save()
        }

        // Seed the cache so searchKeyboards doesn't trigger network calls
        let database = QMKKeyboardDatabase.shared
        await database.seedCache(with: [])

        let results = try await database.searchKeyboards("")

        // Empty query should return custom layouts at the top
        let customResults = results.filter { $0.id.hasPrefix("custom-") }
        XCTAssertFalse(customResults.isEmpty, "Empty search should include custom layouts")
    }
}
