@testable import KeyPathAppKit
import XCTest

final class KeyboardDisplayContextStoreTests: KeyPathTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardDisplayContextStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
    }

    func testSaveLoadAndRemoveContext() async throws {
        let tempURL = tempDir.appendingPathComponent("KeyboardDisplayContexts.json")
        let store = KeyboardDisplayContextStore.testStore(at: tempURL)

        let context = KeyboardDisplayContextStore.Context(
            vendorProductKey: "29EA:1001",
            layoutId: "kinesis-mwave",
            keymapId: "graphite",
            includePunctuationStore: "{\"graphite\":true}",
            keyboardName: "Kinesis mWave",
            updatedAt: Date()
        )

        try await store.saveContext(context)

        let loaded = await store.context(vendorProductKey: "29EA:1001")
        XCTAssertEqual(loaded?.layoutId, "kinesis-mwave")
        XCTAssertEqual(loaded?.keymapId, "graphite")
        XCTAssertEqual(loaded?.includePunctuationStore, "{\"graphite\":true}")

        try await store.removeContext(vendorProductKey: "29EA:1001")
        let removed = await store.context(vendorProductKey: "29EA:1001")
        XCTAssertNil(removed)
    }

    func testSavingContextReplacesSameDeviceLayoutAndKeymap() async throws {
        let tempURL = tempDir.appendingPathComponent("KeyboardDisplayContexts.json")
        let store = KeyboardDisplayContextStore.testStore(at: tempURL)

        try await store.saveContext(KeyboardDisplayContextStore.Context(
            vendorProductKey: "05AC:0341",
            layoutId: "macbook-us",
            keymapId: "qwerty",
            includePunctuationStore: "{\"qwerty\":true}",
            keyboardName: "Apple Internal Keyboard",
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        try await store.saveContext(KeyboardDisplayContextStore.Context(
            vendorProductKey: "05AC:0341",
            layoutId: "macbook-jis",
            keymapId: "dvorak",
            includePunctuationStore: "{\"dvorak\":false}",
            keyboardName: "Apple Internal Keyboard",
            updatedAt: Date(timeIntervalSince1970: 2)
        ))

        let contexts = await store.allContexts()
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.layoutId, "macbook-jis")
        XCTAssertEqual(contexts.first?.keymapId, "dvorak")
        XCTAssertEqual(contexts.first?.includePunctuationStore, "{\"dvorak\":false}")
    }

    func testMalformedContextFileLoadsEmpty() async throws {
        let tempURL = tempDir.appendingPathComponent("KeyboardDisplayContexts.json")
        try "not-json".write(to: tempURL, atomically: true, encoding: .utf8)
        let store = KeyboardDisplayContextStore.testStore(at: tempURL)

        let contexts = await store.allContexts()
        let missingContext = await store.context(vendorProductKey: "05AC:0341")

        XCTAssertTrue(contexts.isEmpty)
        XCTAssertNil(missingContext)
    }
}
