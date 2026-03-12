import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
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
