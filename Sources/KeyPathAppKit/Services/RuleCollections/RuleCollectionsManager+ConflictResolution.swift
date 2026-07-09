import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
    // MARK: - Save-time mapping-conflict resolution (#460)

    /// Determine whether a set of save-time mapping conflicts can be resolved by
    /// disabling a collection — i.e. every named party of every conflict maps to a
    /// real, enabled collection by exact name. Synthetic parties (chord group names,
    /// alias key-pairs, the "Leader Key" preference) won't match a collection, so
    /// those conflicts fall back to a plain explanation rather than offering an
    /// action that wouldn't apply.
    ///
    /// - Returns: the distinct collections the user could disable (≥2), or nil when
    ///   the conflicts aren't all collection-vs-collection.
    nonisolated static func resolvableCollectionConflict(
        conflicts: [KeyPathError.MappingConflictInfo],
        collections: [RuleCollection]
    ) -> [RuleCollection]? {
        guard !conflicts.isEmpty else { return nil }

        let byName = Dictionary(
            collections.filter(\.isEnabled).map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var involved: [UUID: RuleCollection] = [:]
        for conflict in conflicts {
            // Every party must resolve to a real enabled collection; otherwise the
            // whole set is treated as non-actionable (explanation fallback).
            for name in conflict.conflictingCollections {
                guard let collection = byName[name] else { return nil }
                involved[collection.id] = collection
            }
        }

        // Need at least two distinct collections for "disable one" to resolve anything.
        guard involved.count >= 2 else { return nil }
        return involved.values.sorted { $0.name < $1.name }
    }

    /// On a save-time mapping-conflict failure, if the conflicting parties are all
    /// real collections, prompt the user to disable one and retry the save (#460).
    /// - Returns: the retry result, or nil when the failure wasn't a resolvable
    ///   mapping conflict or the user cancelled (caller falls back to its error path).
    func tryResolveMappingConflict(_ error: Error, skipReload: Bool, depth: Int) async -> Bool? {
        // Bound retries: each resolution disables one collection (strictly shrinking
        // the enabled set), so this terminates, but the guard prevents pathological loops.
        guard depth < 5,
              let keyPathError = error as? KeyPathError,
              case let .configuration(configError) = keyPathError,
              case let .mappingConflicts(conflicts) = configError,
              let callback = onMappingConflictResolution,
              let resolvable = Self.resolvableCollectionConflict(
                  conflicts: conflicts, collections: ruleCollections
              )
        else { return nil }

        let context = MappingConflictContext(
            explanation: conflicts.map(\.userExplanation).joined(separator: "\n\n"),
            options: resolvable.map {
                MappingConflictOption(id: $0.id, name: $0.name, icon: $0.icon ?? "square.stack.3d.up")
            }
        )

        guard let chosenID = await callback(context),
              let index = ruleCollections.firstIndex(where: { $0.id == chosenID })
        else { return nil } // cancelled → fall back to explanation

        AppLogger.shared.log(
            "🔧 [RuleCollections] Resolving mapping conflict by disabling '\(ruleCollections[index].name)' (#460)"
        )
        // Make the disable atomic: snapshot first, disable in-memory, retry the full
        // save. If the retry still fails (another conflict, depth guard, validation),
        // restore so in-memory state never diverges from what was actually persisted —
        // callers that ignore the `false` return must not see an unsaved disable.
        let snapshot = ruleCollections
        ruleCollections[index].isEnabled = false
        refreshLayerIndicatorState()
        let saved = await regenerateConfigFromCollections(skipReload: skipReload, conflictResolutionDepth: depth + 1)
        if !saved {
            ruleCollections = snapshot
            refreshLayerIndicatorState()
        }
        return saved
    }

    // MARK: - Conflict Resolution

    typealias RuleStateSnapshot = (collections: [RuleCollection], customRules: [CustomRule])

    /// Capture current collections/rules so an operation can be rolled back atomically.
    func snapshotRuleState() -> RuleStateSnapshot {
        (collections: ruleCollections, customRules: customRules)
    }

    /// Restore state snapshot and attempt to re-apply previous config.
    @discardableResult
    func rollbackToSnapshot(_ snapshot: RuleStateSnapshot, userMessage: String) async -> Bool {
        ruleCollections = snapshot.collections
        customRules = snapshot.customRules
        refreshLayerIndicatorState()

        let rollbackApplied = await regenerateConfigFromCollections()
        if rollbackApplied {
            onError?(userMessage)
        } else {
            onError?("\(userMessage) Automatic rollback failed. Please review your configuration.")
        }

        return rollbackApplied
    }

    /// Disable a conflicting rule source (collection or custom rule)
    ///
    /// When `regenerate` is false, this only updates in-memory state so callers can
    /// apply their intended change and regenerate once at the end.
    func disableConflicting(_ source: RuleConflictInfo.Source, regenerate: Bool = true) async {
        guard !regenerate else {
            switch source {
            case let .collection(collection):
                await toggleCollection(id: collection.id, isEnabled: false)
            case let .customRule(rule):
                await toggleCustomRule(id: rule.id, isEnabled: false)
            }
            return
        }

        switch source {
        case let .collection(collection):
            guard let index = ruleCollections.firstIndex(where: { $0.id == collection.id }) else { return }
            ruleCollections[index].isEnabled = false
        case let .customRule(rule):
            guard let index = customRules.firstIndex(where: { $0.id == rule.id }) else { return }
            customRules[index].isEnabled = false
        }
    }
}
