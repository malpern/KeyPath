@testable import KeyPathAppKit
import XCTest

final class RuleCollectionStorePersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleCollectionStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> RuleCollectionStore {
        let url = tempDir.appendingPathComponent("RuleCollections.json")
        return RuleCollectionStore.testStore(at: url)
    }

    // MARK: - Load: no file → defaults

    func testLoadCollections_NoFile_ReturnsDefaults() async {
        let store = makeStore()
        let collections = await store.loadCollections()
        XCTAssertFalse(collections.isEmpty)
        let ids = Set(collections.map(\.id))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.macFunctionKeys))
    }

    // MARK: - Save and reload round-trip

    func testSaveAndLoad_PreservesCollections() async throws {
        let store = makeStore()
        var collections = await store.loadCollections()

        // Enable one, disable another
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = false
        }

        try await store.saveCollections(collections)

        let store2 = makeStore()
        let reloaded = await store2.loadCollections()

        let capsReloaded = reloaded.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        let hrmReloaded = reloaded.first(where: { $0.id == RuleCollectionIdentifier.homeRowMods })
        XCTAssertTrue(capsReloaded?.isEnabled ?? false)
        XCTAssertFalse(hrmReloaded?.isEnabled ?? true)
    }

    // MARK: - Corrupt file → resilient recovery

    func testLoadCollections_CorruptFile_FallsBackToDefaults() async throws {
        let url = tempDir.appendingPathComponent("RuleCollections.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = RuleCollectionStore.testStore(at: url)
        let result = await store.loadCollectionsDetailed()
        XCTAssertFalse(result.collections.isEmpty)
        XCTAssertTrue(result.wasFullReset)
    }

    // MARK: - Missing collections get merged from catalog

    func testLoadCollections_MissingDefaults_GetMergedIn() async throws {
        let store = makeStore()
        // Save only one collection
        let justOne = [RuleCollectionCatalog().defaultCollections().first!]
        try await store.saveCollections(justOne)

        let store2 = makeStore()
        let reloaded = await store2.loadCollections()
        XCTAssertGreaterThan(reloaded.count, 1, "Catalog defaults should be merged back in")
        let ids = Set(reloaded.map(\.id))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.capsLockRemap))
    }

    // MARK: - Schema version

    func testSchemaVersion_IsPositive() {
        XCTAssertGreaterThan(RuleCollectionStore.currentSchemaVersion, 0)
    }
}
