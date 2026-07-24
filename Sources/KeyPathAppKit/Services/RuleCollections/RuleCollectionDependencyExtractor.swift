import Foundation
import KeyPathRulesCore

/// Converts configured rule collections into the pure dependency graph inputs.
///
/// The extractor deliberately keeps each configuration family explicit. A
/// collection's enabled state is not consulted here: disabled collections are
/// still potential providers, and the graph adapter decides which providers
/// are active in a particular snapshot.
struct RuleCollectionDependencyExtractor {
    func contribution(for collection: RuleCollection) -> RuleDependencyContribution {
        let effectiveMappings = KanataConfiguration.effectiveMappings(for: collection)
        var provides: Set<RuleCapability> = []
        var requirements: Set<RuleRequirement> = []

        if !effectiveMappings.isEmpty {
            provides.insert(.layerContent(RuleLayerIdentifier(collection.targetLayer)))
        }

        switch collection.configuration {
        case let .homeRowLayerToggles(config):
            addLayerAssignments(
                enabledKeys: config.enabledKeys,
                assignments: config.layerAssignments,
                provides: &provides,
                requirements: &requirements
            )

        case let .homeRowMods(config) where config.holdMode == .layers:
            addLayerAssignments(
                enabledKeys: config.enabledKeys,
                assignments: config.layerAssignments,
                provides: &provides,
                requirements: &requirements
            )

        case let .launcherGrid(config):
            addLauncherContribution(
                config: config,
                targetLayer: collection.targetLayer,
                provides: &provides,
                requirements: &requirements
            )

        case let .sequences(config):
            for sequence in config.sequences where sequence.isValid {
                if case let .activateLayer(layer) = sequence.action {
                    provides.insert(.layerActivation(RuleLayerIdentifier(layer)))
                }
            }

        case let .tapHoldPicker(config)
            where collection.id == RuleCollectionIdentifier.capsLockRemap
            && config.selectedHoldOutput == "hyper":
            provides.insert(.keyAlias(.hyper))

        default:
            break
        }

        if collection.id == RuleCollectionIdentifier.leaderKey,
           configuredLeaderKey(in: collection) != nil
        {
            provides.insert(.layerActivation(RuleLayerIdentifier(.navigation)))
        }

        let usesConfigurationDefinedLauncherActivation =
            collection.configuration.launcherGridConfig != nil

        if !usesConfigurationDefinedLauncherActivation,
           let activator = functionalActivator(in: collection)
        {
            let source = RuleLayerIdentifier(activator.sourceLayer)
            let target = RuleLayerIdentifier(activator.targetLayer)
            provides.insert(.layerActivation(target))

            if activator.sourceLayer != .base {
                requirements.insert(RuleRequirement(
                    capability: .layerActivation(source),
                    evidence: [.layerPath(source: source, target: target)]
                ))
            }
        }

        let hasOwnActivation = usesConfigurationDefinedLauncherActivation
            || functionalActivator(in: collection) != nil
            || provides.contains(.layerActivation(RuleLayerIdentifier(collection.targetLayer)))

        if collection.targetLayer != .base,
           !effectiveMappings.isEmpty,
           !hasOwnActivation
        {
            let target = RuleLayerIdentifier(collection.targetLayer)
            var evidence: Set<RuleDependencyEvidence> = []
            let mappingIDs = effectiveMappings.map(\.id)
            if !mappingIDs.isEmpty {
                evidence.insert(.mappingIDs(mappingIDs))
            }
            requirements.insert(RuleRequirement(
                capability: .layerActivation(target),
                evidence: evidence
            ))
        }

        return RuleDependencyContribution(
            collectionID: collection.id,
            provides: provides,
            requirements: requirements
        )
    }

    private func addLayerAssignments(
        enabledKeys: Set<String>,
        assignments: [String: String],
        provides: inout Set<RuleCapability>,
        requirements: inout Set<RuleRequirement>
    ) {
        let keysByLayer = Dictionary(grouping: enabledKeys.compactMap { key -> (String, String)? in
            guard let layerName = assignments[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !layerName.isEmpty
            else {
                return nil
            }
            return (layerName, key)
        }, by: { RuleLayerIdentifier($0.0) })

        for (layer, assignments) in keysByLayer {
            provides.insert(.layerActivation(layer))
            requirements.insert(RuleRequirement(
                capability: .layerContent(layer),
                evidence: [.keys(assignments.map(\.1).sorted())]
            ))
        }
    }

    private func addLauncherContribution(
        config: LauncherGridConfig,
        targetLayer: RuleCollectionLayer,
        provides: inout Set<RuleCapability>,
        requirements: inout Set<RuleRequirement>
    ) {
        let target = RuleLayerIdentifier(targetLayer)
        provides.insert(.layerActivation(target))

        switch config.activationMode {
        case .holdHyper:
            requirements.insert(RuleRequirement(
                capability: .keyAlias(.hyper),
                evidence: [
                    .configuration(field: "activationMode", value: config.activationMode.rawValue),
                    .configuration(field: "hyperTriggerMode", value: config.hyperTriggerMode.rawValue),
                ]
            ))

        case .leaderSequence:
            let navigation = RuleLayerIdentifier(.navigation)
            requirements.insert(RuleRequirement(
                capability: .layerActivation(navigation),
                evidence: [
                    .configuration(field: "activationMode", value: config.activationMode.rawValue),
                    .layerPath(source: navigation, target: target),
                ]
            ))
        }
    }

    private func functionalActivator(in collection: RuleCollection) -> MomentaryActivator? {
        guard let activator = collection.momentaryActivator,
              !activator.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              activator.targetLayer != .base
        else {
            return nil
        }
        return activator
    }

    private func configuredLeaderKey(in collection: RuleCollection) -> String? {
        guard case let .singleKeyPicker(config) = collection.configuration else {
            return nil
        }
        let output = config.selectedOutput ?? config.presetOptions.first?.output
        guard let output = output?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty
        else {
            return nil
        }
        return output
    }
}

/// Builds a dependency graph from persisted collections and custom rules.
///
/// Custom rules use their existing `RuleCollection` adapter so custom and
/// built-in mappings share exactly the same extraction rules.
struct RuleCollectionDependencyGraphAdapter {
    private let extractor = RuleCollectionDependencyExtractor()

    func build(
        collections: [RuleCollection],
        customRules: [CustomRule] = []
    ) -> RuleDependencyGraph {
        let customCollections = customRules.asRuleCollections()
        let allCollections = collections + customCollections
        return RuleDependencyGraph.build(
            from: allCollections.map(extractor.contribution(for:)),
            enabledCollectionIDs: Set(allCollections.filter(\.isEnabled).map(\.id))
        )
    }
}
