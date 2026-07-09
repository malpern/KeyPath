@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

final class RuleCollectionStoreTests: XCTestCase {
    func testLoadFallsBackToDefaultsWhenFileMissing() async {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        let store = RuleCollectionStore.testStore(at: tempURL)

        let collections = await store.loadCollections()

        XCTAssertFalse(collections.isEmpty, "Default catalog should be returned when file missing")
        XCTAssertEqual(collections.first?.name, "macOS Function Keys")
    }

    func testSaveAndLoadRoundTrip() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let store = RuleCollectionStore.testStore(at: fileURL)

        let sample = [
            RuleCollection(
                name: "Custom",
                summary: "User rules",
                category: .custom,
                mappings: [
                    KeyMapping(input: "caps_lock", action: .keystroke(key: "escape")),
                    KeyMapping(input: "left_shift", action: .keystroke(key: "hyper"))
                ],
                isEnabled: true,
                isSystemDefault: false,
                icon: "star"
            )
        ]

        try await store.saveCollections(sample)
        let loaded = await store.loadCollections()

        let loadedIDs = Set(loaded.map(\.id))
        let sampleIDs = Set(sample.map(\.id))
        let catalogIDs = Set(RuleCollectionCatalog().defaultCollections().map(\.id))

        XCTAssertTrue(
            loadedIDs.isSuperset(of: sampleIDs),
            "Persisted collections should remain present after load"
        )
        XCTAssertTrue(
            loadedIDs.isSuperset(of: catalogIDs),
            "Loaded collections should also include catalog defaults"
        )
    }

    func testLoadUpgradesBuiltInCollectionsWithLatestMetadata() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let legacyEntry: [String: Any] = [
            "id": RuleCollectionIdentifier.vimNavigation.uuidString,
            "name": "Vim Navigation",
            "summary": "Legacy",
            "category": RuleCollectionCategory.navigation.rawValue,
            "mappings": [
                ["id": UUID().uuidString, "input": "h", "action": ["keystroke": ["key": "left"]]]
            ],
            "isEnabled": true,
            "isSystemDefault": false,
            "icon": "arrow"
        ]

        let data = try JSONSerialization.data(withJSONObject: [legacyEntry])
        try data.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let loaded = await store.loadCollections()

        let vim = loaded.first { $0.id == RuleCollectionIdentifier.vimNavigation }
        XCTAssertNotNil(vim)
        XCTAssertEqual(vim?.targetLayer, .navigation)
        XCTAssertEqual(vim?.momentaryActivator?.input, "space")
        XCTAssertEqual(vim?.momentaryActivator?.targetLayer, .navigation)
        XCTAssertEqual(vim?.activationHint, "Hold Leader key to enter Navigation layer")
    }

    func testSaveWritesVersionedFormat() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let store = RuleCollectionStore.testStore(at: fileURL)
        let sample = [
            RuleCollection(
                name: "Test",
                summary: "Test",
                category: .custom,
                mappings: [],
                isEnabled: true,
                isSystemDefault: false,
                icon: "star"
            ),
        ]

        try await store.saveCollections(sample)

        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Saved file should be a JSON object, not an array")
        XCTAssertEqual(json?["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(json?["collections"] as? [[String: Any]])
    }

    func testLoadReadsVersionedFormat() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let store = RuleCollectionStore.testStore(at: fileURL)
        let catalog = RuleCollectionCatalog()
        let defaults = catalog.defaultCollections()

        try await store.saveCollections(defaults)
        let loaded = await store.loadCollections()

        let loadedIDs = Set(loaded.map(\.id))
        let defaultIDs = Set(defaults.map(\.id))
        XCTAssertEqual(loadedIDs, defaultIDs, "Versioned round-trip should preserve all collections")
    }

    // MARK: - Resilient Decode Tests

    func testLoadRecoversSurvivingCollectionsWhenOneIsBroken() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        // Build a versioned JSON with one valid collection and one broken one
        let catalog = RuleCollectionCatalog()
        let validCollection = try XCTUnwrap(catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.macFunctionKeys })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let validData = try encoder.encode(validCollection)
        let validJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: validData) as? [String: Any])

        // Broken collection: category is an int (should be string), causing decode failure
        let brokenCollection: [String: Any] = [
            "id": RuleCollectionIdentifier.homeRowMods.uuidString,
            "name": "Home Row Mods",
            "summary": "Test",
            "category": 999,
            "mappings": [],
            "isEnabled": true,
            "isSystemDefault": false
        ]

        let versioned: [String: Any] = [
            "schemaVersion": 1,
            "collections": [validJSON, brokenCollection]
        ]
        let data = try JSONSerialization.data(withJSONObject: versioned)
        try data.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let result = await store.loadCollectionsDetailed()

        // The valid collection should survive
        XCTAssertTrue(
            result.collections.contains { $0.id == RuleCollectionIdentifier.macFunctionKeys },
            "Valid collection should be preserved"
        )
        // The broken one should be reported
        XCTAssertEqual(result.failedCollectionNames, ["Home Row Mods"])
        XCTAssertFalse(result.wasFullReset)
    }

    func testLoadCreatesBackupWhenDecodePartiallyFails() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        // Write versioned JSON with a broken collection (category is wrong type)
        let brokenCollection: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Broken Rule",
            "summary": "Will fail",
            "category": 999,
            "mappings": [],
            "isEnabled": true,
            "isSystemDefault": false
        ]
        let versioned: [String: Any] = [
            "schemaVersion": 1,
            "collections": [brokenCollection]
        ]
        let data = try JSONSerialization.data(withJSONObject: versioned)
        try data.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let result = await store.loadCollectionsDetailed()

        XCTAssertNotNil(result.backupPath, "Backup should be created when decode fails")
        if let path = result.backupPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Backup file should exist on disk")
        }
    }

    func testLoadReturnsDefaultsForCompletelyCorruptFile() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let garbageData = try XCTUnwrap("this is not json at all".data(using: .utf8))
        try garbageData.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let result = await store.loadCollectionsDetailed()

        XCTAssertFalse(result.collections.isEmpty, "Should fall back to catalog defaults")
        XCTAssertTrue(result.wasFullReset, "Should report full reset for unreadable file")
        XCTAssertNotNil(result.backupPath, "Should backup even on full reset")
    }

    func testLoadPreservesEnabledStateWhenSiblingCollectionFails() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let catalog = RuleCollectionCatalog()
        // Take a normally-disabled collection and enable it
        var capsLock = try XCTUnwrap(catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.capsLockRemap })
        capsLock = RuleCollection(
            id: capsLock.id,
            name: capsLock.name,
            summary: capsLock.summary,
            category: capsLock.category,
            mappings: capsLock.mappings,
            isEnabled: true,
            isSystemDefault: capsLock.isSystemDefault,
            icon: capsLock.icon,
            configuration: capsLock.configuration
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let validJSON = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: encoder.encode(capsLock)
        ) as? [String: Any])

        let brokenJSON: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Broken",
            "summary": "x",
            "category": 999,
            "mappings": [],
            "isEnabled": true,
            "isSystemDefault": false
        ]

        let versioned: [String: Any] = [
            "schemaVersion": 1,
            "collections": [validJSON, brokenJSON]
        ]
        try JSONSerialization.data(withJSONObject: versioned).write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let result = await store.loadCollectionsDetailed()

        let capsResult = result.collections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertNotNil(capsResult)
        XCTAssertTrue(capsResult?.isEnabled == true, "Enabled state should survive sibling decode failure")
    }

    func testLoadAddsMissingCatalogDefaultsWhenFileHasSubset() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let catalog = RuleCollectionCatalog()
        guard let macOnly = catalog.defaultCollections().first(
            where: { $0.id == RuleCollectionIdentifier.macFunctionKeys }
        ) else {
            XCTFail("Missing macOS Function Keys in catalog")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([macOnly])
        try data.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let loaded = await store.loadCollections()

        let loadedIDs = Set(loaded.map(\.id))
        let defaultIDs = Set(catalog.defaultCollections().map(\.id))

        XCTAssertEqual(
            defaultIDs, loadedIDs,
            "Loading should merge persisted subset with all catalog defaults (including new ones)"
        )
    }
}
