import Foundation
import KeyPathRulesCore

/// A presentation-neutral snapshot of the enabled rules that would lose a
/// required capability if a provider were disabled.
struct RuleDependentResolutionContext: Equatable, Sendable {
    let providerID: UUID
    let providerName: String
    let dependents: [RuleDependentMapping]
    let affectedConsumers: [RuleCollection]
    let availableProviders: [RuleCollection]
}

enum RuleDependentResolutionChoice: Equatable, Sendable {
    case disableAnyway
}

extension RuleCollectionsManager {
    /// Confirms a proposed disable before any mutation occurs.
    ///
    /// Interactive app callers receive the reverse-dependency dialog.
    /// Headless callers preserve the existing direct-disable behavior.
    func confirmedDisableOfProvider(
        id providerID: UUID,
        name providerName: String
    ) async -> Bool {
        let dependentMappings = dependents(ifDisabling: providerID)
        guard !dependentMappings.isEmpty else { return true }

        guard let onDependentResolution else {
            return true
        }

        let context = dependentResolutionContext(
            providerID: providerID,
            providerName: providerName,
            dependents: dependentMappings
        )
        return await onDependentResolution(context) == .disableAnyway
    }

    private func dependentResolutionContext(
        providerID: UUID,
        providerName: String,
        dependents: [RuleDependentMapping]
    ) -> RuleDependentResolutionContext {
        var knownCollections = ruleCollections
        knownCollections.append(contentsOf: customRules.asRuleCollections())

        let existingIDs = Set(knownCollections.map(\.id))
        knownCollections.append(contentsOf:
            RuleCollectionCatalog().defaultCollections().filter {
                !existingIDs.contains($0.id)
            })

        let consumerIDs = Set(dependents.map(\.dependentCollectionID))
        let providerIDs = Set(
            dependents.flatMap(\.remainingAvailableProviderCollectionIDs)
        )

        return RuleDependentResolutionContext(
            providerID: providerID,
            providerName: providerName,
            dependents: dependents,
            affectedConsumers: knownCollections.filter {
                consumerIDs.contains($0.id)
            },
            availableProviders: knownCollections.filter {
                providerIDs.contains($0.id)
            }
        )
    }
}
