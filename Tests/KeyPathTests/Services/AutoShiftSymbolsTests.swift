import Foundation
@testable import KeyPathAppKit
import Testing

// MARK: - Config Codable Tests

@Suite("AutoShiftSymbolsConfig Codable")
struct AutoShiftSymbolsConfigCodableTests {
    @Test("Round-trip encodes and decodes default config")
    func roundTripDefault() throws {
        let config = AutoShiftSymbolsConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AutoShiftSymbolsConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("Round-trip encodes custom timeout and key set")
    func roundTripCustom() throws {
        let config = AutoShiftSymbolsConfig(
            timeoutMs: 250,
            protectFastTyping: false,
            enabledKeys: Set(["grv", "min", "dot"])
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AutoShiftSymbolsConfig.self, from: data)
        #expect(decoded.timeoutMs == 250)
        #expect(decoded.protectFastTyping == false)
        #expect(decoded.enabledKeys == Set(["grv", "min", "dot"]))
    }

    @Test("Default config has all symbol keys enabled")
    func defaultKeysAreAllSymbols() {
        let config = AutoShiftSymbolsConfig()
        #expect(config.enabledKeys == Set(AutoShiftSymbolsConfig.allSymbolKeys))
    }

    @Test("Default timeout is 180ms")
    func defaultTimeout() {
        let config = AutoShiftSymbolsConfig()
        #expect(config.timeoutMs == 180)
    }

    @Test("Default protectFastTyping is true")
    func defaultProtectFastTyping() {
        let config = AutoShiftSymbolsConfig()
        #expect(config.protectFastTyping == true)
    }
}

// MARK: - RuleCollectionConfiguration Codable Tests

@Suite("AutoShiftSymbols RuleCollectionConfiguration Codable")
struct AutoShiftConfigurationCodableTests {
    @Test("Round-trip encodes autoShiftSymbols configuration case")
    func roundTripConfiguration() throws {
        let config = AutoShiftSymbolsConfig(timeoutMs: 200, protectFastTyping: false)
        let configuration = RuleCollectionConfiguration.autoShiftSymbols(config)
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)
        #expect(decoded == configuration)
        #expect(decoded.autoShiftSymbolsConfig?.timeoutMs == 200)
        #expect(decoded.autoShiftSymbolsConfig?.protectFastTyping == false)
    }

    @Test("Display style is autoShiftSymbols")
    func displayStyle() {
        let configuration = RuleCollectionConfiguration.autoShiftSymbols(AutoShiftSymbolsConfig())
        #expect(configuration.displayStyle == .autoShiftSymbols)
    }
}

// MARK: - Mapping Generation Tests

@Suite("AutoShiftSymbols Mapping Generation")
struct AutoShiftMappingGenerationTests {
    @Test("Generates one mapping per enabled key")
    func generatesCorrectCount() {
        let config = AutoShiftSymbolsConfig()
        let mappings = KanataConfiguration.generateAutoShiftSymbolsMappings(from: config)
        #expect(mappings.count == AutoShiftSymbolsConfig.allSymbolKeys.count)
    }

    @Test("Generates only for enabled keys")
    func generatesOnlyEnabledKeys() {
        let config = AutoShiftSymbolsConfig(enabledKeys: Set(["dot", "comm"]))
        let mappings = KanataConfiguration.generateAutoShiftSymbolsMappings(from: config)
        #expect(mappings.count == 2)
        let inputs = Set(mappings.map(\.input))
        #expect(inputs == Set(["dot", "comm"]))
    }

    @Test("Generated mappings have correct dual-role behavior")
    func correctDualRoleBehavior() {
        let config = AutoShiftSymbolsConfig(timeoutMs: 200)
        let mappings = KanataConfiguration.generateAutoShiftSymbolsMappings(from: config)

        let dotMapping = mappings.first { $0.input == "dot" }
        #expect(dotMapping != nil)

        guard case let .dualRole(behavior) = dotMapping?.behavior else {
            Issue.record("Expected dualRole behavior")
            return
        }

        #expect(behavior.tapAction == "dot")
        #expect(behavior.holdAction == "S-dot")
        #expect(behavior.tapTimeout == 200)
        #expect(behavior.holdTimeout == 200)
        #expect(behavior.activateHoldOnOtherKey == false)
        #expect(behavior.quickTap == false)
        #expect(behavior.useOppositeHand == false)
    }

    @Test("Empty enabled keys produces no mappings")
    func emptyEnabledKeys() {
        let config = AutoShiftSymbolsConfig(enabledKeys: Set())
        let mappings = KanataConfiguration.generateAutoShiftSymbolsMappings(from: config)
        #expect(mappings.isEmpty)
    }
}

// MARK: - Kanata Rendering Tests

@Suite("AutoShiftSymbols Kanata Rendering")
struct AutoShiftKanataRenderingTests {
    @Test("Generates valid Kanata config with tap-hold")
    func generatesKanataConfig() {
        let config = AutoShiftSymbolsConfig(
            timeoutMs: 180,
            enabledKeys: Set(["dot", "scln"])
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.autoShiftSymbols,
            name: "Auto Shift Symbols",
            summary: "Test",
            category: .experimental,
            mappings: [],
            isEnabled: true,
            configuration: .autoShiftSymbols(config)
        )

        let output = KanataConfiguration.generateFromCollections([collection])
        #expect(output.contains("tap-hold"))
        #expect(output.contains("dot"))
        #expect(output.contains("scln"))
    }

    @Test("Require-prior-idle emitted when protectFastTyping is true")
    func emitsRequirePriorIdle() {
        let config = AutoShiftSymbolsConfig(timeoutMs: 180, protectFastTyping: true, enabledKeys: Set(["dot"]))
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.autoShiftSymbols,
            name: "Auto Shift Symbols",
            summary: "Test",
            category: .experimental,
            mappings: [],
            isEnabled: true,
            configuration: .autoShiftSymbols(config)
        )

        let output = KanataConfiguration.generateFromCollections([collection])
        #expect(output.contains("require-prior-idle 180"))
    }

    @Test("No require-prior-idle when protectFastTyping is false")
    func noRequirePriorIdleWhenDisabled() {
        let config = AutoShiftSymbolsConfig(timeoutMs: 180, protectFastTyping: false, enabledKeys: Set(["dot"]))
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.autoShiftSymbols,
            name: "Auto Shift Symbols",
            summary: "Test",
            category: .experimental,
            mappings: [],
            isEnabled: true,
            configuration: .autoShiftSymbols(config)
        )

        let output = KanataConfiguration.generateFromCollections([collection])
        #expect(!output.contains("require-prior-idle"))
    }
}

// MARK: - Catalog Tests

@Suite("AutoShiftSymbols Catalog")
struct AutoShiftCatalogTests {
    @Test("Catalog includes auto shift symbols collection")
    func catalogHasAutoShift() {
        let catalog = RuleCollectionCatalog()
        let collections = catalog.defaultCollections()
        let autoShift = collections.first { $0.id == RuleCollectionIdentifier.autoShiftSymbols }
        #expect(autoShift != nil)
        #expect(autoShift?.name == "Auto Shift Symbols")
        #expect(autoShift?.category == .experimental)
        #expect(autoShift?.isEnabled == false)
    }

    @Test("Catalog preserves user config on upgrade")
    func upgradePreservesConfig() throws {
        let catalog = RuleCollectionCatalog()
        let customConfig = AutoShiftSymbolsConfig(timeoutMs: 250, protectFastTyping: false, enabledKeys: Set(["dot"]))
        var existing = try #require(catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.autoShiftSymbols })
        existing.configuration = .autoShiftSymbols(customConfig)
        existing.isEnabled = true

        let upgraded = catalog.upgradedCollection(from: existing)
        #expect(upgraded.isEnabled == true)
        #expect(upgraded.configuration.autoShiftSymbolsConfig?.timeoutMs == 250)
        #expect(upgraded.configuration.autoShiftSymbolsConfig?.protectFastTyping == false)
        #expect(upgraded.configuration.autoShiftSymbolsConfig?.enabledKeys == Set(["dot"]))
    }
}
