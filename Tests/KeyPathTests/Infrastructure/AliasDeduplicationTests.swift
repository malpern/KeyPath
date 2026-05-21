@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import XCTest

final class AliasDeduplicationTests: XCTestCase {
    // MARK: - deduplicateAliases

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

    func testDuplicateAliasLastWins() {
        let aliases = [
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_;", definition: "(tap-hold 200 200 ; rsft)", comment: "home row mod"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_a", definition: "(tap-hold 200 200 a lsft)"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_;", definition: "(tap-hold 150 ; (layer-while-held fun))", comment: "layer toggle"),
        ]

        let result = KanataConfiguration.deduplicateAliases(aliases)

        XCTAssertEqual(result.count, 2, "Should have 2 unique aliases, not 3")
        XCTAssertEqual(result[0].aliasName, "beh_base_;")
        XCTAssertTrue(result[0].definition.contains("layer-while-held fun"), "Last definition should win")
        XCTAssertEqual(result[0].comment, "layer toggle")
        XCTAssertEqual(result[1].aliasName, "beh_base_a")
    }

    func testMultipleDuplicatesAllDeduped() {
        let aliases = [
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_;", definition: "def1"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_a", definition: "def2"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_s", definition: "def3"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_;", definition: "def4"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_a", definition: "def5"),
            KanataConfiguration.AliasDefinition(aliasName: "beh_base_s", definition: "def6"),
        ]

        let result = KanataConfiguration.deduplicateAliases(aliases)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].definition, "def4")
        XCTAssertEqual(result[1].definition, "def5")
        XCTAssertEqual(result[2].definition, "def6")
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

    // MARK: - Integration: HRM + Layer Toggles don't produce duplicate aliases

    func testHRMAndLayerTogglesProduceNoDuplicateAliases() throws {
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

        let config = KanataConfiguration.generateFromCollections([
            hrmCollection, layerTogglesCollection,
        ])

        // Config should be parseable (no duplicate aliases)
        let aliasMatches = config.components(separatedBy: "\n").filter { $0.contains("beh_base_;") }
        let definitionLines = aliasMatches.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("beh_base_;") }
        XCTAssertEqual(definitionLines.count, 1, "Should have exactly one beh_base_; definition, not \(definitionLines.count): \(definitionLines)")
    }

    // MARK: - extractConfigParseError

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
        XCTAssertTrue(issue.canAutoFix)
        XCTAssertTrue(issue.action.contains("Duplicate alias: beh_base_;"))
        XCTAssertTrue(issue.action.contains("Reset to default config"))
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
