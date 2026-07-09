@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class CustomRulesStorePersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomRulesStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> CustomRulesStore {
        let url = tempDir.appendingPathComponent("CustomRules.json")
        return CustomRulesStore.testStore(at: url)
    }

    // MARK: - Load: no file → empty

    func testLoadRules_NoFile_ReturnsEmpty() async {
        let store = makeStore()
        let rules = await store.loadRules()
        XCTAssertTrue(rules.isEmpty)
    }

    // MARK: - Save and reload round-trip

    func testSaveAndLoad_PreservesRules() async throws {
        let store = makeStore()
        let rules = [
            CustomRule(input: "caps", action: .keystroke(key: "esc")),
            CustomRule(input: "a", action: .keystroke(key: "b")),
        ]
        try await store.saveRules(rules)

        let store2 = makeStore()
        let loaded = await store2.loadRules()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].input, "caps")
        XCTAssertEqual(loaded[1].input, "a")
    }

    // MARK: - Save empty rules

    func testSaveEmpty_ProducesEmptyOnLoad() async throws {
        let store = makeStore()
        let rules = [
            CustomRule(input: "x", action: .keystroke(key: "y")),
        ]
        try await store.saveRules(rules)
        try await store.saveRules([])

        let store2 = makeStore()
        let loaded = await store2.loadRules()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Preserve rule properties

    func testSaveAndLoad_PreservesAllFields() async throws {
        let store = makeStore()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var rule = CustomRule(
            id: id,
            title: "Test Rule",
            input: "caps",
            action: .keystroke(key: "esc"),
            isEnabled: true,
            notes: "A note",
            createdAt: date
        )
        rule.isEnabled = false

        try await store.saveRules([rule])

        let store2 = makeStore()
        let loaded = await store2.loadRules()
        XCTAssertEqual(loaded.count, 1)
        let r = loaded[0]
        XCTAssertEqual(r.id, id)
        XCTAssertEqual(r.title, "Test Rule")
        XCTAssertEqual(r.input, "caps")
        XCTAssertEqual(r.action, .keystroke(key: "esc"))
        XCTAssertFalse(r.isEnabled)
        XCTAssertEqual(r.notes, "A note")
    }

    // MARK: - Corrupt file

    func testLoadRules_CorruptFile_ReturnsEmpty() async throws {
        let url = tempDir.appendingPathComponent("CustomRules.json")
        try "not json!!!".write(to: url, atomically: true, encoding: .utf8)

        let store = CustomRulesStore.testStore(at: url)
        let loaded = await store.loadRules()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Rules with behaviors

    func testSaveAndLoad_WithDualRoleBehavior() async throws {
        let store = makeStore()
        let rule = CustomRule(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )
        try await store.saveRules([rule])

        let store2 = makeStore()
        let loaded = await store2.loadRules()
        XCTAssertEqual(loaded.count, 1)
        if case let .dualRole(dr) = loaded[0].behavior {
            XCTAssertEqual(dr.tapAction, .keystroke(key: "a"))
            XCTAssertEqual(dr.holdAction, .keystroke(key: "lctl"))
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testSaveAndLoad_WithPackSource() async throws {
        let store = makeStore()
        var rule = CustomRule(input: "f", action: .keystroke(key: "f"))
        rule.packSource = "com.keypath.pack.test"
        try await store.saveRules([rule])

        let store2 = makeStore()
        let loaded = await store2.loadRules()
        XCTAssertEqual(loaded[0].packSource, "com.keypath.pack.test")
    }
}
