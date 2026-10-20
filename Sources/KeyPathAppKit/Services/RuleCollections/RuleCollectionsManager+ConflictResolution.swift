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
    func tryResolveMappingConflict(_ error: Error, skipReload: Bool, depth: Int, mutationPermit: ConfigurationOperationGate.Permit? = nil) async -> RulePersistenceResult? {
        await withRuleMutation(using: mutationPermit, failure: nil) { [self] permit in
            let snapshot = ruleCollections
            guard await resolveMappingConflictInMemory(error, depth: depth, mutationPermit: permit) else { return nil }
            let saved = await persistRules(skipReload: skipReload, conflictResolutionDepth: depth + 1, mutationPermit: permit)
            if !saved.didPersist {
                ruleCollections = snapshot
                refreshLayerIndicatorState()
            }
            return saved
        }
    }

    /// Resolve the same existing conflict choice without choosing a persistence
    /// owner. The caller retains the original snapshot until its save settles.
    func resolveMappingConflictInMemory(_ error: Error, depth: Int, mutationPermit: ConfigurationOperationGate.Permit) async -> Bool {
        await withRuleMutation(using: mutationPermit, failure: false) { [self] _ in
            // Bound retries: each resolution disables one collection (strictly shrinking
            // the enabled set), so this terminates, but the guard prevents pathological loops.
            guard depth < 5,
                  let keyPathError = error as? KeyPathError,
                  case let .configuration(configError) = keyPathError,
                  case .mappingConflicts = configError,
                  let callback = onMappingConflictResolution
            else { return false }

            // Ask the engine about the state that just failed, so the dialog is
            // built from verdicts attributed by id, not by matching display names.
            let state = admissionState(
                collections: ruleCollections.filter { !isNeovimAppScopedReference($0) },
                customRules: customRules
            )
            guard let context = Self.mappingConflictContext(for: state) else { return false }

            guard let chosenID = await callback(context) else { return false } // cancelled → explanation
            if let index = ruleCollections.firstIndex(where: { $0.id == chosenID }) {
                AppLogger.shared.log("🔧 [RuleCollections] Resolving mapping conflict by disabling '\(ruleCollections[index].name)' (#460)")
                ruleCollections[index].isEnabled = false
            } else if let index = customRules.firstIndex(where: { $0.id == chosenID }) {
                AppLogger.shared.log("🔧 [RuleCollections] Resolving mapping conflict by disabling rule '\(customRules[index].displayTitle)'")
                customRules[index].isEnabled = false
            } else {
                return false
            }
            refreshLayerIndicatorState()
            return true
        }
    }

    /// The save-time dialog's content for `state`, from the engine's conflict
    /// verdicts: one explanation per conflict, and one option per rule or custom
    /// rule that could be turned off. Nil when there is no conflict or nothing
    /// to turn off (leader key vs chord group), which falls back to the plain
    /// explanation the caller already shows.
    static func mappingConflictContext(for state: AdmissionEngine.State) -> MappingConflictContext? {
        let verdicts = AdmissionEngine.evaluate(state).filter { if case .conflict = $0.reason { return true }; return false }
        guard !verdicts.isEmpty else { return nil }
        let name = nameLookup(state)
        let presentations = verdicts.map { AdmissionVerdictPresenter.present($0, name: name) }
        var seen = Set<UUID>()
        let options: [MappingConflictOption] = presentations.flatMap(\.options).compactMap { option in
            switch option.subject {
            case let .collection(id):
                guard seen.insert(id).inserted, let c = state.collections.first(where: { $0.id == id }) else { return nil }
                return MappingConflictOption(id: id, name: c.name, icon: c.icon ?? "square.stack.3d.up")
            case let .customRule(id):
                guard seen.insert(id).inserted, let r = state.customRules.first(where: { $0.id == id }) else { return nil }
                return MappingConflictOption(id: id, name: r.displayTitle, icon: "pencil.circle")
            case .pack, .named:
                return nil
            }
        }
        guard !options.isEmpty else { return nil }
        return MappingConflictContext(explanation: presentations.map(\.explanation).joined(separator: "\n\n"), options: options)
    }

    /// What the user calls each party of a verdict.
    nonisolated static func nameLookup(_ state: AdmissionEngine.State) -> (AdmissionSubject) -> String {
        { subject in
            switch subject {
            case let .collection(id): state.collections.first { $0.id == id }?.name ?? "a rule collection"
            case let .customRule(id): state.customRules.first { $0.id == id }?.displayTitle ?? "a custom rule"
            case let .pack(id): PackRegistry.pack(id: id)?.name ?? id
            case let .named(name): name
            }
        }
    }

    // MARK: - Conflict Resolution

    typealias RuleStateSnapshot = (collections: [RuleCollection], customRules: [CustomRule])

    /// Capture current collections/rules so an operation can be rolled back atomically.
    func snapshotRuleState() -> RuleStateSnapshot {
        (collections: ruleCollections, customRules: customRules)
    }

    /// Restore state snapshot and attempt to re-apply previous config.
    @discardableResult
    func rollbackToSnapshot(_ snapshot: RuleStateSnapshot, userMessage: String, mutationPermit: ConfigurationOperationGate.Permit? = nil) async -> Bool {
        await withRuleMutation(using: mutationPermit, failure: false) { [self] permit in
            ruleCollections = snapshot.collections
            customRules = snapshot.customRules
            refreshLayerIndicatorState()

            let rollbackApplied = await regenerateConfigFromCollections(mutationPermit: permit)
            if rollbackApplied {
                onError?(userMessage)
            } else {
                onError?("\(userMessage) Automatic rollback failed. Please review your configuration.")
            }

            return rollbackApplied
        }
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
            case let .named(name):
                AppLogger.shared.log("ℹ️ [RuleCollections] \(name) is not a rule and cannot be disabled from a conflict")
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
        case .named:
            break
        }
    }
}
