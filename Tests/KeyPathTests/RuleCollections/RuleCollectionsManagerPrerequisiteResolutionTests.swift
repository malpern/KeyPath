@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
final class RuleCollectionsManagerPrerequisiteResolutionTests: XCTestCase {
    func testEnableRequiredProvidersAppliesOneAtomicRegeneration() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(1),
            name: "Function",
            enabled: false
        )
        let candidate = homeRowToggles(
            id: uuid(2),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [provider, candidate]

        var receivedContext: RulePrerequisiteResolutionContext?
        manager.onPrerequisiteResolution = { context in
            receivedContext = context
            return .enableRequiredProvidersAndApply
        }
        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let applied = await manager.toggleCollection(
            id: candidate.id,
            isEnabled: true,
            bypassOwnershipCheck: true
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(receivedContext?.operation, .enable)
        XCTAssertEqual(receivedContext?.candidate.id, candidate.id)
        XCTAssertEqual(receivedContext?.recommendedProviderIDs, [provider.id])
        XCTAssertEqual(receivedContext?.availableProviders.map(\.id), [provider.id])
        XCTAssertEqual(receivedContext?.affectedConsumers.map(\.id), [candidate.id])

        let dialogModel = try XCTUnwrap(receivedContext.map(
            RulePrerequisiteDialogModel.init(context:)
        ))
        XCTAssertTrue(dialogModel.canEnableAll)
        XCTAssertEqual(dialogModel.candidateName, "Home Row Layer Toggles")
        XCTAssertEqual(dialogModel.recommendedProviderNames, ["Function"])
        XCTAssertEqual(
            dialogModel.primaryActionTitle,
            "Enable Required Rules & Turn On"
        )
        XCTAssertEqual(dialogModel.secondaryActionTitle, "Turn On Without Them")
        XCTAssertEqual(dialogModel.rows.map(\.consumerName), [
            "Home Row Layer Toggles",
        ])
        XCTAssertEqual(dialogModel.rows.map(\.capabilityName), [
            "Fun layer content",
        ])
        XCTAssertEqual(dialogModel.rows.map(\.providerSummary), [
            "Provided by Function.",
        ])
        XCTAssertEqual(dialogModel.rows.flatMap(\.evidence), [
            "1 affected key: A",
        ])
        XCTAssertEqual(regenerationCount, 1)
        XCTAssertTrue(manager.ruleCollections[id: candidate.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: provider.id]?.isEnabled == true)
    }

    func testCancelAppliesNothing() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(10),
            name: "Function",
            enabled: false
        )
        let candidate = homeRowToggles(
            id: uuid(11),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [provider, candidate]
        manager.onPrerequisiteResolution = { _ in nil }

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let applied = await manager.toggleCollection(
            id: candidate.id,
            isEnabled: true,
            bypassOwnershipCheck: true
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(regenerationCount, 0)
        XCTAssertTrue(manager.ruleCollections[id: candidate.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: provider.id]?.isEnabled == false)
    }

    func testCancelCatalogOnlyCandidateDoesNotInsertAttemptedConfig() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()
            .filter { $0.id != RuleCollectionIdentifier.homeRowMods }
        manager.onPrerequisiteResolution = { _ in nil }

        var attempted = HomeRowModsConfig()
        attempted.holdMode = .layers

        _ = await manager.updateHomeRowModsConfig(
            id: RuleCollectionIdentifier.homeRowMods,
            config: attempted
        )

        XCTAssertNil(
            manager.ruleCollections.first {
                $0.id == RuleCollectionIdentifier.homeRowMods
            },
            "Cancelling a catalog-only edit must not insert its attempted config"
        )
    }

    func testSaveWithoutProvidersAppliesOnlyCandidateEdit() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(20),
            name: "Function",
            enabled: false
        )
        let candidate = homeRowToggles(
            id: uuid(21),
            enabled: false,
            assignments: [:]
        )
        manager.ruleCollections = [provider, candidate]

        var receivedContext: RulePrerequisiteResolutionContext?
        manager.onPrerequisiteResolution = { context in
            receivedContext = context
            return .applyWithoutProviders
        }
        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let newlyEnabled = await manager.updateHomeRowLayerTogglesConfig(
            id: candidate.id,
            config: HomeRowLayerTogglesConfig(
                enabledKeys: ["a"],
                layerAssignments: ["a": "fun"]
            )
        )

        XCTAssertTrue(newlyEnabled)
        XCTAssertEqual(receivedContext?.operation, .save)
        XCTAssertEqual(regenerationCount, 1)
        XCTAssertTrue(manager.ruleCollections[id: candidate.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: provider.id]?.isEnabled == false)
        XCTAssertEqual(
            manager.ruleCollections[id: candidate.id]?
                .configuration.homeRowLayerTogglesConfig?.layerAssignments,
            ["a": "fun"]
        )
    }

    func testConfigurationEditAnalyzesProposedStateBeforeMutation() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(30),
            name: "Function",
            enabled: false
        )
        let candidate = homeRowToggles(
            id: uuid(31),
            enabled: true,
            assignments: [:]
        )
        manager.ruleCollections = [provider, candidate]

        var receivedContext: RulePrerequisiteResolutionContext?
        manager.onPrerequisiteResolution = { context in
            receivedContext = context
            return nil
        }

        _ = await manager.updateHomeRowLayerTogglesConfig(
            id: candidate.id,
            config: HomeRowLayerTogglesConfig(
                enabledKeys: ["a", ";"],
                layerAssignments: ["a": "fun", ";": "fun"]
            )
        )

        XCTAssertEqual(
            receivedContext?.prerequisites.first?.requirement.evidence,
            [.keys([";", "a"])]
        )
        XCTAssertEqual(
            manager.ruleCollections[id: candidate.id]?
                .configuration.homeRowLayerTogglesConfig?.layerAssignments,
            [:],
            "Cancelling must leave the stored configuration untouched"
        )
    }

    func testHomeRowModsLayerEditDerivesAllProvidersFromGraph() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let function = layerContentProvider(
            id: uuid(35),
            name: "Function",
            enabled: false,
            layerName: "fun"
        )
        let numpad = layerContentProvider(
            id: uuid(36),
            name: "Numpad",
            enabled: false,
            layerName: "num"
        )
        let symbols = layerContentProvider(
            id: uuid(37),
            name: "Symbol",
            enabled: false,
            layerName: "sym"
        )
        let navigation = layerContentProvider(
            id: uuid(39),
            name: "Navigation",
            enabled: false,
            layerName: "nav"
        )
        let candidate = RuleCollection(
            id: uuid(38),
            name: "Home Row Mods",
            summary: "Test",
            category: .custom,
            mappings: [],
            isEnabled: false,
            configuration: .homeRowMods(HomeRowModsConfig())
        )
        manager.ruleCollections = [
            function,
            numpad,
            symbols,
            navigation,
            candidate,
        ]

        var receivedContext: RulePrerequisiteResolutionContext?
        manager.onPrerequisiteResolution = { context in
            receivedContext = context
            return .enableRequiredProvidersAndApply
        }
        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        var layerConfig = HomeRowModsConfig()
        layerConfig.holdMode = .layers
        let newlyEnabled = await manager.updateHomeRowModsConfig(
            id: candidate.id,
            config: layerConfig
        )

        XCTAssertTrue(newlyEnabled)
        XCTAssertEqual(regenerationCount, 1)
        XCTAssertEqual(
            Set(receivedContext?.recommendedProviderIDs ?? []),
            Set([function.id, numpad.id, symbols.id, navigation.id])
        )
        XCTAssertTrue(manager.ruleCollections[id: function.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: numpad.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: symbols.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: navigation.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: candidate.id]?.isEnabled == true)
    }

    func testMultipleProvidersDisableAutomaticFix() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let first = layerContentProvider(
            id: uuid(40),
            name: "First Function",
            enabled: false
        )
        let second = layerContentProvider(
            id: uuid(41),
            name: "Second Function",
            enabled: false
        )
        let candidate = homeRowToggles(
            id: uuid(42),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [first, second, candidate]

        var recommendedProviderIDs: [UUID]?
        var didReceiveContext = false
        var receivedContext: RulePrerequisiteResolutionContext?
        manager.onPrerequisiteResolution = { context in
            didReceiveContext = true
            receivedContext = context
            recommendedProviderIDs = context.recommendedProviderIDs
            return .applyWithoutProviders
        }

        _ = await manager.toggleCollection(
            id: candidate.id,
            isEnabled: true,
            bypassOwnershipCheck: true
        )

        XCTAssertTrue(didReceiveContext)
        XCTAssertNil(recommendedProviderIDs)
        let context = try XCTUnwrap(receivedContext)
        let dialogModel = RulePrerequisiteDialogModel(context: context)
        XCTAssertFalse(dialogModel.canEnableAll)
        XCTAssertEqual(dialogModel.rows.map(\.providerSummary), [
            "Available from First Function and Second Function.",
        ])
        XCTAssertTrue(manager.ruleCollections[id: first.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: second.id]?.isEnabled == false)
    }

    func testNonInteractiveAutomaticFixAbortsWhenProvidersAreAmbiguous() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let first = layerContentProvider(
            id: uuid(43),
            name: "First Function",
            enabled: false
        )
        let second = layerContentProvider(
            id: uuid(44),
            name: "Second Function",
            enabled: false
        )
        let candidate = homeRowToggles(
            id: uuid(45),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [first, second, candidate]

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let appliedProviderIDs = await manager.applyProposedCollectionWithPrerequisites(
            candidate,
            rollbackMessage: "Test rollback",
            nonInteractiveChoice: .enableRequiredProvidersAndApply
        )

        XCTAssertNil(appliedProviderIDs)
        XCTAssertEqual(regenerationCount, 0)
        XCTAssertTrue(manager.ruleCollections[id: candidate.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: first.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: second.id]?.isEnabled == false)
    }

    func testFailedAtomicSaveRestoresCandidateAndProvider() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(50),
            name: "Function",
            enabled: false,
            input: "x",
            output: "y",
            activatorKey: "f"
        )
        let conflicting = RuleCollection(
            id: uuid(51),
            name: "Existing Function",
            summary: "Test",
            category: .custom,
            mappings: [
                KeyMapping(input: "z", action: .keystroke(key: "q")),
            ],
            isEnabled: true,
            targetLayer: .custom("sym"),
            momentaryActivator: MomentaryActivator(
                input: "f",
                targetLayer: .custom("sym")
            ),
            configuration: .list
        )
        let candidate = homeRowToggles(
            id: uuid(52),
            enabled: false,
            assignments: [:]
        )
        manager.ruleCollections = [provider, conflicting, candidate]
        manager.onPrerequisiteResolution = { _ in
            .enableRequiredProvidersAndApply
        }

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let newlyEnabled = await manager.updateHomeRowLayerTogglesConfig(
            id: candidate.id,
            config: HomeRowLayerTogglesConfig(
                enabledKeys: ["a"],
                layerAssignments: ["a": "fun"]
            )
        )

        XCTAssertFalse(newlyEnabled)
        XCTAssertEqual(
            regenerationCount,
            2,
            "The failed apply and rollback should each regenerate exactly once"
        )
        XCTAssertTrue(manager.ruleCollections[id: candidate.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: provider.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: conflicting.id]?.isEnabled == true)
        XCTAssertEqual(
            manager.ruleCollections[id: candidate.id]?
                .configuration.homeRowLayerTogglesConfig?.layerAssignments,
            [:]
        )
    }

    private func makeManager() throws -> RuleCollectionsManager {
        TestEnvironment.forceTestMode = true
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prerequisite-resolution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return RuleCollectionsManager(
            ruleCollectionStore: RuleCollectionStore(
                fileURL: directory.appendingPathComponent("RuleCollections.json")
            ),
            customRulesStore: CustomRulesStore(
                fileURL: directory.appendingPathComponent("CustomRules.json")
            ),
            configurationService: ConfigurationService(
                configDirectory: directory.path
            )
        )
    }

    private func homeRowToggles(
        id: UUID,
        enabled: Bool,
        assignments: [String: String]
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: "Home Row Layer Toggles",
            summary: "Test",
            category: .custom,
            mappings: [],
            isEnabled: enabled,
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: Set(assignments.keys),
                layerAssignments: assignments
            ))
        )
    }

    private func layerContentProvider(
        id: UUID,
        name: String,
        enabled: Bool,
        input: String = "x",
        output: String = "y",
        activatorKey: String? = nil,
        layerName: String = "fun"
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: name,
            summary: "Test",
            category: .custom,
            mappings: [
                KeyMapping(input: input, action: .keystroke(key: output)),
            ],
            isEnabled: enabled,
            targetLayer: .custom(layerName),
            momentaryActivator: activatorKey.map {
                MomentaryActivator(
                    input: $0,
                    targetLayer: .custom(layerName)
                )
            },
            configuration: .list
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        ))!
    }
}

private extension [RuleCollection] {
    subscript(id id: UUID) -> RuleCollection? {
        first { $0.id == id }
    }
}
