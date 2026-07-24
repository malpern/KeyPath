@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

@MainActor
final class RuleCollectionsManagerPrerequisiteDetectionTests: XCTestCase {
    func testDefaultCatalogHasNoNewPrerequisites() {
        let manager = makeManager()
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()

        let candidate = manager.ruleCollections[0]

        XCTAssertTrue(manager.prerequisites(for: candidate).isEmpty)
    }

    func testForwardAnalysisFindsMissingLayerContentWithEvidence() {
        let manager = makeManager()
        let consumer = homeRowToggles(
            id: uuid(1),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [consumer]

        let prerequisites = manager.prerequisites(for: consumer)

        XCTAssertEqual(prerequisites, [
            RulePrerequisite(
                consumerCollectionID: consumer.id,
                missingCapability: .layerContent(layer("fun")),
                requirement: RuleRequirement(
                    capability: .layerContent(layer("fun")),
                    evidence: [.keys(["a"])]
                ),
                availableProviderCollectionIDs: [],
                recommendedProviderCollectionID: nil
            ),
        ])
    }

    func testForwardAnalysisAppendsBrandNewCandidate() {
        let manager = makeManager()
        let candidate = homeRowToggles(
            id: uuid(3),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = []

        let prerequisites = manager.prerequisites(for: candidate)

        XCTAssertEqual(prerequisites.map(\.consumerCollectionID), [candidate.id])
        XCTAssertEqual(prerequisites.map(\.missingCapability), [
            .layerContent(layer("fun")),
        ])
    }

    func testForwardAnalysisFindsMissingActivationPath() {
        let manager = makeManager()
        let consumer = collection(
            id: uuid(2),
            name: "Symbols",
            enabled: false,
            activator: MomentaryActivator(
                input: "f",
                targetLayer: .custom("sym"),
                sourceLayer: .navigation
            )
        )
        manager.ruleCollections = [consumer]

        let prerequisites = manager.prerequisites(for: consumer)

        XCTAssertEqual(prerequisites.map(\.missingCapability), [
            .layerActivation(layer("nav")),
        ])
        XCTAssertEqual(prerequisites.first?.requirement.evidence, [
            .layerPath(source: layer("nav"), target: layer("sym")),
        ])
    }

    func testForwardAnalysisFindsMissingHyperAlias() {
        let manager = makeManager()
        let launcher = collection(
            id: RuleCollectionIdentifier.launcher,
            name: "Launcher",
            enabled: false,
            targetLayer: .custom("launcher"),
            configuration: .launcherGrid(LauncherGridConfig(
                activationMode: .holdHyper,
                mappings: []
            ))
        )
        manager.ruleCollections = [launcher]

        let prerequisites = manager.prerequisites(for: launcher)

        XCTAssertEqual(prerequisites.map(\.missingCapability), [.keyAlias(.hyper)])
    }

    func testForwardAnalysisReturnsSingleDisabledProviderAsRecommendation() throws {
        let manager = makeManager()
        let provider = layerContentProvider(
            id: uuid(10),
            name: "Function",
            layerName: "fun",
            enabled: false
        )
        let consumer = homeRowToggles(
            id: uuid(11),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [provider, consumer]

        let prerequisite = try XCTUnwrap(
            manager.prerequisites(for: consumer).first
        )

        XCTAssertEqual(prerequisite.availableProviderCollectionIDs, [provider.id])
        XCTAssertEqual(prerequisite.recommendedProviderCollectionID, provider.id)
    }

    func testForwardAnalysisReturnsMultipleProvidersWithoutRecommendation() throws {
        let manager = makeManager()
        let first = layerContentProvider(
            id: uuid(20),
            name: "First Function",
            layerName: "fun",
            enabled: false
        )
        let second = layerContentProvider(
            id: uuid(21),
            name: "Second Function",
            layerName: "fun",
            enabled: false
        )
        let consumer = homeRowToggles(
            id: uuid(22),
            enabled: false,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [first, second, consumer]

        let prerequisite = try XCTUnwrap(
            manager.prerequisites(for: consumer).first
        )

        XCTAssertEqual(
            prerequisite.availableProviderCollectionIDs,
            [first.id, second.id]
        )
        XCTAssertNil(prerequisite.recommendedProviderCollectionID)
    }

    func testForwardAnalysisUsesProposedConfigurationInsteadOfStoredState() {
        let manager = makeManager()
        let stored = collection(
            id: uuid(30),
            name: "Home Row Mods",
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a"],
                layerAssignments: ["a": "fun"],
                holdMode: .modifiers
            ))
        )
        var proposed = stored
        proposed.configuration = .homeRowMods(HomeRowModsConfig(
            enabledKeys: ["a"],
            layerAssignments: ["a": "fun"],
            holdMode: .layers
        ))
        manager.ruleCollections = [stored]

        let prerequisites = manager.prerequisites(for: proposed)

        XCTAssertEqual(prerequisites.map(\.missingCapability), [
            .layerContent(layer("fun")),
        ])
    }

    func testForwardProviderEditReportsNewlyOrphanedExistingConsumer() {
        let manager = makeManager()
        let provider = collection(
            id: uuid(31),
            name: "Navigation Activator",
            activator: MomentaryActivator(
                input: "space",
                targetLayer: .navigation
            )
        )
        let consumer = collection(
            id: uuid(32),
            name: "Navigation Mappings",
            mappings: [
                KeyMapping(input: "h", action: .keystroke(key: "left")),
            ],
            targetLayer: .navigation
        )
        var proposedProvider = provider
        proposedProvider.momentaryActivator = nil
        manager.ruleCollections = [provider, consumer]

        let prerequisites = manager.prerequisites(for: proposedProvider)

        XCTAssertEqual(prerequisites.map(\.consumerCollectionID), [consumer.id])
        XCTAssertEqual(prerequisites.map(\.missingCapability), [
            .layerActivation(layer("nav")),
        ])
    }

    func testForwardAnalysisDoesNotRepeatPreexistingMissingRequirement() {
        let manager = makeManager()
        let broken = homeRowToggles(
            id: uuid(40),
            enabled: true,
            assignments: ["a": "fun"]
        )
        let unrelated = collection(
            id: uuid(41),
            name: "Unrelated",
            enabled: true
        )
        manager.ruleCollections = [broken, unrelated]

        XCTAssertTrue(manager.prerequisites(for: unrelated).isEmpty)
    }

    func testForwardAnalysisDoesNotRepeatMissingCapabilityWhenEvidenceChanges() {
        let manager = makeManager()
        let stored = homeRowToggles(
            id: uuid(42),
            enabled: true,
            assignments: ["a": "fun"]
        )
        let proposed = homeRowToggles(
            id: stored.id,
            enabled: true,
            assignments: [";": "fun", "a": "fun"]
        )
        manager.ruleCollections = [stored]

        XCTAssertTrue(manager.prerequisites(for: proposed).isEmpty)
    }

    func testReverseAnalysisDoesNotWarnWhenAnotherProviderRemainsActive() {
        let manager = makeManager()
        let victim = layerContentProvider(
            id: uuid(50),
            name: "First Function",
            layerName: "fun",
            enabled: true
        )
        let alternate = layerContentProvider(
            id: uuid(51),
            name: "Second Function",
            layerName: "fun",
            enabled: true
        )
        let consumer = homeRowToggles(
            id: uuid(52),
            enabled: true,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [victim, alternate, consumer]

        XCTAssertTrue(manager.dependents(ifDisabling: victim.id).isEmpty)
    }

    func testReverseAnalysisDoesNotRepeatPreexistingOrphan() {
        let manager = makeManager()
        let unrelatedVictim = layerContentProvider(
            id: uuid(53),
            name: "Symbols",
            layerName: "sym",
            enabled: true
        )
        let brokenConsumer = homeRowToggles(
            id: uuid(54),
            enabled: true,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [unrelatedVictim, brokenConsumer]

        XCTAssertTrue(
            manager.dependents(ifDisabling: unrelatedVictim.id).isEmpty
        )
    }

    func testReverseAnalysisFindsOneOrphanAndRemainingDisabledProviders() {
        let manager = makeManager()
        let victim = layerContentProvider(
            id: uuid(60),
            name: "Active Function",
            layerName: "fun",
            enabled: true
        )
        let disabledAlternate = layerContentProvider(
            id: uuid(61),
            name: "Disabled Function",
            layerName: "fun",
            enabled: false
        )
        let consumer = homeRowToggles(
            id: uuid(62),
            enabled: true,
            assignments: ["a": "fun"]
        )
        manager.ruleCollections = [victim, disabledAlternate, consumer]

        let dependents = manager.dependents(ifDisabling: victim.id)

        XCTAssertEqual(dependents, [
            RuleDependentMapping(
                dependentCollectionID: consumer.id,
                newlyUnsatisfiedCapability: .layerContent(layer("fun")),
                requirement: RuleRequirement(
                    capability: .layerContent(layer("fun")),
                    evidence: [.keys(["a"])]
                ),
                remainingAvailableProviderCollectionIDs: [disabledAlternate.id]
            ),
        ])
    }

    func testReverseAnalysisFindsMultipleOrphansInDisplayAndRequirementOrder() {
        let manager = makeManager()
        let function = layerContentProvider(
            id: uuid(70),
            name: "Function",
            layerName: "fun",
            enabled: true
        )
        let firstConsumer = homeRowToggles(
            id: uuid(71),
            name: "First Consumer",
            enabled: true,
            assignments: ["d": "sym", "a": "fun"]
        )
        let secondConsumer = homeRowToggles(
            id: uuid(72),
            name: "Second Consumer",
            enabled: true,
            assignments: ["j": "fun"]
        )
        manager.ruleCollections = [function, firstConsumer, secondConsumer]

        let dependents = manager.dependents(ifDisabling: function.id)

        XCTAssertEqual(dependents.map(\.dependentCollectionID), [
            firstConsumer.id,
            secondConsumer.id,
        ])
        XCTAssertEqual(dependents.map(\.newlyUnsatisfiedCapability), [
            .layerContent(layer("fun")),
            .layerContent(layer("fun")),
        ])
    }

    func testForwardResultsUseDisplayThenCapabilityAndEvidenceOrder() {
        let manager = makeManager()
        let second = homeRowToggles(
            id: uuid(82),
            name: "Second",
            enabled: true,
            assignments: ["a": "fun"]
        )
        let first = homeRowToggles(
            id: uuid(81),
            name: "First",
            enabled: false,
            assignments: ["d": "sym", "a": "fun"]
        )
        manager.ruleCollections = [second, first]

        let prerequisites = manager.prerequisites(for: first)

        XCTAssertEqual(prerequisites.map(\.consumerCollectionID), [
            first.id,
            first.id,
        ])
        XCTAssertEqual(prerequisites.map(\.missingCapability), [
            .layerContent(layer("fun")),
            .layerContent(layer("sym")),
        ])
    }

    private func makeManager() -> RuleCollectionsManager {
        RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: ConfigurationService()
        )
    }

    private func collection(
        id: UUID,
        name: String,
        enabled: Bool = true,
        mappings: [KeyMapping] = [],
        targetLayer: RuleCollectionLayer = .base,
        activator: MomentaryActivator? = nil,
        configuration: RuleCollectionConfiguration = .list
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: name,
            summary: "Test",
            category: .custom,
            mappings: mappings,
            isEnabled: enabled,
            targetLayer: targetLayer,
            momentaryActivator: activator,
            configuration: configuration
        )
    }

    private func homeRowToggles(
        id: UUID,
        name: String = "Home Row Toggles",
        enabled: Bool,
        assignments: [String: String]
    ) -> RuleCollection {
        collection(
            id: id,
            name: name,
            enabled: enabled,
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: Set(assignments.keys),
                layerAssignments: assignments
            ))
        )
    }

    private func layerContentProvider(
        id: UUID,
        name: String,
        layerName: String,
        enabled: Bool
    ) -> RuleCollection {
        collection(
            id: id,
            name: name,
            enabled: enabled,
            mappings: [
                KeyMapping(input: "x", action: .keystroke(key: "y")),
            ],
            targetLayer: .custom(layerName)
        )
    }

    private func layer(_ name: String) -> RuleLayerIdentifier {
        RuleLayerIdentifier(name)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        ))!
    }
}
