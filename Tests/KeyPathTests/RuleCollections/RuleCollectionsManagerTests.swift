@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class RuleCollectionsManagerTests: XCTestCase {
    @MainActor
    func testToggleRehydratesMissingCatalogCollection() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-manager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json"))
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json"))
        let configService = ConfigurationService(configDirectory: tempDir.path)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        // Start with only macOS Function Keys (simulate post-reset subset)
        let catalog = RuleCollectionCatalog()
        let macOnly = catalog.defaultCollections().first {
            $0.id == RuleCollectionIdentifier.macFunctionKeys
        }!
        await manager.replaceCollections([macOnly])
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation })

        // Toggling Vim when missing should rehydrate from catalog and enable it
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })

        // Persisted store should also include the rehydrated collection
        let persisted = await collectionStore.loadCollections()
        XCTAssertTrue(persisted.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })
    }

    func testGenerateConfigIncludesMomentaryActivatorAlias() {
        let catalog = RuleCollectionCatalog()
        let vim = catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.vimNavigation }!

        let config = KanataConfiguration.generateFromCollections([vim])

        XCTAssertTrue(config.contains("(tap-hold 200 200 spc (layer-while-held navigation))"))
        XCTAssertTrue(config.contains("(deflayer navigation"), "Navigation layer block should be emitted")
    }
}
