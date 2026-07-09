import Foundation
import KeyPathRulesCore

/// Checks pack dependencies against current system state.
///
/// Simple flat validation — iterates each pack's requirements and checks
/// if they're met. No graph traversal needed for ~15 packs with 1-2 depth chains.
@MainActor
enum PackDependencyChecker {
    /// Returns unmet hard requirements for a specific pack.
    static func unmetRequirements(
        for packID: String,
        enabledCollections: [RuleCollection],
        installedPackIDs: Set<String>
    ) -> [UnmetDependency] {
        guard let pack = PackRegistry.pack(id: packID) else { return [] }

        let enabledIDs = Set(enabledCollections.filter(\.isEnabled).map(\.id))

        return pack.dependencies.filter { $0.kind == .requires }.compactMap { dep in
            checkDependency(dep, enabledCollections: enabledCollections,
                            enabledIDs: enabledIDs, installedPackIDs: installedPackIDs)
        }
    }

    /// Returns all unmet requirements across all enabled packs.
    /// Used to show warning badges in the rules list.
    static func allUnmetRequirements(
        enabledCollections: [RuleCollection],
        installedPackIDs: Set<String>
    ) -> [String: [UnmetDependency]] {
        var result: [String: [UnmetDependency]] = [:]

        let enabledIDs = Set(enabledCollections.filter(\.isEnabled).map(\.id))

        for pack in PackRegistry.starterKit {
            let isPackOn: Bool
            if pack.visualOnly {
                isPackOn = installedPackIDs.contains(pack.id)
            } else if let collectionID = pack.associatedCollectionID {
                isPackOn = enabledIDs.contains(collectionID)
            } else {
                continue
            }

            guard isPackOn else { continue }

            let unmet = pack.dependencies.filter { $0.kind == .requires }.compactMap { dep in
                checkDependency(dep, enabledCollections: enabledCollections,
                                enabledIDs: enabledIDs, installedPackIDs: installedPackIDs)
            }

            if !unmet.isEmpty {
                result[pack.id] = unmet
            }
        }

        return result
    }

    /// Returns soft suggestions for a pack (enabled packs it works well with).
    static func suggestions(for packID: String, installedPackIDs: Set<String>) -> [PackDependency] {
        guard let pack = PackRegistry.pack(id: packID) else { return [] }
        return pack.dependencies.filter { dep in
            dep.kind == .enhancedBy && !installedPackIDs.contains(dep.packID)
        }
    }

    /// Returns packs that depend on a given pack (for disable warnings).
    static func dependents(
        of packID: String,
        enabledCollections: [RuleCollection],
        installedPackIDs: Set<String>
    ) -> [Pack] {
        let enabledIDs = Set(enabledCollections.filter(\.isEnabled).map(\.id))

        return PackRegistry.starterKit.filter { pack in
            guard pack.id != packID else { return false }

            let isPackOn: Bool
            if pack.visualOnly {
                isPackOn = installedPackIDs.contains(pack.id)
            } else if let collectionID = pack.associatedCollectionID {
                isPackOn = enabledIDs.contains(collectionID)
            } else {
                return false
            }

            guard isPackOn else { return false }

            return pack.dependencies.contains { dep in
                (dep.kind == .requires || dep.kind == .enhancedBy) && dep.packID == packID
            }
        }
    }

    // MARK: - Private

    private static func checkDependency(
        _ dep: PackDependency,
        enabledCollections: [RuleCollection],
        enabledIDs: Set<UUID>,
        installedPackIDs: Set<String>
    ) -> UnmetDependency? {
        guard let targetPack = PackRegistry.pack(id: dep.packID) else { return nil }

        // Check if the target pack is enabled
        let isTargetEnabled: Bool = if targetPack.visualOnly {
            installedPackIDs.contains(targetPack.id)
        } else if let collectionID = targetPack.associatedCollectionID {
            enabledIDs.contains(collectionID)
        } else {
            false
        }

        guard isTargetEnabled else {
            return UnmetDependency(dependency: dep, reason: .notEnabled)
        }

        // Check config predicate if specified
        if let predicate = dep.configPredicate,
           let collectionID = targetPack.associatedCollectionID,
           let collection = enabledCollections.first(where: { $0.id == collectionID })
        {
            if !evaluatePredicate(predicate, on: collection) {
                return UnmetDependency(dependency: dep, reason: .configMismatch)
            }
        }

        return nil
    }

    private static func evaluatePredicate(
        _ predicate: ConfigPredicate,
        on collection: RuleCollection
    ) -> Bool {
        switch predicate {
        case .isEnabled:
            return collection.isEnabled

        case let .holdOutput(expected):
            if case let .tapHoldPicker(config) = collection.configuration {
                let currentHold = config.selectedHoldOutput ?? config.holdOptions.first?.output
                return currentHold == expected
            }
            return false

        case let .tapOutput(expected):
            if case let .tapHoldPicker(config) = collection.configuration {
                let currentTap = config.selectedTapOutput ?? config.tapOptions.first?.output
                return currentTap == expected
            }
            return false
        }
    }
}
