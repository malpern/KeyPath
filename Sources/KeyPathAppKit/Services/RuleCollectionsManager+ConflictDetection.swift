import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
// MARK: - Conflict Detection

func normalizedKeys(for collection: RuleCollection) -> Set<String> {
    Set(collection.mappings.map { KanataKeyConverter.convertToKanataKey($0.input) })
}

func normalizedActivator(for collection: RuleCollection) -> (input: String, layer: RuleCollectionLayer)? {
    guard let activator = collection.momentaryActivator else { return nil }
    return (KanataKeyConverter.convertToKanataKey(activator.input), activator.targetLayer)
}

func conflictInfo(for candidate: RuleCollection) -> RuleConflictInfo? {
    let candidateKeys = normalizedKeys(for: candidate)
    let candidateActivator = normalizedActivator(for: candidate)

    for other in ruleCollections where other.isEnabled && other.id != candidate.id {
        if candidate.targetLayer == other.targetLayer {
            let overlap = candidateKeys.intersection(normalizedKeys(for: other))
            if !overlap.isEmpty {
                return RuleConflictInfo(source: .collection(other), keys: Array(overlap))
            }
        }

        if let act1 = candidateActivator,
           let act2 = normalizedActivator(for: other)
        {
            if act1 == act2 {
                // Identical momentary activators are treated as redundant, not conflicts
                continue
            }
            if act1.input == act2.input {
                return RuleConflictInfo(source: .collection(other), keys: [act1.input])
            }
        }
    }

    if let conflict = conflictWithCustomRules(candidateKeys, layer: candidate.targetLayer) {
        return conflict
    }

    return nil
}

func conflictInfo(for rule: CustomRule) -> RuleConflictInfo? {
    let normalizedKey = KanataKeyConverter.convertToKanataKey(rule.input)

    for collection in ruleCollections where collection.isEnabled && collection.targetLayer == rule.targetLayer {
        if normalizedKeys(for: collection).contains(normalizedKey) {
            return RuleConflictInfo(source: .collection(collection), keys: [normalizedKey])
        }
    }

    for other in customRules where other.isEnabled && other.id != rule.id {
        if KanataKeyConverter.convertToKanataKey(other.input) == normalizedKey {
            return RuleConflictInfo(source: .customRule(other), keys: [normalizedKey])
        }
    }

    return nil
}

func conflictWithCustomRules(_ keys: Set<String>, layer: RuleCollectionLayer) -> RuleConflictInfo? {
    for rule in customRules where rule.isEnabled && rule.targetLayer == layer {
        let normalized = KanataKeyConverter.convertToKanataKey(rule.input)
        if keys.contains(normalized) {
            return RuleConflictInfo(source: .customRule(rule), keys: [normalized])
        }
    }
    return nil
}

}
