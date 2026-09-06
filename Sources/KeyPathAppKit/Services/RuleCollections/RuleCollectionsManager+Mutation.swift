import Foundation
import KeyPathCore
import KeyPathRulesCore

extension RuleCollectionsManager {
    /// Admission precedes snapshots and mutation. Nested internal calls carry an
    /// explicit permit; callbacks without one fail rather than deadlock/reenter.
    func withRuleMutation<Result: Sendable>(
        using permit: ConfigurationOperationGate.Permit? = nil,
        failure: Result,
        _ operation: @escaping @MainActor @Sendable (ConfigurationOperationGate.Permit) async -> Result
    ) async -> Result {
        do {
            return try await configurationService.operationGate.withOperation(using: permit) { @MainActor admitted in
                await operation(admitted)
            }
        } catch is CancellationError {
            return failure
        } catch {
            onError?(error.localizedDescription)
            return failure
        }
    }

    /// Recover interrupted source writes before taking the next editor snapshot.
    func recoverAndSnapshotRuleState(mutationPermit: ConfigurationOperationGate.Permit) async -> RuleStateSnapshot? {
        do {
            try await recoverRuleState(mutationPermit: mutationPermit)
            return snapshotRuleState()
        } catch is CancellationError {
            return nil
        } catch {
            onError?(error.localizedDescription)
            return nil
        }
    }

    /// Throwing preparation for save owners that report their own failure result.
    func recoverRuleState(mutationPermit: ConfigurationOperationGate.Permit) async throws {
        try await configurationService.recoverPendingAppKeymapWrite(mutationPermit: mutationPermit)
        let recovered = try await configurationService.recoverPendingRuleWrite(
            collectionStore: ruleCollectionStore, customStore: customRulesStore,
            mutationPermit: mutationPermit, preferenceDefaults: preferencesService.persistenceDefaults
        )
        if pendingLeaderKeyPreference == nil {
            preferencesService.reloadLeaderKeyPreference(from: preferencesService.persistenceDefaults)
        }
        try await refreshRecoveredRuleStateIfNeeded(recovered, mutationPermit: mutationPermit)
    }

    /// Do not let a retry use stale arrays after journal recovery succeeded but
    /// source decoding failed. Clear the requirement only after both stores load.
    func refreshRecoveredRuleStateIfNeeded(_ recovered: Bool, mutationPermit: ConfigurationOperationGate.Permit) async throws {
        needsRecoveredRuleStateRefresh = needsRecoveredRuleStateRefresh || recovered
            || observedRuleRecoveryRevision != configurationService.ruleRecoveryRevision
        if needsRecoveredRuleStateRefresh {
            let collections = await ruleCollectionStore.loadCollectionsDetailed()
            guard !collections.wasFullReset, collections.failedCollectionNames.isEmpty else {
                throw KeyPathError.configuration(.loadFailed(reason: "Recovered rule collections could not be read completely. No edit was made."))
            }
            let rules = try await customRulesStore.loadForMutation()
            ruleCollections = RuleCollectionDeduplicator.dedupe(collections.collections)
            customRules = rules
            needsRecoveredRuleStateRefresh = false
            observedRuleRecoveryRevision = configurationService.ruleRecoveryRevision
            refreshLayerIndicatorState()
        }
        // The configuration owner retains this requirement across app/rule/raw
        // editors sharing it, including failed recovery after journal removal.
        _ = try await configurationService.applyRecoveredRuntimeIfNeeded(mutationPermit: mutationPermit, reloadHandler: onRulesChanged)
    }

    /// Preserve the editor's existing enable policy while sharing preparation and
    /// settlement. The Boolean means newly enabled AND committed, not applied.
    func updateCollectionSettings(id: UUID, enableExisting: Bool = true,
                                  update: @escaping @MainActor @Sendable (inout RuleCollection) -> Void) async -> Bool
    {
        await withRuleMutation(failure: false) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return false }
            let existing = ruleCollections.first(where: { $0.id == id })
            guard var candidate = existing ?? RuleCollectionCatalog().defaultCollections().first(where: { $0.id == id }) else { return false }
            let wasNewlyEnabled = existing == nil || (enableExisting && !candidate.isEnabled)
            update(&candidate)
            if enableExisting || existing == nil { candidate.isEnabled = true }
            if let index = ruleCollections.firstIndex(where: { $0.id == id }) { ruleCollections[index] = candidate }
            else { ruleCollections.append(candidate) }
            dedupeRuleCollectionsInPlace()
            refreshLayerIndicatorState()
            guard await commitRuleMutation(snapshot: snapshot, failureContext: candidate.name, mutationPermit: permit) else { return false }
            return wasNewlyEnabled
        }
    }

    /// Compatibility for editor callers that only need committed/not committed.
    @discardableResult
    func commitRuleMutation(snapshot: RuleStateSnapshot, skipReload: Bool = false, failureContext: String? = nil,
                            leaderPreferenceBefore: LeaderPreferenceSnapshot? = nil,
                            keymapBefore: (id: String, includePunctuation: Bool)? = nil,
                            mutationPermit: ConfigurationOperationGate.Permit) async -> Bool
    {
        await commitRuleMutationResult(snapshot: snapshot, skipReload: skipReload, failureContext: failureContext,
                                       leaderPreferenceBefore: leaderPreferenceBefore, keymapBefore: keymapBefore,
                                       mutationPermit: mutationPermit).success
    }

    /// The save owner restores files/runtime; the manager restores its in-memory
    /// candidate without regenerating over the recovered or externally edited files.
    @discardableResult
    func commitRuleMutationResult(snapshot: RuleStateSnapshot, skipReload: Bool = false, failureContext: String? = nil, leaderPreferenceBefore: LeaderPreferenceSnapshot? = nil,
                                  keymapBefore: (id: String, includePunctuation: Bool)? = nil,
                                  packRecord: InstalledPackTracker.RecordChange? = nil,
                                  mutationPermit: ConfigurationOperationGate.Permit) async -> SaveResult
    {
        let preparedLeaderPreference = pendingLeaderKeyPreference ?? preferencesService.leaderKeyPreference
        let preparedKeymap = (id: activeKeymapId, includePunctuation: keymapIncludesPunctuation)
        var preferenceChanges: [RecoverableRuleWrite.PreferenceChange] = []
        do {
            if leaderPreferenceBefore != nil {
                try preferenceChanges.append(.leader(
                    before: leaderPreferenceBefore?.data,
                    after: JSONEncoder().encode(preparedLeaderPreference)
                ))
            }
        } catch {
            pendingLeaderKeyPreference = nil
            return .failure(error)
        }
        let result = await SaveCoordinator(configurationService: configurationService).saveRuleState(
            manager: self, mutationPermit: mutationPermit, packRecord: packRecord,
            preferenceChanges: preferenceChanges,
            leaderKeyPreference: leaderPreferenceBefore == nil ? nil : preparedLeaderPreference,
            reloadHandler: skipReload ? nil : onRulesChanged
        )
        pendingLeaderKeyPreference = nil
        guard result.success else {
            ruleCollections = snapshot.collections
            customRules = snapshot.customRules
            var preferenceRecoveryDetail = ""
            if let leaderPreferenceBefore {
                if preferencesService.leaderKeyPreference != leaderPreferenceBefore.value {
                    preferenceRecoveryDetail = " A newer leader-key preference was preserved."
                }
            }
            if let keymapBefore {
                activeKeymapId = keymapBefore.id
                keymapIncludesPunctuation = keymapBefore.includePunctuation
                KeymapPreferences.restoreFailedSelection(
                    attemptedID: preparedKeymap.id, attemptedPunctuation: preparedKeymap.includePunctuation,
                    previousID: keymapBefore.id, previousPunctuation: keymapBefore.includePunctuation,
                    userDefaults: keymapPreferences
                )
            }
            refreshLayerIndicatorState()
            if let error = result.error, !(error is CancellationError) {
                let message = failureContext.map { "Could not save \($0): \(error.localizedDescription)" } ?? error.localizedDescription
                onError?(message + preferenceRecoveryDetail)
                SoundManager.shared.playErrorSound()
            }
            return result
        }
        if leaderPreferenceBefore != nil {
            preferencesService.reloadLeaderKeyPreference(from: preferencesService.persistenceDefaults)
        }
        NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
        return result
    }
}
