import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
// MARK: - Conflict Resolution

/// Disable a conflicting rule source (collection or custom rule)
func disableConflicting(_ source: RuleConflictInfo.Source) async {
    switch source {
    case let .collection(collection):
        await toggleCollection(id: collection.id, isEnabled: false)
    case let .customRule(rule):
        await toggleCustomRule(id: rule.id, isEnabled: false)
    }
}
}
