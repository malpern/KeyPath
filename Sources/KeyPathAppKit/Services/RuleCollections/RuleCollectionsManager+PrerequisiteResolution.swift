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
        nonInteractiveChoice: RulePrerequisiteResolutionChoice = .applyWithoutProviders
    ) async -> [UUID]? {
        let missing = prerequisites(for: candidate)
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
            // Ambiguous graphs cannot be auto-fixed safely. Interactive callers
            // hide the action; non-interactive callers fall back to applying
            // without providers.
            return context.recommendedProviderIDs ?? []
        }
    }

    /// Replaces or appends the candidate and enables confirmed providers
    /// in memory. The caller owns the single regeneration and rollback.
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
    /// single mutation and regeneration, restoring the full snapshot on failure.
    func applyProposedCollectionWithPrerequisites(
        _ candidate: RuleCollection,
        rollbackMessage: String,
        nonInteractiveChoice: RulePrerequisiteResolutionChoice = .applyWithoutProviders
    ) async -> [UUID]? {
        let snapshot = snapshotRuleState()
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

        guard await regenerateConfigFromCollections() else {
            AppLogger.shared.log(
                "↩️ [RuleCollections] Prerequisite-aware save failed; rolling back"
            )
            await rollbackToSnapshot(snapshot, userMessage: rollbackMessage)
            return nil
        }

        return providerIDs
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
