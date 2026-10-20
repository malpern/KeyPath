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
            in: AdmissionEngine.State(collections: others + [proposed], customRules: customRules,
                                      leaderKey: preferencesService.leaderKeyPreference)
        )
    }

    func conflictInfo(for rule: CustomRule) -> RuleConflictInfo? {
        var proposed = rule
        proposed.isEnabled = true
        let collections = ruleCollections.filter { !isNeovimAppScopedReference($0) }
        let otherRules = customRules.filter { $0.id != rule.id }
        return firstConflict(
            involving: .customRule(rule.id),
            in: AdmissionEngine.State(collections: collections, customRules: otherRules + [proposed],
                                      leaderKey: preferencesService.leaderKeyPreference)
        )
    }

    /// Would mappings on `keys` (Kanata names) on `layer` collide with an enabled
    /// custom rule? Kept for callers that have keys rather than a collection;
    /// answered through the same engine via a synthetic candidate.
    func conflictWithCustomRules(_ keys: Set<String>, layer: RuleCollectionLayer) -> RuleConflictInfo? {
        let probe = RuleCollection(
            id: UUID(), name: "probe", summary: "", category: .custom,
            mappings: keys.sorted().map { KeyMapping(input: $0, action: .keystroke(key: $0)) },
            isEnabled: true, icon: "", tags: [], targetLayer: layer, momentaryActivator: nil, configuration: .list
        )
        let collections = ruleCollections.filter { !isNeovimAppScopedReference($0) }
        let state = AdmissionEngine.State(collections: collections + [probe], customRules: customRules,
                                          leaderKey: preferencesService.leaderKeyPreference)
        guard let info = firstConflict(involving: .collection(probe.id), in: state),
              case .customRule = info.source else { return nil }
        return info
    }

    /// The first conflict verdict naming `subject`, folded to one other party and
    /// all the keys they collide on. A synthetic party (the leader key, a chord
    /// group) is reported too; the dialog shows it without offering to disable it.
    private func firstConflict(involving subject: AdmissionSubject, in state: AdmissionEngine.State) -> RuleConflictInfo? {
        var keysByParty: [AdmissionSubject: Set<String>] = [:]
        var order: [AdmissionSubject] = []
        for verdict in AdmissionEngine.evaluate(state) {
            guard case let .conflict(key, _, parties) = verdict.reason, parties.contains(subject) else { continue }
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
