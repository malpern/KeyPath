import Foundation
import KeyPathCore
import KeyPathRulesCore

/// The user action that introduced a proposed prerequisite change.
enum RulePrerequisiteOperation: Equatable, Sendable {
    case enable
    case save
}

/// A presentation-neutral snapshot for the prerequisite confirmation UI.
struct RulePrerequisiteResolutionContext: Equatable, Sendable {
    let operation: RulePrerequisiteOperation
    let candidate: RuleCollection
    let prerequisites: [RulePrerequisite]
    let affectedConsumers: [RuleCollection]
    let availableProviders: [RuleCollection]

    /// Provider IDs are returned in prerequisite order with duplicates removed.
    /// `nil` means at least one requirement does not have one unambiguous provider.
    var recommendedProviderIDs: [UUID]? {
        var seen: Set<UUID> = []
        var result: [UUID] = []

        for prerequisite in prerequisites {
            guard let providerID = prerequisite.recommendedProviderCollectionID else {
                return nil
            }
            if seen.insert(providerID).inserted {
                result.append(providerID)
            }
        }

        return result
    }
}

enum RulePrerequisiteResolutionChoice: Equatable, Sendable {
    case enableRequiredProvidersAndApply
    case applyWithoutProviders
}

extension RuleCollectionsManager {
    /// Resolves the proposed prerequisite consequences before any mutation.
    ///
    /// An empty array means the candidate should be applied alone. A non-empty
    /// array contains provider IDs that should be enabled in the same change.
    /// `nil` means the user cancelled and nothing should be applied.
    func confirmedPrerequisiteProviderIDs(
        for candidate: RuleCollection,
        operation: RulePrerequisiteOperation,
        disablingCollectionIDs: Set<UUID> = [],
        nonInteractiveChoice: RulePrerequisiteResolutionChoice = .applyWithoutProviders
    ) async -> [UUID]? {
        let missing = prerequisites(
            for: candidate,
            disablingCollectionIDs: disablingCollectionIDs
        )
        guard !missing.isEmpty else { return [] }

        let context = prerequisiteResolutionContext(
            operation: operation,
            candidate: candidate,
            prerequisites: missing
        )
        let choice: RulePrerequisiteResolutionChoice
        if let onPrerequisiteResolution {
            guard let confirmedChoice = await onPrerequisiteResolution(context) else {
                return nil
            }
            choice = confirmedChoice
        } else {
            choice = nonInteractiveChoice
        }

        switch choice {
        case .applyWithoutProviders:
            return []
        case .enableRequiredProvidersAndApply:
            guard let providerIDs = context.recommendedProviderIDs else {
                AppLogger.shared.log(
                    "⚠️ [RuleCollections] Automatic prerequisite resolution aborted because a requirement has no unambiguous supporting rule"
                )
                return nil
            }
            return providerIDs
        }
    }

    /// Replaces or appends the candidate and enables confirmed providers
    /// in memory. The caller owns save settlement and recovery.
    func applyPrerequisiteChangeInMemory(
        candidate: RuleCollection,
        providerIDs: [UUID]
    ) {
        if let index = ruleCollections.firstIndex(where: { $0.id == candidate.id }) {
            ruleCollections[index] = candidate
        } else {
            ruleCollections.append(candidate)
        }

        let catalog = RuleCollectionCatalog().defaultCollections()
        for providerID in providerIDs {
            if let index = ruleCollections.firstIndex(where: { $0.id == providerID }) {
                ruleCollections[index].isEnabled = true
            } else if let index = customRules.firstIndex(where: { $0.id == providerID }) {
                customRules[index].isEnabled = true
            } else if var provider = catalog.first(where: { $0.id == providerID }) {
                provider.isEnabled = true
                ruleCollections.append(provider)
            }
        }

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
    }

    /// Applies one proposed save plus its confirmed provider enables as a
    /// single retained transaction, restoring the full snapshot on failure.
    func applyProposedCollectionWithPrerequisites(
        _ candidate: RuleCollection,
        nonInteractiveChoice: RulePrerequisiteResolutionChoice = .applyWithoutProviders,
        skipReload: Bool = false,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async -> [UUID]? {
        await withRuleMutation(using: mutationPermit, failure: nil) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return nil }
            guard let providerIDs = await confirmedPrerequisiteProviderIDs(
                for: candidate,
                operation: .save,
                nonInteractiveChoice: nonInteractiveChoice
            ) else {
                return nil
            }

            applyPrerequisiteChangeInMemory(
                candidate: candidate,
                providerIDs: providerIDs
            )

            guard await commitRuleMutation(snapshot: snapshot, skipReload: skipReload, failureContext: candidate.name, mutationPermit: permit) else {
                return nil
            }

            return providerIDs
        }
    }

    private func prerequisiteResolutionContext(
        operation: RulePrerequisiteOperation,
        candidate: RuleCollection,
        prerequisites: [RulePrerequisite]
    ) -> RulePrerequisiteResolutionContext {
        var knownCollections = [candidate]
        knownCollections.append(contentsOf: ruleCollections.filter { $0.id != candidate.id })
        knownCollections.append(contentsOf: customRules.asRuleCollections())

        let existingIDs = Set(knownCollections.map(\.id))
        knownCollections.append(contentsOf:
            RuleCollectionCatalog().defaultCollections().filter {
                !existingIDs.contains($0.id)
            })

        let providerIDs = Set(
            prerequisites.flatMap(\.availableProviderCollectionIDs)
        )
        let consumerIDs = Set(prerequisites.map(\.consumerCollectionID))
        let consumers = knownCollections.filter { consumerIDs.contains($0.id) }
        let providers = knownCollections.filter { providerIDs.contains($0.id) }

        return RulePrerequisiteResolutionContext(
            operation: operation,
            candidate: candidate,
            prerequisites: prerequisites,
            affectedConsumers: consumers,
            availableProviders: providers
        )
    }
}
