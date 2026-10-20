import Foundation
import KeyPathCore
import KeyPathRulesCore

/// One place that decides whether the current rules can be admitted, and why
/// not: key conflicts, needs the backend or Mac cannot meet, the reserved Caps
/// Lock intermediate key, and pack-level conflicts and requirements.
///
/// Phase 3 of docs/architecture/rules-admission-review.md; every caller (toggle,
/// editor, pack install, save gate, startup, doctor) asks it. Conflicts are
/// computed here from claims — what each rule puts on which slot — attributed
/// by rule id, never by display name (§4.4g).
@MainActor
enum AdmissionEngine {
    struct State {
        var collections: [RuleCollection]
        var customRules: [CustomRule] = []
        var leaderKey: LeaderKeyPreference?
        var installedPackIDs: Set<String> = []
        /// The live Caps Lock intermediate (Kanata name such as `f18`), when
        /// managed Caps is active; nil otherwise.
        var capsIntermediate: String?
        /// Intermediate candidates already taken by other apps' mappings.
        var occupiedIntermediates: Set<String> = []
        /// Another app that remaps Caps Lock on the chosen keyboard, if any.
        var foreignCapsOwner: String?
    }

    /// The live Caps Lock environment (phase 4d): what the session runtime
    /// learned at its last start, published through
    /// `RuleCollectionsManager.admissionEnvironment` so every evaluation —
    /// toggle, editor save, pack preview — sees the same reserved key, the
    /// same occupied candidates and the same foreign Caps owner.
    struct Environment: Equatable, Sendable {
        /// The intermediate the runtime reserved (Kanata name, `f18`), or
        /// nil when the profile does not use managed Caps.
        var capsIntermediate: String?
        /// Pool keys other apps' mappings or macOS shortcuts already use.
        var occupiedIntermediates: Set<String> = []
        /// Another app remapping Caps Lock on the chosen keyboard.
        var foreignCapsOwner: String?

        /// Before the first session start nothing is known: the engine then
        /// behaves as in phases 1–3 and the runtime's own re-pick at reload
        /// (`SessionCapsRuntimeSupport.admit`) remains the backstop.
        static let unknown = Environment()

        init(capsIntermediate: String? = nil, occupiedIntermediates: Set<String> = [], foreignCapsOwner: String? = nil) {
            self.capsIntermediate = capsIntermediate
            self.occupiedIntermediates = occupiedIntermediates
            self.foreignCapsOwner = foreignCapsOwner
        }

        /// From the runtime's usage numbers.
        init(intermediateUsage: UInt32?, occupied: Set<UInt32>, foreignCapsOwner: String?) {
            capsIntermediate = intermediateUsage.map { SessionCapsIntermediate.kanataName($0).lowercased() }
            occupiedIntermediates = Set(occupied.map { SessionCapsIntermediate.kanataName($0).lowercased() })
            self.foreignCapsOwner = foreignCapsOwner
        }
    }

    static func evaluate(_ state: State,
                         profile: BackendCapabilityProfile = .shared,
                         fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> [AdmissionVerdict]
    {
        let rules = state.customRules.filter(\.isEnabled)
        let enabled = state.collections.filter(\.isEnabled)
        let owners: [(subject: AdmissionSubject, collection: RuleCollection)] =
            enabled.map { (.collection($0.id), $0) } + rules.map { (.customRule($0.id), $0.asRuleCollection()) }

        var verdicts: [AdmissionVerdict] = []
        verdicts += conflictVerdicts(state, owners: owners)
        verdicts += needVerdicts(state, owners: owners, profile: profile, fileExists: fileExists)
        verdicts += reservedKeyVerdicts(state, owners: owners)
        verdicts += packVerdicts(state, fileExists: fileExists)
        return verdicts.sorted { lhs, rhs in
            lhs.severity != rhs.severity ? lhs.severity > rhs.severity
                : String(describing: lhs.subject) < String(describing: rhs.subject)
        }
    }

    // MARK: - Key conflicts (claims, attributed by id)

    /// One party's stake in a slot: who, what they are called, and what the key
    /// does for them (shown when two stakes collide).
    private struct Stake {
        let subject: AdmissionSubject
        let name: String
        let detail: String?
    }

    private struct KeySlot: Hashable {
        let input: String
        let layer: RuleCollectionLayer
    }

    /// Every conflict in `collections` (enabled ones; custom rules already folded
    /// in as collections) plus the leader key. Pure, so the save gate and the CLI
    /// call it off the main actor. Order is the slot order of the claims; callers
    /// that need a total order sort (see `mappingConflicts`).
    nonisolated static func conflicts(in collections: [RuleCollection], leaderKey: LeaderKeyPreference? = nil)
        -> [AdmissionVerdict]
    {
        let owners: [(subject: AdmissionSubject, collection: RuleCollection)] =
            collections.filter(\.isEnabled).map { (.collection($0.id), $0) }
        return conflicts(owners: owners, leaderKey: leaderKey)
    }

    /// The same, for the save gate and the CLI, in the error type they report.
    nonisolated static func mappingConflicts(in collections: [RuleCollection], leaderKey: LeaderKeyPreference? = nil)
        -> [KeyPathError.MappingConflictInfo]
    {
        let names = Dictionary(collections.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return conflicts(in: collections, leaderKey: leaderKey).compactMap { verdict in
            guard case let .conflict(key, layer, parties, details) = verdict.reason else { return nil }
            return KeyPathError.MappingConflictInfo(
                inputKey: key, layer: layer,
                conflictingCollections: parties.map { subject in
                    switch subject {
                    case let .collection(id), let .customRule(id): names[id] ?? "a rule"
                    case let .pack(id): id
                    case let .named(name): name
                    }
                },
                holdDescriptions: details
            )
        }
        // Total order (key, layer, details) so the gate's message is deterministic
        // even when two conflicts share a key (two alias prefixes at once).
        .sorted { lhs, rhs in
            if lhs.inputKey != rhs.inputKey { return lhs.inputKey < rhs.inputKey }
            if lhs.layer != rhs.layer { return lhs.layer < rhs.layer }
            return lhs.holdDescriptions.joined() < rhs.holdDescriptions.joined()
        }
    }

    private static func conflictVerdicts(_ state: State,
                                         owners: [(subject: AdmissionSubject, collection: RuleCollection)])
        -> [AdmissionVerdict]
    {
        conflicts(owners: owners, leaderKey: state.leaderKey)
    }

    private nonisolated static func conflicts(owners: [(subject: AdmissionSubject, collection: RuleCollection)],
                                              leaderKey: LeaderKeyPreference?) -> [AdmissionVerdict]
    {
        var verdicts: [AdmissionVerdict] = []
        func conflict(_ key: String, _ layer: String, _ stakes: [Stake], subject: AdmissionSubject? = nil) {
            verdicts.append(AdmissionVerdict(
                severity: .needsChoice,
                subject: subject ?? stakes[0].subject,
                reason: .conflict(key: key, layer: layer, parties: stakes.map(\.subject),
                                  details: stakes.compactMap(\.detail)),
                fixes: stakes.map(\.subject).filter { if case .named = $0 { false } else { true } }.map { .disable($0) }
            ))
        }
        let leader = leaderKey.flatMap { $0.enabled ? $0 : nil }
        let leaderInput = leader.map { KanataKeyConverter.convertToKanataKey($0.key) }

        // 1. Mappings: one (input, layer) slot carries one action. The leader key
        // (#463) holds its physical key's base slot too: the generator emits it
        // first and keeps it over a later base mapping, which would otherwise be
        // dropped in silence. Within one owner a repeated input is not a
        // conflict (chord groups share keys); that is checked in 4.
        var keySlots: [KeySlot: [Stake]] = [:]
        var slotOrder: [KeySlot] = []
        // Who maps each slot, by id, for the activator check in 2.
        var mappers: [KeySlot: [(subject: AdmissionSubject, name: String)]] = [:]
        func claim(_ slot: KeySlot, _ stake: Stake) {
            if keySlots[slot] == nil { slotOrder.append(slot) }
            keySlots[slot, default: []].append(stake)
        }
        for owner in owners {
            var seen = Set<String>()
            for mapping in KanataConfiguration.effectiveMappings(for: owner.collection) {
                let input = KanataKeyConverter.convertToKanataKey(mapping.input)
                guard seen.insert(input).inserted else { continue }
                let slot = KeySlot(input: input, layer: owner.collection.targetLayer)
                var hold: String?
                if case let .dualRole(dualRole)? = mapping.behavior { hold = dualRole.holdActionString }
                claim(slot, Stake(subject: owner.subject, name: owner.collection.name,
                                  detail: hold.map { "\(owner.collection.name): hold → \($0)" }))
                mappers[slot, default: []].append((owner.subject, owner.collection.name))
            }
        }
        if let leader, let leaderInput {
            claim(KeySlot(input: leaderInput, layer: .base),
                  Stake(subject: .named("Leader Key"), name: "Leader Key",
                        detail: "Leader Key: hold → \(leader.targetLayer.displayName) layer"))
        }
        for slot in slotOrder {
            let stakes = keySlots[slot]!
            guard stakes.count > 1 else { continue }
            conflict(slot.input, slot.layer.displayName, stakes)
        }

        // 2. An activator occupies its key on its source layer (the generator puts
        // the tap-hold there), so another owner mapping that same slot loses
        // silently (#466: Home Row Arrows' `f` shadowing Home Row Mods' hold-`f`).
        // 3. Two activators on one (source layer, key) must agree on the target
        // layer; the same key reaching different layers from different source
        // layers is a valid chain, and identical activators are merely redundant.
        struct ActivatorSlot: Hashable {
            let sourceLayer: RuleCollectionLayer
            let input: String
        }
        var activators: [ActivatorSlot: [(stake: Stake, target: RuleCollectionLayer)]] = [:]
        var activatorOrder: [ActivatorSlot] = []
        func claimActivator(_ slot: ActivatorSlot, _ stake: Stake, target: RuleCollectionLayer) {
            if activators[slot] == nil { activatorOrder.append(slot) }
            activators[slot, default: []].append((stake, target))
        }
        if let leader, let leaderInput {
            claimActivator(ActivatorSlot(sourceLayer: .base, input: leaderInput),
                           Stake(subject: .named("Leader Key"), name: "Leader Key",
                                 detail: "Leader Key: activates \(leader.targetLayer.displayName)"),
                           target: leader.targetLayer)
        }
        for owner in owners {
            guard let activator = owner.collection.momentaryActivator,
                  activator.input.lowercased() != "hyper" // folded into the hyper hold, never a standalone activator
            else { continue }
            let input = KanataKeyConverter.convertToKanataKey(activator.input)
            let name = owner.collection.name
            claimActivator(ActivatorSlot(sourceLayer: activator.sourceLayer, input: input),
                           Stake(subject: owner.subject, name: name,
                                 detail: "\(name): activates \(activator.targetLayer.displayName)"),
                           target: activator.targetLayer)
            let others = (mappers[KeySlot(input: input, layer: activator.sourceLayer)] ?? [])
                .filter { $0.subject != owner.subject }
                .sorted { $0.name < $1.name }
            guard !others.isEmpty else { continue }
            conflict(input, activator.sourceLayer.displayName,
                     [Stake(subject: owner.subject, name: name, detail: "\(name): activates \(activator.targetLayer.displayName)")]
                         + others.map { Stake(subject: $0.subject, name: $0.name, detail: "\($0.name): maps \(input)") })
        }
        for slot in activatorOrder {
            let claims = activators[slot]!
            guard claims.count > 1, Set(claims.map(\.target)).count > 1 else { continue }
            conflict(slot.input, slot.sourceLayer.displayName, claims.map(\.stake))
        }

        // 4. Chord groups within one owner: two groups with one name render to two
        // `(defchords <name> …)` blocks (#464), and two groups sharing a key make
        // duplicate aliases; kanata rejects both.
        for owner in owners {
            guard case let .chordGroups(config) = owner.collection.configuration else { continue }
            let layer = owner.collection.targetLayer.displayName
            for duplicate in config.detectDuplicateGroupNames() {
                let group = Stake(subject: .named("chord group '\(duplicate.name)'"),
                                  name: "chord group '\(duplicate.name)'", detail: nil)
                var stakes = Array(repeating: group, count: duplicate.count)
                stakes[0] = Stake(subject: group.subject, name: group.name,
                                  detail: "\(duplicate.count) chord groups share the name '\(duplicate.name)' — chord group names must be unique")
                conflict(duplicate.name, layer, stakes, subject: owner.subject)
            }
            for crossing in config.detectCrossGroupConflicts() {
                conflict(crossing.key, layer, crossing.groups.map { group in
                    let chords = group.chords.filter { $0.keys.contains(crossing.key) }
                        .map { "(\($0.keys.joined(separator: "+")) → \($0.action.displayName))" }
                        .joined(separator: ", ")
                    return Stake(subject: .named(group.name), name: group.name, detail: "\(group.name): \(chords)")
                }, subject: owner.subject)
            }
        }

        // 5. Alias names (#462): `{prefix}_{layer}_{sanitized input}` maps `-`, space
        // (and more, for device switches) to `_`, so distinct inputs such as
        // `caps-lock` and `caps_lock` can render to one alias, which kanata
        // rejects. They never collide as inputs, so 1 does not see them.
        struct AliasOrigin {
            let subject: AdmissionSubject
            let name: String
            let input: String
            let layer: String
        }
        var aliases: [String: [AliasOrigin]] = [:]
        var aliasOrder: [String] = []
        for owner in owners {
            for mapping in KanataConfiguration.effectiveMappings(for: owner.collection)
                where !mapping.input.contains(" ") // chords render to defchordsv2, not aliases
            {
                for alias in KanataConfiguration.generatedAliasNames(for: mapping, layer: owner.collection.targetLayer) {
                    if aliases[alias] == nil { aliasOrder.append(alias) }
                    aliases[alias, default: []].append(AliasOrigin(subject: owner.subject, name: owner.collection.name,
                                                                   input: mapping.input,
                                                                   layer: owner.collection.targetLayer.displayName))
                }
            }
        }
        for alias in aliasOrder {
            let origins = aliases[alias]!
            let inputs = Set(origins.map(\.input)).sorted()
            guard inputs.count > 1 else { continue } // same input twice is a slot conflict, reported in 1
            var seen = Set<AdmissionSubject>()
            let parties = origins.filter { seen.insert($0.subject).inserted }.sorted { $0.name < $1.name }
            var stakes = parties.map { Stake(subject: $0.subject, name: $0.name, detail: nil) }
            stakes[0] = Stake(subject: stakes[0].subject, name: stakes[0].name,
                              detail: "keys \(inputs.joined(separator: ", ")) all generate the alias '\(alias)'")
            conflict(inputs.joined(separator: " / "), origins[0].layer, stakes)
        }
        return verdicts
    }

    // MARK: - Environment needs (phase 2 inference)

    private static func needVerdicts(_ state: State,
                                     owners: [(subject: AdmissionSubject, collection: RuleCollection)],
                                     profile: BackendCapabilityProfile,
                                     fileExists: (String) -> Bool) -> [AdmissionVerdict]
    {
        owners.flatMap { owner -> [AdmissionVerdict] in
            let needs = RuleCollectionNeedsExtractor.needs(for: owner.collection)
            var verdicts = RuleCollectionNeedsExtractor.unmet(needs, profile: profile, fileExists: fileExists).map {
                AdmissionVerdict(severity: .blocking, subject: owner.subject, reason: .unmetNeed($0),
                                 fixes: [.disable(owner.subject)])
            }
            if needs.contains(.capsLockInput), let other = state.foreignCapsOwner {
                verdicts.append(AdmissionVerdict(severity: .blocking, subject: owner.subject,
                                                 reason: .capsLockHeldByOtherApp(other)))
            }
            return verdicts
        }
    }

    // MARK: - Reserved Caps intermediate (decision 1: move it)

    private static func reservedKeyVerdicts(_ state: State,
                                            owners: [(subject: AdmissionSubject, collection: RuleCollection)])
        -> [AdmissionVerdict]
    {
        guard let reserved = state.capsIntermediate?.lowercased() else { return [] }
        // Same order as `SessionCapsIntermediate.choose`, so the key this names
        // is the key the runtime's re-pick takes at the next session start.
        let pool = SessionCapsIntermediate.pool.map { SessionCapsIntermediate.kanataName($0).lowercased() }
        let usedByRules = Set(owners.flatMap { usedKeys(in: $0.collection) })
        let candidates = pool.filter {
            $0 != reserved && !usedByRules.contains($0) && !state.occupiedIntermediates.contains($0)
        }
        return owners.compactMap { owner in
            guard usedKeys(in: owner.collection).contains(reserved) else { return nil }
            return AdmissionVerdict(
                severity: candidates.isEmpty ? .blocking : .automatic,
                subject: owner.subject,
                reason: .reservedKey(key: reserved),
                fixes: candidates.isEmpty ? [.disable(owner.subject)] : [.moveCapsIntermediate(candidates: candidates)]
            )
        }
    }

    /// Base keys a collection uses as input or emits as output.
    private static func usedKeys(in collection: RuleCollection) -> Set<String> {
        var keys: Set<String> = []
        for mapping in KanataConfiguration.effectiveMappings(for: collection) {
            keys.insert(BackendCapabilityProfile.baseKey(of: mapping.input))
        }
        for case let .emits(key) in RuleCollectionNeedsExtractor.needs(for: collection) {
            keys.insert(BackendCapabilityProfile.baseKey(of: key))
        }
        return keys
    }

    // MARK: - Packs

    private static func packVerdicts(_ state: State, fileExists: (String) -> Bool) -> [AdmissionVerdict] {
        var verdicts: [AdmissionVerdict] = []
        var reported = Set<Set<String>>()
        for packID in state.installedPackIDs.sorted() {
            for conflict in PackDependencyChecker.conflicts(for: packID, installedPackIDs: state.installedPackIDs)
                where reported.insert([packID, conflict.packID]).inserted
            {
                verdicts.append(AdmissionVerdict(
                    severity: .needsChoice, subject: .pack(packID),
                    reason: .packConflict(otherPackID: conflict.packID, description: conflict.description),
                    fixes: [.disable(.pack(packID)), .disable(.pack(conflict.packID))]
                ))
            }
            guard let pack = PackRegistry.pack(id: packID) else { continue }
            for need in RuleCollectionNeedsExtractor.unmet(Set(pack.requires), fileExists: fileExists) {
                var fixes: [AdmissionVerdict.Fix] = []
                if case let .externalApp(name, path) = need { fixes = [.installApp(name: name, path: path)] }
                verdicts.append(AdmissionVerdict(severity: .blocking, subject: .pack(packID),
                                                 reason: .unmetNeed(need), fixes: fixes))
            }
        }
        return verdicts
    }
}

extension AdmissionEngine.State {
    /// Rules plus the live environment the manager holds.
    init(collections: [RuleCollection], customRules: [CustomRule] = [], leaderKey: LeaderKeyPreference? = nil,
         installedPackIDs: Set<String> = [], environment: AdmissionEngine.Environment)
    {
        self.init(collections: collections, customRules: customRules, leaderKey: leaderKey,
                  installedPackIDs: installedPackIDs,
                  capsIntermediate: environment.capsIntermediate,
                  occupiedIntermediates: environment.occupiedIntermediates,
                  foreignCapsOwner: environment.foreignCapsOwner)
    }
}
