import Foundation

struct RuleRecommendation: Equatable {
    let collectionId: UUID
    let reason: String
}

enum RulesRecommendationEngine {
    static func recommendations(from collections: [RuleCollection]) -> [RuleRecommendation] {
        var results: [RuleRecommendation] = []
        var seen = Set<UUID>()
        let byId = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })

        func isEnabled(_ id: UUID) -> Bool {
            byId[id]?.isEnabled == true
        }

        func maybeAdd(_ id: UUID, reason: String) {
            guard let collection = byId[id], !collection.isEnabled else { return }
            guard !seen.contains(id) else { return }
            seen.insert(id)
            results.append(RuleRecommendation(collectionId: id, reason: reason))
        }

        // Popular starter rules that are safe to recommend when disabled.
        maybeAdd(
            RuleCollectionIdentifier.windowSnapping,
            reason: "Popular for faster window management from the keyboard."
        )
        maybeAdd(
            RuleCollectionIdentifier.homeRowMods,
            reason: "Popular for reducing hand movement with hold modifiers."
        )
        maybeAdd(
            RuleCollectionIdentifier.launcher,
            reason: "Popular for app and website launching without leaving the keyboard."
        )
        maybeAdd(
            RuleCollectionIdentifier.symbolLayer,
            reason: "Popular for quick symbol entry in coding and writing workflows."
        )

        if isEnabled(RuleCollectionIdentifier.vimNavigation) {
            maybeAdd(
                RuleCollectionIdentifier.windowSnapping,
                reason: "Pairs well with Vim for fast window movement."
            )
            maybeAdd(
                RuleCollectionIdentifier.homeRowMods,
                reason: "Complements Vim with hold modifiers on home row keys."
            )
        }

        if isEnabled(RuleCollectionIdentifier.symbolLayer) {
            maybeAdd(
                RuleCollectionIdentifier.sequences,
                reason: "Useful for chaining layer activations with short key sequences."
            )
        }

        let enabledProductivityCount = collections.filter { $0.category == .productivity && $0.isEnabled }.count
        if enabledProductivityCount >= 3 {
            maybeAdd(
                RuleCollectionIdentifier.leaderKey,
                reason: "You have multiple productivity rules; Leader Key improves access consistency."
            )
        }

        return results
    }
}
