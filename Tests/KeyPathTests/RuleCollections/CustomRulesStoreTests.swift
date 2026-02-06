@testable import KeyPathAppKit
@preconcurrency import XCTest

final class CustomRulesStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: CustomRulesStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = CustomRulesStore(fileURL: tempDirectory.appendingPathComponent("CustomRules.json"))
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        store = nil
    }

    func testLoadReturnsEmptyWhenFileMissing() async {
        let loaded = await store.loadRules()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let fixedDate = Date(timeIntervalSince1970: 0) // Truncated to seconds to survive ISO8601 encode/decode
        let rules = [
            CustomRule(
                title: "Caps Escape", input: "caps", output: "escape", createdAt: fixedDate
            ),
            CustomRule(
                title: "Space Nav", input: "space", output: "nav", isEnabled: false,
                createdAt: fixedDate
            )
        ]

        try await store.saveRules(rules)
        let loaded = await store.loadRules()
        XCTAssertEqual(loaded, rules)
    }

    func testLoadGracefullyHandlesCorruptData() async throws {
        let url = tempDirectory.appendingPathComponent("CustomRules.json")
        try "not-json".write(to: url, atomically: true, encoding: .utf8)

        let loaded = await store.loadRules()
        XCTAssertTrue(loaded.isEmpty)
    }
}
