import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
    // MARK: - Conflict Detection

    func isNeovimAppScopedReference(_ collection: RuleCollection) -> Bool {
        collection.id == RuleCollectionIdentifier.neovimTerminal
    }

    func normalizedKeys(for collection: RuleCollection) -> Set<String> {
        // Effective mappings include config-generated ones (Home Row Mods, Window
        // Snapping, Launcher…) whose static `mappings` array is empty — config
        // generation validates against these, so conflict pre-detection must too.
        Set(KanataConfiguration.effectiveMappings(for: collection).map {
            KanataKeyConverter.convertToKanataKey($0.input)
        })
    }

    func normalizedActivator(for collection: RuleCollection) -> (input: String, layer: RuleCollectionLayer)? {
        guard let activator = collection.momentaryActivator else { return nil }
        return (KanataKeyConverter.convertToKanataKey(activator.input), activator.targetLayer)
    }

    /// Toggle-time admission: would enabling `candidate` (as proposed) conflict
    /// with an enabled collection or custom rule? Asks the same `AdmissionEngine`
    /// the save path uses, so toggle-time and save-time can no longer disagree
    /// (they used to be separate implementations with different identity rules
    /// and a first-hit-only toggle check). Returns the first other party with
    /// every key it collides with, in the shape the resolution dialog expects.
    func conflictInfo(
        for candidate: RuleCollection,
        ignoringCollectionIDs: Set<UUID> = []
    ) -> RuleConflictInfo? {
        // Neovim Terminal is app-scoped educational content; the save path drops
        // it from the generated config, so it never conflicts at toggle time.
        if isNeovimAppScopedReference(candidate) {
            return nil
        }
        var proposed = candidate
        proposed.isEnabled = true
        let others = ruleCollections.filter {
            $0.id != candidate.id && !ignoringCollectionIDs.contains($0.id) && !isNeovimAppScopedReference($0)
        }
        return firstConflict(
            involving: .collection(candidate.id),
            in: admissionState(collections: others + [proposed], customRules: customRules)
        )
    }

    func conflictInfo(for rule: CustomRule) -> RuleConflictInfo? {
        var proposed = rule
        proposed.isEnabled = true
        let collections = ruleCollections.filter { !isNeovimAppScopedReference($0) }
        let otherRules = customRules.filter { $0.id != rule.id }
        return firstConflict(
            involving: .customRule(rule.id),
            in: admissionState(collections: collections, customRules: otherRules + [proposed])
        )
    }

    /// The first conflict verdict naming `subject`, folded to one other party and
    /// all the keys they collide on. A synthetic party (the leader key, a chord
    /// group) is reported too; the dialog shows it without offering to disable it.
    private func firstConflict(involving subject: AdmissionSubject, in state: AdmissionEngine.State) -> RuleConflictInfo? {
        var keysByParty: [AdmissionSubject: Set<String>] = [:]
        var order: [AdmissionSubject] = []
        for verdict in AdmissionEngine.evaluate(state) {
            guard case let .conflict(key, _, parties, _) = verdict.reason, parties.contains(subject) else { continue }
            for party in parties where party != subject {
                if keysByParty[party] == nil { order.append(party) }
                keysByParty[party, default: []].insert(key)
            }
        }
        for party in order {
            let keys = Array(keysByParty[party] ?? []).sorted()
            switch party {
            case let .collection(id):
                if let collection = state.collections.first(where: { $0.id == id }) {
                    return RuleConflictInfo(source: .collection(collection), keys: keys)
                }
            case let .customRule(id):
                if let rule = state.customRules.first(where: { $0.id == id }) {
                    return RuleConflictInfo(source: .customRule(rule), keys: keys)
                }
            case let .named(text):
                return RuleConflictInfo(source: .named(text), keys: keys)
            case .pack:
                continue
            }
        }
        return nil
    }
}
