@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CLIExportImportTests: XCTestCase {
    private let facade = CollectionsFacade()
    private var originalCollections: [RuleCollection] = []

    override func setUp() async throws {
        try await super.setUp()
        originalCollections = await RuleCollectionStore.shared.loadCollections()
    }

    override func tearDown() async throws {
        try await RuleCollectionStore.shared.saveCollections(originalCollections)
        try await super.tearDown()
    }

    // MARK: - Export

    func testExportCollectionReturnsJSON() async throws {
        _ = try await facade.createCollection(name: "Export Test", category: "productivity", summary: "For export")
        let exported = try await facade.exportCollection(nameOrId: "Export Test")
        XCTAssertNotNil(exported)
        XCTAssertEqual(exported?.name, "Export Test")
        XCTAssertEqual(exported?.category, "productivity")
        XCTAssertEqual(exported?.summary, "For export")
    }

    func testExportCollectionNotFoundReturnsNil() async throws {
        let exported = try await facade.exportCollection(nameOrId: "NonexistentZZZ")
        XCTAssertNil(exported)
    }

    func testExportAllReturnsAllCollections() async throws {
        _ = try await facade.createCollection(name: "First", category: nil, summary: "")
        _ = try await facade.createCollection(name: "Second", category: nil, summary: "")
        let all = await facade.exportAllCollections()
        XCTAssertTrue(all.count >= 2)
        let names = all.map(\.name)
        XCTAssertTrue(names.contains("First"))
        XCTAssertTrue(names.contains("Second"))
    }

    func testExportCollectionIncludesHomeRowModsConfiguration() async throws {
        var config = HomeRowModsConfig()
        config.holdMode = .layers
        config.hasUserSelectedHoldMode = true
        config.layerAssignments["a"] = "nav"
        config.timing.tapWindow = 240
        config.timing.holdDelay = 260
        config.timing.requirePriorIdleMs = 120
        config.oppositeHandMode = .press

        var collections = await RuleCollectionStore.shared.loadCollections()
        collections.append(RuleCollection(
            name: "Exportable HRM",
            summary: "Config-backed",
            category: .productivity,
            mappings: [],
            configuration: .homeRowMods(config)
        ))
        try await RuleCollectionStore.shared.saveCollections(collections)

        let exportedResult = try await facade.exportCollection(nameOrId: "Exportable HRM")
        let exported = try XCTUnwrap(exportedResult)
        guard case let .homeRowMods(exportedConfig)? = exported.configuration else {
            XCTFail("Expected Home Row Mods configuration in export")
            return
        }
        XCTAssertEqual(exported.mappings.count, 0)
        XCTAssertEqual(exportedConfig.holdMode, .layers)
        XCTAssertEqual(exportedConfig.layerAssignments["a"], "nav")
        XCTAssertEqual(exportedConfig.timing.tapWindow, 240)
        XCTAssertEqual(exportedConfig.timing.holdDelay, 260)
        XCTAssertEqual(exportedConfig.timing.requirePriorIdleMs, 120)
        XCTAssertEqual(exportedConfig.oppositeHandMode, .press)
    }

    func testExportCollectionResolvesHomeRowAlias() async throws {
        var collections = await RuleCollectionStore.shared.loadCollections()
        collections.append(RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "Config-backed",
            category: .productivity,
            mappings: [],
            configuration: .homeRowMods(HomeRowModsConfig())
        ))
        try await RuleCollectionStore.shared.saveCollections(collections)

        let exported = try await facade.exportCollection(nameOrId: "home-row")
        XCTAssertEqual(exported?.name, "Home Row Mods")
    }

    // MARK: - Import

    func testImportCollectionCreatesNew() async throws {
        let exported = CLIExportedCollection(
            from: RuleCollection(
                name: "Imported",
                summary: "From file",
                category: .custom,
                mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))]
            )
        )
        let result = try await facade.importCollection(exported)
        XCTAssertEqual(result.name, "Imported")
        XCTAssertEqual(result.mappingCount, 1)
    }

    func testImportCollectionConflictFail() async throws {
        _ = try await facade.createCollection(name: "Existing", category: nil, summary: "")
        let exported = CLIExportedCollection(
            from: RuleCollection(name: "Existing", summary: "", category: .custom, mappings: [])
        )

        do {
            _ = try await facade.importCollection(exported, onConflict: .fail)
            XCTFail("Expected error")
        } catch is AmbiguousCollectionMatch {
            // Expected
        }
    }

    func testImportCollectionConflictReplace() async throws {
        _ = try await facade.createCollection(name: "Replace Me", category: nil, summary: "old")
        let exported = CLIExportedCollection(
            from: RuleCollection(
                name: "Replace Me",
                summary: "new",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"))]
            )
        )
        let result = try await facade.importCollection(exported, onConflict: .replace)
        XCTAssertEqual(result.name, "Replace Me")
        XCTAssertEqual(result.mappingCount, 1)
    }

    func testImportCollectionConflictSkip() async throws {
        _ = try await facade.createCollection(name: "Keep Me", category: nil, summary: "original")
        let exported = CLIExportedCollection(
            from: RuleCollection(name: "Keep Me", summary: "new", category: .custom, mappings: [])
        )
        let result = try await facade.importCollection(exported, onConflict: .skip)
        XCTAssertEqual(result.name, "Keep Me")
    }

    // MARK: - Round-trip

    func testExportImportRoundTrip() async throws {
        _ = try await facade.createCollection(name: "Round Trip", category: "navigation", summary: "Test round trip")

        let exported = try await facade.exportCollection(nameOrId: "Round Trip")
        XCTAssertNotNil(exported)

        // Encode to JSON and back
        let encoder = JSONEncoder()
        let data = try encoder.encode(exported!)
        let decoded = try JSONDecoder().decode(CLIExportedCollection.self, from: data)

        XCTAssertEqual(decoded.name, "Round Trip")
        XCTAssertEqual(decoded.category, "navigation")
        XCTAssertEqual(decoded.summary, "Test round trip")

        // Delete and reimport
        _ = try await facade.deleteCollection(nameOrId: "Round Trip")
        let imported = try await facade.importCollection(decoded)
        XCTAssertEqual(imported.name, "Round Trip")
    }

    func testExportImportRoundTripPreservesConfiguration() throws {
        var config = HomeRowModsConfig()
        config.holdMode = .layers
        config.layerAssignments["f"] = "nav"
        config.timing.holdDelay = 260

        let collection = RuleCollection(
            name: "Round Trip HRM",
            summary: "Config-backed",
            category: .productivity,
            mappings: [],
            configuration: .homeRowMods(config)
        )
        let exported = CLIExportedCollection(from: collection)

        let encoder = JSONEncoder()
        let data = try encoder.encode(exported)
        let decoded = try JSONDecoder().decode(CLIExportedCollection.self, from: data)
        let restored = decoded.toRuleCollection()

        guard case let .homeRowMods(restoredConfig) = restored.configuration else {
            XCTFail("Expected Home Row Mods configuration after round trip")
            return
        }
        XCTAssertEqual(restoredConfig.holdMode, .layers)
        XCTAssertEqual(restoredConfig.layerAssignments["f"], "nav")
        XCTAssertEqual(restoredConfig.timing.holdDelay, 260)
    }
}
