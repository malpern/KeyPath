import Foundation
import KeyPathRulesCore

/// A requirement that would be newly unsatisfied by a proposed collection.
///
/// This value is deliberately presentation-free. Dialogs and other clients
/// decide how to describe the capability and its structured evidence.
struct RulePrerequisite: Equatable, Sendable {
    let consumerCollectionID: UUID
    let missingCapability: RuleCapability
    let requirement: RuleRequirement
    let availableProviderCollectionIDs: [UUID]
    let recommendedProviderCollectionID: UUID?
}

/// A dependent requirement that would become unsatisfied after removing a provider.
struct RuleDependentMapping: Equatable, Sendable {
    let dependentCollectionID: UUID
    let newlyUnsatisfiedCapability: RuleCapability
    let requirement: RuleRequirement
    let remainingAvailableProviderCollectionIDs: [UUID]
}

extension RuleCollectionsManager {
    /// Finds requirements newly introduced by enabling or saving `proposedCollection`.
    ///
    /// An existing collection is replaced in place so its display order remains
    /// stable. A new collection is appended. The proposal is always analyzed as
    /// enabled because this query runs before the enable/save mutation.
    func prerequisites(
        for proposedCollection: RuleCollection
    ) -> [RulePrerequisite] {
        let adapter = RuleCollectionDependencyGraphAdapter()
        let currentGraph = adapter.build(
            collections: ruleCollections,
            customRules: customRules
        )

        var candidate = proposedCollection
        candidate.isEnabled = true

        var proposedCollections = ruleCollections
        if let index = proposedCollections.firstIndex(where: { $0.id == candidate.id }) {
            proposedCollections[index] = candidate
        } else {
            proposedCollections.append(candidate)
        }

        let proposedGraph = adapter.build(
            collections: proposedCollections,
            customRules: customRules
        )
        let preexistingMissing = missingRequirementIdentities(in: currentGraph)

        return orderedEnabledConsumerIDs(
            collections: proposedCollections,
            customRules: customRules,
            graph: proposedGraph
        ).flatMap { consumerID in
            proposedGraph.requirements(for: consumerID).compactMap { requirement in
                let identity = MissingRequirementIdentity(
                    consumerID: consumerID,
                    capability: requirement.capability
                )
                guard proposedGraph.activeProviders(for: requirement.capability).isEmpty,
                      !preexistingMissing.contains(identity)
                else {
                    return nil
                }

                let providers = proposedGraph.knownProviders(for: requirement.capability)
                return RulePrerequisite(
                    consumerCollectionID: consumerID,
                    missingCapability: requirement.capability,
                    requirement: requirement,
                    availableProviderCollectionIDs: providers,
                    recommendedProviderCollectionID: providers.count == 1 ? providers[0] : nil
                )
            }
        }
    }

    /// Finds enabled consumers that would become unsatisfied if `collectionID`
    /// stopped contributing capabilities.
    ///
    /// The provider contribution is removed entirely from the proposed graph.
    /// Other enabled and disabled providers remain available for analysis.
    func dependents(
        ifDisabling collectionID: UUID
    ) -> [RuleDependentMapping] {
        let adapter = RuleCollectionDependencyGraphAdapter()
        let currentGraph = adapter.build(
            collections: ruleCollections,
            customRules: customRules
        )
        guard currentGraph.enabledCollectionIDs.contains(collectionID) else {
            return []
        }

        let proposedCollections = ruleCollections.filter { $0.id != collectionID }
        let proposedCustomRules = customRules.filter { $0.id != collectionID }
        let proposedGraph = adapter.build(
            collections: proposedCollections,
            customRules: proposedCustomRules
        )

        return orderedEnabledConsumerIDs(
            collections: proposedCollections,
            customRules: proposedCustomRules,
            graph: proposedGraph
        ).flatMap { consumerID in
            proposedGraph.requirements(for: consumerID).compactMap { requirement in
                let wasSatisfied =
                    !currentGraph.activeProviders(for: requirement.capability).isEmpty
                let isNowMissing =
                    proposedGraph.activeProviders(for: requirement.capability).isEmpty
                guard wasSatisfied, isNowMissing else {
                    return nil
                }

                return RuleDependentMapping(
                    dependentCollectionID: consumerID,
                    newlyUnsatisfiedCapability: requirement.capability,
                    requirement: requirement,
                    remainingAvailableProviderCollectionIDs:
                    proposedGraph.knownProviders(for: requirement.capability)
                )
            }
        }
    }

    private func missingRequirementIdentities(
        in graph: RuleDependencyGraph
    ) -> Set<MissingRequirementIdentity> {
        Set(graph.enabledCollectionIDs.flatMap { consumerID in
            graph.requirements(for: consumerID).compactMap { requirement in
                graph.activeProviders(for: requirement.capability).isEmpty
                    ? MissingRequirementIdentity(
                        consumerID: consumerID,
                        capability: requirement.capability
                    )
                    : nil
            }
        })
    }

    private func orderedEnabledConsumerIDs(
        collections: [RuleCollection],
        customRules: [CustomRule],
        graph: RuleDependencyGraph
    ) -> [UUID] {
        var seen: Set<UUID> = []
        let displayOrder =
            collections.filter(\.isEnabled).map(\.id)
                + customRules.filter(\.isEnabled).map(\.id)
                + graph.collectionIDs.filter { graph.enabledCollectionIDs.contains($0) }

        return displayOrder.filter { seen.insert($0).inserted }
    }
}

private struct MissingRequirementIdentity: Hashable {
    let consumerID: UUID
    let capability: RuleCapability
}
