@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import XCTest

final class AliasDeduplicationTests: XCTestCase {
    // MARK: - deduplicateAliases (safety net)

    func testNoDuplicatesPassesThrough() {
        let aliases = [
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_a", definition: "(tap-hold 200 200 a lsft)"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_s", definition: "(tap-hold 200 200 s lctl)"),
        ]

        let result = KanataConfiguration.deduplicateAliases(aliases)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].aliasName, "beh_base_a")
        XCTAssertEqual(result[1].aliasName, "beh_base_s")
    }

    func testDuplicateAliasSafetyNetKeepsLastDefinition() {
        let aliases = [
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_;", definition: "(tap-hold 200 200 ; rsft)", comment: "home row mod"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_a", definition: "(tap-hold 200 200 a lsft)"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_;", definition: "(tap-hold 150 ; (layer-while-held fun))", comment: "layer toggle"),
        ]

        let result = KanataConfiguration.deduplicateAliases(aliases)

        XCTAssertEqual(result.count, 2, "Safety net should keep 2 unique aliases")
        XCTAssertEqual(result[0].aliasName, "beh_base_;")
        XCTAssertTrue(result[0].definition.contains("layer-while-held fun"), "Last definition should win in safety net")
    }

    func testEmptyInputReturnsEmpty() {
        let result = KanataConfiguration.deduplicateAliases([])
        XCTAssertTrue(result.isEmpty)
    }

    func testPreservesInsertionOrder() {
        let aliases = [
            KanataConfiguration.AliasDefinition(aliasName: "z_alias", definition: "z"),
            KanataConfiguration.AliasDefinition(aliasName: "a_alias", definition: "a"),
            KanataConfiguration.AliasDefinition(aliasName: "m_alias", definition: "m"),
        ]

        let result = KanataConfiguration.deduplicateAliases(aliases)

        XCTAssertEqual(result.map(\.aliasName), ["z_alias", "a_alias", "m_alias"])
    }

    // MARK: - Conflict detection (effectiveMappings)

    func testDetectsConflictBetweenHRMAndLayerToggles() {
        let hrmCollection = makeCollection(
            name: "Home Row Mods",
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: [";", "a"],
                modifierAssignments: [";": "rsft", "a": "lsft"],
                holdMode: .modifiers
            ))
        )

        let layerTogglesCollection = makeCollection(
            name: "Home Row Layer Toggles",
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: [";", "a"],
                layerAssignments: [";": "fun", "a": "fun"]
            ))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [
            hrmCollection, layerTogglesCollection,
        ])

        XCTAssertFalse(conflicts.isEmpty, "Should detect conflicts when HRM and Layer Toggles share keys")
        XCTAssertEqual(conflicts.count, 2, "Should detect 2 conflicting keys (; and a)")

        let semicolonConflict = conflicts.first { $0.inputKey == ";" }
        XCTAssertNotNil(semicolonConflict)
        XCTAssertEqual(semicolonConflict?.conflictingCollections.count, 2)
        XCTAssertTrue(semicolonConflict?.conflictingCollections.contains("Home Row Mods") ?? false)
        XCTAssertTrue(semicolonConflict?.conflictingCollections.contains("Home Row Layer Toggles") ?? false)
    }

    func testNoConflictWhenCollectionsUseDistinctKeys() {
        let hrmCollection = makeCollection(
            name: "Home Row Mods",
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a", "s"],
                modifierAssignments: ["a": "lsft", "s": "lctl"],
                holdMode: .modifiers
            ))
        )

        let layerTogglesCollection = makeCollection(
            name: "Home Row Layer Toggles",
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: ["j", "k"],
                layerAssignments: ["j": "nav", "k": "sym"]
            ))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [
            hrmCollection, layerTogglesCollection,
        ])

        XCTAssertTrue(conflicts.isEmpty, "No conflicts when collections use distinct keys")
    }

    // MARK: - User-friendly conflict explanation

    func testConflictExplanationIncludesCollectionNames() {
        let conflict = KeyPathError.MappingConflictInfo(
            inputKey: ";",
            layer: "Base",
            conflictingCollections: ["Home Row Mods", "Home Row Layer Toggles"],
            holdDescriptions: ["Home Row Mods: hold → rsft", "Home Row Layer Toggles: hold → (layer-while-held fun)"]
        )

        let explanation = conflict.userExplanation

        XCTAssertTrue(explanation.contains("Home Row Mods"), "Should mention first collection")
        XCTAssertTrue(explanation.contains("Home Row Layer Toggles"), "Should mention second collection")
        XCTAssertTrue(explanation.contains("\";\"\u{20}key"), "Should mention the conflicting key")
        XCTAssertTrue(explanation.contains("hold → rsft"), "Should describe what first collection does")
        XCTAssertTrue(explanation.contains("hold → (layer-while-held fun)"), "Should describe what second collection does")
        XCTAssertTrue(explanation.contains("disable one"), "Should suggest disabling one")
        XCTAssertTrue(explanation.contains("key assignments"), "Should suggest changing key assignments")
    }

    func testConflictExplanationWithoutHoldDescriptions() {
        let conflict = KeyPathError.MappingConflictInfo(
            inputKey: "a",
            layer: "Base",
            conflictingCollections: ["Custom Rules", "Home Row Mods"]
        )

        let explanation = conflict.userExplanation

        XCTAssertTrue(explanation.contains("Custom Rules"))
        XCTAssertTrue(explanation.contains("Home Row Mods"))
        XCTAssertTrue(explanation.contains("only have one action assigned"))
    }

    // MARK: - Integration: config gen safety net still works

    func testConfigGenSafetyNetProducesValidConfig() {
        let hrmCollection = makeCollection(
            name: "Home Row Mods",
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: [";", "a"],
                modifierAssignments: [";": "rsft", "a": "lsft"],
                holdMode: .modifiers
            ))
        )

        let layerTogglesCollection = makeCollection(
            name: "Home Row Layer Toggles",
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: [";", "a"],
                layerAssignments: [";": "fun", "a": "fun"]
            ))
        )

        // generateFromCollections doesn't run detectConflicts (that's in saveConfiguration),
        // but the safety net deduplicateAliases prevents duplicate alias names
        let config = KanataConfiguration.generateFromCollections([
            hrmCollection, layerTogglesCollection,
        ])

        let aliasLines = config.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("beh_base_;") }
        XCTAssertEqual(aliasLines.count, 1, "Safety net should ensure exactly one beh_base_; definition")
    }

    // MARK: - extractConfigParseError (stderr detection)

    func testExtractsDuplicateAliasError() {
        let log = """
        [kanata-launcher] Launching Kanata for user=test
        04:28:32 [ERROR]  × Error in configuration
             ╭─[keypath.kbd:159:1]
         159 │   beh_base_; (tap-hold-opposite-hand 150 ; (layer-while-held fun))
             ·   ─────┬────
             ·        ╰── Error here
         160 │   beh_base_a (tap-hold-opposite-hand 150 a (layer-while-held fun))
             ╰────
          help: Duplicate alias: beh_base_;
        04:28:32 [ERROR] failed to parse file
        """

        let error = ServiceHealthChecker.extractConfigParseError(from: log)

        XCTAssertNotNil(error)
        XCTAssertEqual(error, "Duplicate alias: beh_base_;")
    }

    func testExtractsGenericConfigError() {
        let log = """
        [kanata-launcher] Host bridge config validation failed: Error in configuration
        [kanata-launcher] Host bridge runtime creation failed: failed to parse file
        04:28:32 [ERROR]  × Error in configuration
        04:28:32 [ERROR] failed to parse file
        """

        let error = ServiceHealthChecker.extractConfigParseError(from: log)

        XCTAssertNotNil(error)
        XCTAssertTrue(
            error?.contains("failed to parse file") == true || error?.contains("Error in configuration") == true,
            "Should extract a meaningful error, got: \(error ?? "nil")"
        )
    }

    func testNoConfigErrorWhenLogIsClean() {
        let log = """
        [kanata-launcher] Launching Kanata for user=test
        [kanata-launcher] Runtime started successfully
        """

        let error = ServiceHealthChecker.extractConfigParseError(from: log)

        XCTAssertNil(error)
    }

    // MARK: - Issue.configParseError

    func testConfigParseErrorIssueProperties() {
        let issue = Issue.configParseError(detail: "Duplicate alias: beh_base_;")

        XCTAssertEqual(issue.title, "Configuration error prevents remapping")
        XCTAssertFalse(issue.canAutoFix, "Destructive reset should not be auto-fixable")
        XCTAssertEqual(issue.action, "Reset to default config")
    }

    // MARK: - Helpers

    private func makeCollection(
        name: String,
        configuration: RuleCollectionConfiguration
    ) -> RuleCollection {
        RuleCollection(
            id: UUID(),
            name: name,
            summary: "",
            category: .custom,
            mappings: [],
            isEnabled: true,
            isSystemDefault: false,
            icon: nil,
            tags: [],
            targetLayer: .base,
            momentaryActivator: nil,
            activationHint: nil,
            configuration: configuration
        )
    }
}
