@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
final class RuleCollectionsManagerDependentResolutionTests: XCTestCase {
    func testKeepEnabledAppliesNothing() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(1),
            name: "Function",
            enabled: true
        )
        let consumer = homeRowToggles(
            id: uuid(2),
            name: "Home Row Layer Toggles",
            enabled: true,
            assignments: ["a": "fun", ";": "fun"]
        )
        manager.ruleCollections = [provider, consumer]

        var receivedContext: RuleDependentResolutionContext?
        manager.onDependentResolution = { context in
            receivedContext = context
            return nil
        }
        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let applied = await manager.toggleCollection(
            id: provider.id,
            isEnabled: false,
            bypassOwnershipCheck: true
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(regenerationCount, 0)
        XCTAssertTrue(manager.ruleCollections[id: provider.id]?.isEnabled == true)
        XCTAssertTrue(manager.ruleCollections[id: consumer.id]?.isEnabled == true)

        let context = try XCTUnwrap(receivedContext)
        XCTAssertEqual(context.providerID, provider.id)
        XCTAssertEqual(context.providerName, "Function")
        XCTAssertEqual(context.affectedConsumers.map(\.id), [consumer.id])
        XCTAssertEqual(context.dependents.map(\.dependentCollectionID), [
            consumer.id,
        ])

        let model = RuleDependentResolutionDialogModel(context: context)
        XCTAssertEqual(model.providerName, "Function")
        XCTAssertEqual(model.dependentCount, 1)
        XCTAssertFalse(model.collapseDetails)
        XCTAssertEqual(model.rows.map(\.usageSummary), [
            "Home Row Layer Toggles uses Function for the Fun layer.",
        ])
        XCTAssertEqual(model.rows.flatMap(\.evidence), [
            "2 affected keys: ; and A",
        ])
    }

    func testDisableAnywayAppliesOnlyProviderDisableOnce() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(10),
            name: "Function",
            enabled: true
        )
        let consumer = homeRowToggles(
            id: uuid(11),
            name: "Home Row Layer Toggles",
            enabled: true,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [provider, consumer]
        manager.onDependentResolution = { _ in .disableAnyway }

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let applied = await manager.toggleCollection(
            id: provider.id,
            isEnabled: false,
            bypassOwnershipCheck: true
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(regenerationCount, 1)
        XCTAssertTrue(manager.ruleCollections[id: provider.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: consumer.id]?.isEnabled == true)
    }

    func testAlternateActiveProviderSuppressesDialog() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let first = layerContentProvider(
            id: uuid(20),
            name: "Function",
            enabled: true,
            input: "x"
        )
        let second = layerContentProvider(
            id: uuid(21),
            name: "Custom Function",
            enabled: true,
            input: "z"
        )
        let consumer = homeRowToggles(
            id: uuid(22),
            name: "Home Row Layer Toggles",
            enabled: true,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [first, second, consumer]

        var didPrompt = false
        manager.onDependentResolution = { _ in
            didPrompt = true
            return nil
        }

        let applied = await manager.toggleCollection(
            id: first.id,
            isEnabled: false,
            bypassOwnershipCheck: true
        )

        XCTAssertTrue(applied)
        XCTAssertFalse(didPrompt)
        XCTAssertTrue(manager.ruleCollections[id: first.id]?.isEnabled == false)
        XCTAssertTrue(manager.ruleCollections[id: second.id]?.isEnabled == true)
    }

    func testManyDependentsProduceDeterministicCollapsedRows() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = layerContentProvider(
            id: uuid(30),
            name: "Function",
            enabled: true
        )
        let consumers = [
            homeRowToggles(
                id: uuid(31),
                name: "Alpha",
                enabled: true,
                assignments: ["a": "fun"]
            ),
            homeRowToggles(
                id: uuid(32),
                name: "Bravo",
                enabled: true,
                assignments: ["s": "fun"]
            ),
            homeRowToggles(
                id: uuid(33),
                name: "Charlie",
                enabled: true,
                assignments: ["d": "fun"]
            ),
            homeRowToggles(
                id: uuid(34),
                name: "Delta",
                enabled: true,
                assignments: ["f": "fun"]
            ),
        ]
        manager.ruleCollections = [provider] + consumers

        var receivedContext: RuleDependentResolutionContext?
        manager.onDependentResolution = { context in
            receivedContext = context
            return nil
        }

        _ = await manager.toggleCollection(
            id: provider.id,
            isEnabled: false,
            bypassOwnershipCheck: true
        )

        let model = try XCTUnwrap(receivedContext.map(
            RuleDependentResolutionDialogModel.init(context:)
        ))
        XCTAssertEqual(model.dependentCount, 4)
        XCTAssertTrue(model.collapseDetails)
        XCTAssertEqual(model.rows.map(\.usageSummary), [
            "Alpha uses Function for the Fun layer.",
            "Bravo uses Function for the Fun layer.",
            "Charlie uses Function for the Fun layer.",
            "Delta uses Function for the Fun layer.",
        ])
    }

    func testCustomRuleProviderUsesSameReverseConfirmation() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }
        let provider = CustomRule(
            id: uuid(40),
            title: "My Function Layer",
            input: "x",
            action: .keystroke(key: "y"),
            isEnabled: true,
            targetLayer: .custom("fun")
        )
        let consumer = homeRowToggles(
            id: uuid(41),
            name: "Home Row Layer Toggles",
            enabled: true,
            assignments: ["a": "fun"]
        )
        manager.customRules = [provider]
        manager.ruleCollections = [consumer]

        var receivedProviderName: String?
        manager.onDependentResolution = { context in
            receivedProviderName = context.providerName
            return nil
        }

        await manager.toggleCustomRule(id: provider.id, isEnabled: false)

        XCTAssertEqual(receivedProviderName, "My Function Layer")
        XCTAssertTrue(manager.customRules.first?.isEnabled == true)
    }

    func testFailedDisableRestoresProviderAndDependentState() async throws {
        let manager = try makeManager()
        defer { TestEnvironment.forceTestMode = false }

        var leader = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections().first {
                $0.id == RuleCollectionIdentifier.leaderKey
            }
        )
        leader.isEnabled = true

        let dependent = RuleCollection(
            id: uuid(50),
            name: "Navigation Consumer",
            summary: "Test",
            category: .custom,
            mappings: [
                KeyMapping(input: "x", action: .keystroke(key: "y")),
            ],
            isEnabled: true,
            targetLayer: .custom("fun"),
            momentaryActivator: MomentaryActivator(
                input: "f",
                targetLayer: .custom("fun"),
                sourceLayer: .navigation
            ),
            configuration: .list
        )
        let navigationMapping = RuleCollection(
            id: uuid(51),
            name: "Navigation Space Mapping",
            summary: "Test",
            category: .custom,
            mappings: [
                KeyMapping(input: "space", action: .keystroke(key: "q")),
            ],
            isEnabled: true,
            targetLayer: .navigation,
            configuration: .list
        )
        manager.ruleCollections = [leader, dependent, navigationMapping]
        manager.onDependentResolution = { _ in .disableAnyway }

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let applied = await manager.toggleCollection(
            id: leader.id,
            isEnabled: false,
            bypassOwnershipCheck: true
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(
            regenerationCount,
            2,
            "The failed disable and rollback should each regenerate once"
        )
        XCTAssertTrue(manager.ruleCollections[id: leader.id]?.isEnabled == true)
        XCTAssertEqual(
            manager.ruleCollections[id: dependent.id]?.momentaryActivator?.input,
            "f"
        )
        XCTAssertTrue(
            manager.ruleCollections[id: navigationMapping.id]?.isEnabled == true
        )
    }

    private func makeManager() throws -> RuleCollectionsManager {
        TestEnvironment.forceTestMode = true
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dependent-resolution-\(UUID().uuidString)")
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
        name: String,
        enabled: Bool,
        assignments: [String: String]
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: name,
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
        input: String = "x"
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: name,
            summary: "Test",
            category: .custom,
            mappings: [
                KeyMapping(input: input, action: .keystroke(key: "y")),
            ],
            isEnabled: enabled,
            targetLayer: .custom("fun"),
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
