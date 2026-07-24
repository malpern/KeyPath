@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class RuleCollectionDependencyExtractorTests: XCTestCase {
    private let extractor = RuleCollectionDependencyExtractor()
    private let adapter = RuleCollectionDependencyGraphAdapter()

    func testUsefulMappingsProvideNormalizedLayerContentForDisabledCollection() {
        let collection = makeCollection(
            isEnabled: false,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"))],
            targetLayer: .custom(" FUN ")
        )

        let contribution = extractor.contribution(for: collection)

        XCTAssertEqual(contribution.provides, [.layerContent(layer("fun"))])
        let graph = adapter.build(collections: [collection])
        XCTAssertEqual(
            graph.knownProviders(for: .layerContent(layer("fun"))),
            [collection.id]
        )
        XCTAssertTrue(
            graph.activeProviders(for: .layerContent(layer("fun"))).isEmpty
        )
    }

    func testBaseAndChainedActivatorsProvideTargetActivation() {
        let baseProvider = makeCollection(
            momentaryActivator: MomentaryActivator(
                input: "space",
                targetLayer: .custom(" FUN ")
            )
        )
        let chainedProvider = makeCollection(
            momentaryActivator: MomentaryActivator(
                input: "f",
                targetLayer: .custom("SYM"),
                sourceLayer: .custom(" NAV ")
            )
        )

        let baseContribution = extractor.contribution(for: baseProvider)
        XCTAssertTrue(baseContribution.provides.contains(.layerActivation(layer("fun"))))
        XCTAssertTrue(baseContribution.requirements.isEmpty)

        let chainedContribution = extractor.contribution(for: chainedProvider)
        XCTAssertTrue(chainedContribution.provides.contains(.layerActivation(layer("sym"))))
        XCTAssertEqual(
            chainedContribution.requirements,
            [RuleRequirement(
                capability: .layerActivation(layer("nav")),
                evidence: [.layerPath(source: layer("nav"), target: layer("sym"))]
            )]
        )
    }

    func testNonBaseMappingsWithoutActivatorRequireTargetActivationWithMappingEvidence() {
        let mappingID = uuid(20)
        let collection = makeCollection(
            mappings: [
                KeyMapping(
                    id: mappingID,
                    input: "a",
                    action: .keystroke(key: "b")
                ),
            ],
            targetLayer: .custom(" Fun ")
        )

        let contribution = extractor.contribution(for: collection)

        XCTAssertEqual(
            contribution.requirements,
            [RuleRequirement(
                capability: .layerActivation(layer("fun")),
                evidence: [.mappingIDs([mappingID])]
            )]
        )
    }

    func testMismatchedActivatorTargetDoesNotSatisfyCollectionLayerActivation() {
        let mappingID = uuid(23)
        let collection = makeCollection(
            mappings: [
                KeyMapping(
                    id: mappingID,
                    input: "a",
                    action: .keystroke(key: "b")
                ),
            ],
            targetLayer: .custom("fun"),
            momentaryActivator: MomentaryActivator(
                input: "space",
                targetLayer: .custom("other")
            )
        )

        let contribution = extractor.contribution(for: collection)

        XCTAssertTrue(contribution.provides.contains(.layerActivation(layer("other"))))
        XCTAssertEqual(
            requirement(in: contribution, for: .layerActivation(layer("fun"))),
            RuleRequirement(
                capability: .layerActivation(layer("fun")),
                evidence: [.mappingIDs([mappingID])]
            )
        )
    }

    func testCustomRulesUseCollectionExtractionAndPreserveEnabledState() {
        let enabledRule = CustomRule(
            id: uuid(21),
            input: "a",
            action: .keystroke(key: "b"),
            isEnabled: true,
            targetLayer: .custom(" NAV ")
        )
        let disabledRule = CustomRule(
            id: uuid(22),
            input: "c",
            action: .keystroke(key: "d"),
            isEnabled: false,
            targetLayer: .custom(" NAV ")
        )

        let graph = adapter.build(collections: [], customRules: [enabledRule, disabledRule])
        let navContent = RuleCapability.layerContent(layer("nav"))

        XCTAssertEqual(graph.knownProviders(for: navContent), [enabledRule.id, disabledRule.id])
        XCTAssertEqual(graph.activeProviders(for: navContent), [enabledRule.id])
        XCTAssertEqual(
            graph.requirements(for: enabledRule.id),
            [RuleRequirement(
                capability: .layerActivation(layer("nav")),
                evidence: [.mappingIDs([enabledRule.id])]
            )]
        )
    }

    func testHomeRowLayerTogglesGroupEnabledKeysAndProvideActivationInBothModes() {
        for toggleMode in [LayerToggleMode.whileHeld, .toggle] {
            let config = HomeRowLayerTogglesConfig(
                enabledKeys: ["a", "d", "f"],
                layerAssignments: [
                    "a": " FUN ",
                    "d": "sym",
                    "f": "FUN",
                    "j": "nav",
                ],
                toggleMode: toggleMode
            )
            let collection = makeCollection(
                id: RuleCollectionIdentifier.homeRowLayerToggles,
                configuration: .homeRowLayerToggles(config)
            )

            let contribution = extractor.contribution(for: collection)

            XCTAssertTrue(contribution.provides.contains(.layerActivation(layer("fun"))))
            XCTAssertTrue(contribution.provides.contains(.layerActivation(layer("sym"))))
            XCTAssertFalse(contribution.provides.contains(.layerActivation(layer("nav"))))
            XCTAssertEqual(
                requirement(in: contribution, for: .layerContent(layer("fun")))?.evidence,
                [.keys(["a", "f"])]
            )
            XCTAssertEqual(
                requirement(in: contribution, for: .layerContent(layer("sym")))?.evidence,
                [.keys(["d"])]
            )
            XCTAssertNil(requirement(in: contribution, for: .layerContent(layer("nav"))))
        }
    }

    func testHomeRowModsOnlyRequireLayerContentInLayerMode() {
        var config = HomeRowModsConfig(
            enabledKeys: ["a", "d"],
            layerAssignments: ["a": "fun", "d": "sym"],
            holdMode: .modifiers
        )
        let modifierCollection = makeCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            configuration: .homeRowMods(config)
        )

        let modifierContribution = extractor.contribution(for: modifierCollection)
        XCTAssertFalse(modifierContribution.provides.contains(.layerActivation(layer("fun"))))
        XCTAssertTrue(modifierContribution.requirements.isEmpty)

        config.holdMode = .layers
        let layerCollection = makeCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            configuration: .homeRowMods(config)
        )
        let layerContribution = extractor.contribution(for: layerCollection)

        XCTAssertTrue(layerContribution.provides.contains(.layerActivation(layer("fun"))))
        XCTAssertTrue(layerContribution.provides.contains(.layerActivation(layer("sym"))))
        XCTAssertEqual(
            requirement(in: layerContribution, for: .layerContent(layer("fun")))?.evidence,
            [.keys(["a"])]
        )
    }

    func testLauncherHyperAndLeaderModesHaveConfigurationSensitiveRequirements() {
        let hyperConfig = LauncherGridConfig(
            activationMode: .holdHyper,
            hyperTriggerMode: .tap,
            mappings: []
        )
        let hyperLauncher = makeCollection(
            id: RuleCollectionIdentifier.launcher,
            targetLayer: .custom(" LAUNCHER "),
            momentaryActivator: MomentaryActivator(
                input: "hyper",
                targetLayer: .custom("launcher")
            ),
            configuration: .launcherGrid(hyperConfig)
        )

        let hyperContribution = extractor.contribution(for: hyperLauncher)
        XCTAssertTrue(hyperContribution.provides.contains(.layerActivation(layer("launcher"))))
        XCTAssertEqual(
            requirement(in: hyperContribution, for: .keyAlias(.hyper))?.evidence,
            [
                .configuration(field: "activationMode", value: "holdHyper"),
                .configuration(field: "hyperTriggerMode", value: "tap"),
            ]
        )
        XCTAssertNil(
            requirement(in: hyperContribution, for: .layerActivation(layer("nav")))
        )

        let leaderConfig = LauncherGridConfig(
            activationMode: .leaderSequence,
            hyperTriggerMode: .hold,
            mappings: []
        )
        let leaderLauncher = makeCollection(
            id: RuleCollectionIdentifier.launcher,
            targetLayer: .custom("launcher"),
            momentaryActivator: MomentaryActivator(
                input: "hyper",
                targetLayer: .custom("launcher")
            ),
            configuration: .launcherGrid(leaderConfig)
        )

        let leaderContribution = extractor.contribution(for: leaderLauncher)
        XCTAssertNil(requirement(in: leaderContribution, for: .keyAlias(.hyper)))
        XCTAssertEqual(
            requirement(
                in: leaderContribution,
                for: .layerActivation(layer("nav"))
            )?.evidence,
            [
                .configuration(field: "activationMode", value: "leaderSequence"),
                .layerPath(source: layer("nav"), target: layer("launcher")),
            ]
        )
    }

    func testLauncherConfigurationOverridesLegacyMomentaryActivatorSource() {
        let launcher = makeCollection(
            id: RuleCollectionIdentifier.launcher,
            targetLayer: .custom("launcher"),
            momentaryActivator: MomentaryActivator(
                input: "hyper",
                targetLayer: .custom("launcher"),
                sourceLayer: .custom("legacy-source")
            ),
            configuration: .launcherGrid(LauncherGridConfig(
                activationMode: .holdHyper,
                mappings: []
            ))
        )

        let contribution = extractor.contribution(for: launcher)

        XCTAssertNotNil(requirement(in: contribution, for: .keyAlias(.hyper)))
        XCTAssertNil(
            requirement(
                in: contribution,
                for: .layerActivation(layer("legacy-source"))
            )
        )
    }

    func testCapsLockRemapProvidesHyperOnlyForExactConfiguredHoldOutput() {
        for (output, expected) in [
            ("hyper", true),
            ("Hyper", false),
            ("meh", false),
        ] {
            let collection = makeCollection(
                id: RuleCollectionIdentifier.capsLockRemap,
                configuration: .tapHoldPicker(TapHoldPickerConfig(
                    inputKey: "caps",
                    tapOptions: [],
                    holdOptions: [],
                    selectedTapOutput: "esc",
                    selectedHoldOutput: output
                ))
            )

            XCTAssertEqual(
                extractor.contribution(for: collection)
                    .provides.contains(.keyAlias(.hyper)),
                expected
            )
        }

        let unrelated = makeCollection(
            configuration: .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: [],
                holdOptions: [],
                selectedHoldOutput: "hyper"
            ))
        )
        XCTAssertFalse(
            extractor.contribution(for: unrelated)
                .provides.contains(.keyAlias(.hyper))
        )
    }

    func testConfiguredLeaderKeyProvidesNavigationActivation() {
        let configured = makeCollection(
            id: RuleCollectionIdentifier.leaderKey,
            configuration: .singleKeyPicker(SingleKeyPickerConfig(
                inputKey: "leader",
                presetOptions: [],
                selectedOutput: " space "
            ))
        )
        let unconfigured = makeCollection(
            id: RuleCollectionIdentifier.leaderKey,
            configuration: .singleKeyPicker(SingleKeyPickerConfig(
                inputKey: "leader",
                presetOptions: [],
                selectedOutput: " "
            ))
        )

        XCTAssertTrue(
            extractor.contribution(for: configured)
                .provides.contains(.layerActivation(layer("nav")))
        )
        XCTAssertFalse(
            extractor.contribution(for: unconfigured)
                .provides.contains(.layerActivation(layer("nav")))
        )
    }

    func testValidSequencesProvideCorrespondingActivationCapabilities() {
        let valid = SequenceDefinition(
            name: "Launcher",
            keys: ["space", "l"],
            action: .activateLayer(.custom(" LAUNCHER "))
        )
        let invalid = SequenceDefinition(
            name: "",
            keys: ["space", "n"],
            action: .activateLayer(.navigation)
        )
        let collection = makeCollection(
            id: RuleCollectionIdentifier.sequences,
            configuration: .sequences(SequencesConfig(sequences: [valid, invalid]))
        )

        let contribution = extractor.contribution(for: collection)

        XCTAssertTrue(contribution.provides.contains(.layerActivation(layer("launcher"))))
        XCTAssertFalse(contribution.provides.contains(.layerActivation(layer("nav"))))
    }

    func testDefaultEffectiveCatalogHasNoMissingPrerequisites() {
        let graph = adapter.build(collections: RuleCollectionCatalog().defaultCollections())

        XCTAssertTrue(missingRequirements(in: graph).isEmpty)
    }

    func testHomeRowLayerTogglesSoloExposeFourMissingContentCapabilitiesWithKeyEvidence() {
        let config = HomeRowLayerTogglesConfig()
        let collection = makeCollection(
            id: RuleCollectionIdentifier.homeRowLayerToggles,
            configuration: .homeRowLayerToggles(config)
        )
        let graph = adapter.build(collections: [collection])

        let missing = Set(missingRequirements(in: graph).map(\.requirement))

        XCTAssertEqual(missing, [
            RuleRequirement(
                capability: .layerContent(layer("fun")),
                evidence: [.keys([";", "a"])]
            ),
            RuleRequirement(
                capability: .layerContent(layer("num")),
                evidence: [.keys(["l", "s"])]
            ),
            RuleRequirement(
                capability: .layerContent(layer("sym")),
                evidence: [.keys(["d", "k"])]
            ),
            RuleRequirement(
                capability: .layerContent(layer("nav")),
                evidence: [.keys(["f", "j"])]
            ),
        ])
    }

    func testHomeRowLayerTogglesWithCompanionLayersHasNoMissingPrerequisites() {
        let toggles = makeCollection(
            id: RuleCollectionIdentifier.homeRowLayerToggles,
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig())
        )
        let companions = ["fun", "num", "sym", "nav"].map { layerName in
            makeCollection(
                id: uuid(100 + stableIndex(for: layerName)),
                mappings: [KeyMapping(input: "x", action: .keystroke(key: "y"))],
                targetLayer: RuleCollectionLayer(kanataName: layerName)
            )
        }

        let graph = adapter.build(collections: [toggles] + companions)

        XCTAssertTrue(missingRequirements(in: graph).isEmpty)
    }

    func testAlternateActiveNavigationProviderPreventsOrphaningConsumer() {
        let disabledProvider = makeCollection(
            id: uuid(30),
            isEnabled: false,
            momentaryActivator: MomentaryActivator(
                input: "space",
                targetLayer: .navigation
            )
        )
        let enabledProvider = makeCollection(
            id: uuid(31),
            momentaryActivator: MomentaryActivator(
                input: "caps",
                targetLayer: .navigation
            )
        )
        let consumer = makeCollection(
            id: uuid(32),
            mappings: [KeyMapping(input: "x", action: .keystroke(key: "y"))],
            targetLayer: .navigation
        )

        let graph = adapter.build(
            collections: [disabledProvider, enabledProvider, consumer]
        )

        XCTAssertEqual(
            graph.knownProviders(for: .layerActivation(layer("nav"))),
            [disabledProvider.id, enabledProvider.id]
        )
        XCTAssertEqual(
            graph.activeProviders(for: .layerActivation(layer("nav"))),
            [enabledProvider.id]
        )
        XCTAssertTrue(missingRequirements(in: graph).isEmpty)
    }

    private func makeCollection(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        mappings: [KeyMapping] = [],
        targetLayer: RuleCollectionLayer = .base,
        momentaryActivator: MomentaryActivator? = nil,
        configuration: RuleCollectionConfiguration = .list
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: "Test",
            summary: "Test",
            category: .custom,
            mappings: mappings,
            isEnabled: isEnabled,
            targetLayer: targetLayer,
            momentaryActivator: momentaryActivator,
            configuration: configuration
        )
    }

    private func layer(_ name: String) -> RuleLayerIdentifier {
        RuleLayerIdentifier(name)
    }

    private func requirement(
        in contribution: RuleDependencyContribution,
        for capability: RuleCapability
    ) -> RuleRequirement? {
        contribution.requirements.first { $0.capability == capability }
    }

    private func missingRequirements(
        in graph: RuleDependencyGraph
    ) -> [(collectionID: UUID, requirement: RuleRequirement)] {
        graph.enabledCollectionIDs.flatMap { collectionID in
            graph.requirements(for: collectionID).compactMap { requirement in
                graph.activeProviders(for: requirement.capability).isEmpty
                    ? (collectionID, requirement)
                    : nil
            }
        }
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        ))!
    }

    private func stableIndex(for layerName: String) -> Int {
        switch layerName {
        case "fun": 1
        case "num": 2
        case "sym": 3
        case "nav": 4
        default: 0
        }
    }
}
