import Foundation
import KeyPathCore
import KeyPathRulesCore

/// One place that decides whether the current rules can be admitted, and why
/// not: key conflicts, needs the backend or Mac cannot meet, the reserved Caps
/// Lock intermediate key, and pack-level conflicts and requirements.
///
/// Phase 3 of docs/architecture/rules-admission-review.md. Pure and additive:
/// nothing calls it yet (phase 4 switches the toggle, editor, pack install,
/// save and startup paths to it). Conflicts come from the existing
/// `RuleCollectionDeduplicator.detectConflicts`, so they match today's results
/// exactly; this adds attribution to rule ids and the cases nothing detected.
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

    // MARK: - Key conflicts (today's detector, attributed)

    private static func conflictVerdicts(_ state: State,
                                         owners: [(subject: AdmissionSubject, collection: RuleCollection)])
        -> [AdmissionVerdict]
    {
        let infos = RuleCollectionDeduplicator.detectConflicts(
            in: state.collections + state.customRules.map { $0.asRuleCollection() },
            leaderKey: state.leaderKey
        )
        return infos.map { info in
            // The detector reports display names, which are not unique; map each
            // back to every enabled owner with that name, or keep the name.
            let parties: [AdmissionSubject] = info.conflictingCollections.flatMap { name in
                let matches = owners.filter { $0.collection.name == name }.map(\.subject)
                return matches.isEmpty ? [.named(name)] : matches
            }
            return AdmissionVerdict(
                severity: .needsChoice,
                subject: parties.first ?? .named(info.inputKey),
                reason: .conflict(key: info.inputKey, layer: info.layer, parties: parties),
                fixes: parties.map { .disable($0) }
            )
        }
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
