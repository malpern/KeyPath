import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
    // MARK: - Public API

    /// Get all enabled mappings from collections and custom rules
    func enabledMappings() -> [KeyMapping] {
        ruleCollections.enabledMappings() + customRules.enabledMappings()
    }

    /// Replace all rule collections
    func replaceCollections(_ collections: [RuleCollection]) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            let leaderSnapshot = snapshotLeaderPreference()
            ruleCollections = RuleCollectionDeduplicator.dedupe(collections)
            dedupeRuleCollectionsInPlace()
            refreshLayerIndicatorState()
            let didReconcileLeader = reconcileLeaderKeyFromCollection()
            await commitRuleMutation(snapshot: snapshot, failureContext: "rule collections",
                                     leaderPreferenceBefore: didReconcileLeader ? leaderSnapshot : nil, mutationPermit: permit)
        }
    }

    /// Toggle a rule collection on/off.
    ///
    /// `configurationOverride` lets a catalog surface apply an explicit
    /// user selection in the same save/reload transaction as enabling the
    /// collection. It is intentionally optional so existing callers retain
    /// their current configuration.
    /// `additionalCollectionIDsToDisable` stages related catalog collections
    /// in the same transaction. It is used when activating one managed pack
    /// replaces an untouched, not-yet-installed catalog experience.
    /// `skipReload` lets a higher-level transaction validate the resulting
    /// live reload itself without triggering a duplicate cooldown-blocked
    /// attempt. The configuration is still validated and persisted.
    /// - Returns: `true` if the toggle was applied successfully, `false` if validation failed and state was rolled back
    @discardableResult
    func toggleCollection(
        id: UUID,
        isEnabled: Bool,
        autoResolveConflicts: Bool = false,
        bypassOwnershipCheck: Bool = false,
        configurationOverride: RuleCollectionConfiguration? = nil,
        additionalCollectionIDsToDisable: Set<UUID> = [],
        skipReload: Bool = false,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async -> Bool {
        await toggleCollectionResult(id: id, isEnabled: isEnabled, autoResolveConflicts: autoResolveConflicts,
                                     bypassOwnershipCheck: bypassOwnershipCheck, configurationOverride: configurationOverride,
                                     additionalCollectionIDsToDisable: additionalCollectionIDsToDisable, skipReload: skipReload,
                                     mutationPermit: mutationPermit).success
    }

    @discardableResult
    func toggleCollectionResult(
        id: UUID,
        isEnabled: Bool,
        autoResolveConflicts: Bool = false,
        bypassOwnershipCheck: Bool = false,
        configurationOverride: RuleCollectionConfiguration? = nil,
        additionalCollectionIDsToDisable: Set<UUID> = [],
        skipReload: Bool = false,
        packRecord: InstalledPackTracker.RecordChange? = nil,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async -> SaveResult {
        do {
            return try await configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
                AppLogger.shared.log("🔀 [RuleCollections] toggleCollection called: id=\(id), isEnabled=\(isEnabled)")

                try await recoverRuleState(mutationPermit: permit)
                let snapshot = snapshotRuleState()
                if !bypassOwnershipCheck {
                    if let owner = await InstalledPackTracker.shared.packManagingCollection(id) {
                        AppLogger.shared.log(
                            "🔒 [RuleCollections] Toggle blocked: collection \(id) is managed by pack '\(owner.packName)'"
                        )
                        return .failure(KeyPathError.configuration(.validationFailed(errors: ["Collection is managed by \(owner.packName); change it through that pack."])))
                    }
                }

                let leaderPreferenceSnapshot = snapshotLeaderPreference()

                let catalogMatch = RuleCollectionCatalog().defaultCollections().first { $0.id == id }
                AppLogger.shared.log("🔀 [RuleCollections] catalogMatch=\(catalogMatch?.name ?? "nil")")
                guard var candidate = ruleCollections.first(where: { $0.id == id }) ?? catalogMatch else {
                    return .failure(KeyPathError.configuration(.validationFailed(errors: ["No matching collection was found."])))
                }
                candidate.isEnabled = isEnabled
                if let configurationOverride {
                    candidate.configuration = configurationOverride
                }

                if !isEnabled {
                    guard await confirmedDisableOfProvider(
                        id: candidate.id,
                        name: candidate.name
                    ) else {
                        return .failure(KeyPathError.configuration(.validationFailed(errors: ["Disabling \(candidate.name) was declined."])))
                    }
                }

                // Ensure home row mods config exists if this is a home row mods collection.
                if candidate.displayStyle == .homeRowMods,
                   case .homeRowMods = candidate.configuration
                {
                    // Already configured.
                } else if candidate.displayStyle == .homeRowMods {
                    candidate.configuration = .homeRowMods(HomeRowModsConfig())
                }

                var prerequisiteProviderIDs: [UUID] = []
                if isEnabled {
                    guard let confirmedProviderIDs = await confirmedPrerequisiteProviderIDs(
                        for: candidate,
                        operation: .enable,
                        disablingCollectionIDs: additionalCollectionIDsToDisable
                    ) else {
                        return .failure(KeyPathError.configuration(.validationFailed(errors: ["Required collections were not enabled; \(candidate.name) was left unchanged."])))
                    }
                    prerequisiteProviderIDs = confirmedProviderIDs

                    if let conflict = conflictInfo(
                        for: candidate,
                        ignoringCollectionIDs: additionalCollectionIDsToDisable
                    ) {
                        if autoResolveConflicts {
                            AppLogger.shared.log(
                                "🔄 [RuleCollections] Auto-resolving conflict: \(candidate.name) wins over \(conflict.displayName) on \(conflict.keys)"
                            )
                            await disableConflicting(conflict.source, regenerate: false)
                        } else {
                            let context = RuleConflictContext(
                                newRule: .collection(candidate),
                                existingRule: conflict.source,
                                conflictingKeys: conflict.keys
                            )

                            AppLogger.shared.log(
                                "⚠️ [RuleCollections] Conflict enabling \(candidate.name) vs \(conflict.displayName) on \(conflict.keys)"
                            )

                            guard let choice = await onConflictResolution?(context) else {
                                return .failure(KeyPathError.configuration(.validationFailed(errors: ["The mapping conflict was not resolved; \(candidate.name) was left unchanged."])))
                            }

                            switch choice {
                            case .keepNew:
                                await disableConflicting(conflict.source, regenerate: false)
                            case .keepExisting:
                                return .failure(KeyPathError.configuration(.validationFailed(errors: ["The existing mapping was kept; \(candidate.name) was not enabled."])))
                            }
                        }
                    }
                }

                for index in ruleCollections.indices where
                    additionalCollectionIDsToDisable.contains(ruleCollections[index].id)
                    && ruleCollections[index].id != candidate.id
                {
                    ruleCollections[index].isEnabled = false
                }

                applyPrerequisiteChangeInMemory(
                    candidate: candidate,
                    providerIDs: prerequisiteProviderIDs
                )

                AppLogger.shared.log("🔀 [RuleCollections] After toggle - collections: \(ruleCollections.map { "\($0.name) (enabled: \($0.isEnabled))" }.joined(separator: ", "))")

                // Special handling: If Leader Key collection is toggled off, reset all momentary activators to default (space)
                if id == RuleCollectionIdentifier.leaderKey {
                    if isEnabled {
                        let key = leaderKeyOutput(from: candidate) ?? leaderPreferenceSnapshot.value.key
                        syncLeaderKeyPreference(key: key, enabled: true)
                    } else {
                        syncLeaderKeyPreference(enabled: false)
                        applyLeaderKeyToMomentaryActivators("space")
                    }
                }

                let result = await commitRuleMutationResult(snapshot: snapshot, skipReload: skipReload, failureContext: candidate.name,
                                                            leaderPreferenceBefore: id == RuleCollectionIdentifier.leaderKey ? leaderPreferenceSnapshot : nil,
                                                            packRecord: packRecord, mutationPermit: permit)
                guard result.success else { return result }

                // Pre-cache icons for collections with app launches (e.g., Vim nav layer)
                if isEnabled, let collection = ruleCollections.first(where: { $0.id == id }) {
                    await warmLayerIconCache(for: collection)
                }
                return result
            }
        } catch {
            if !(error is CancellationError) { onError?(error.localizedDescription) }
            return .failure(error)
        }
    }

    /// Enable multiple collections in a single batch, regenerating config only once.
    /// Used when a mode switch (e.g., home row mods → layers) needs to enable several
    /// layer collections at once without 4 separate save/validate/reload cycles.
    func batchEnableCollections(ids: [UUID]) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            let catalog = RuleCollectionCatalog().defaultCollections()

            for id in ids {
                let catalogMatch = catalog.first { $0.id == id }
                let candidate = ruleCollections.first(where: { $0.id == id }) ?? catalogMatch

                if let index = ruleCollections.firstIndex(where: { $0.id == id }) {
                    ruleCollections[index].isEnabled = true
                } else if var newCollection = candidate {
                    newCollection.isEnabled = true
                    ruleCollections.append(newCollection)
                }
            }

            dedupeRuleCollectionsInPlace()
            refreshLayerIndicatorState()
            _ = await commitRuleMutation(snapshot: snapshot, mutationPermit: permit)
        }
    }

    /// Add or update a rule collection
    @discardableResult
    func addCollection(_ collection: RuleCollection, mutationPermit: ConfigurationOperationGate.Permit? = nil) async -> Bool {
        await withRuleMutation(using: mutationPermit, failure: false) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return false }

            if collection.isEnabled, let conflict = conflictInfo(for: collection) {
                // Show conflict resolution dialog
                let context = RuleConflictContext(
                    newRule: .collection(collection),
                    existingRule: conflict.source,
                    conflictingKeys: conflict.keys
                )

                AppLogger.shared.log(
                    "⚠️ [RuleCollections] Conflict adding \(collection.name) vs \(conflict.displayName) on \(conflict.keys)"
                )

                guard let choice = await onConflictResolution?(context) else {
                    // User cancelled - don't add
                    return false
                }

                switch choice {
                case .keepNew:
                    // Disable the conflicting rule, then proceed with adding this one
                    await disableConflicting(conflict.source, regenerate: false)
                case .keepExisting:
                    // User chose to keep the existing rule - don't add the new one
                    return false
                }
            }

            if let index = ruleCollections.firstIndex(where: { $0.id == collection.id }) {
                ruleCollections[index].isEnabled = true
                ruleCollections[index].summary = collection.summary
                ruleCollections[index].mappings = collection.mappings
                ruleCollections[index].category = collection.category
                ruleCollections[index].icon = collection.icon
            } else {
                ruleCollections.append(collection)
            }
            dedupeRuleCollectionsInPlace()
            refreshLayerIndicatorState()
            return await commitRuleMutation(snapshot: snapshot, mutationPermit: permit)
        }
    }

    /// Remove a rule collection by ID
    func removeCollection(id: UUID) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            ruleCollections.removeAll { $0.id == id }
            refreshLayerIndicatorState()
            if await commitRuleMutation(snapshot: snapshot, mutationPermit: permit) {
                AppLogger.shared.log("🗑️ [RuleCollections] Removed collection: \(id)")
            }
        }
    }

    /// Remove all collections and custom rules for a specific layer
    func removeLayer(_ layerName: String) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            let normalizedName = layerName.lowercased()

            // Remove collections targeting this layer
            let collectionCount = ruleCollections.count
            ruleCollections.removeAll { collection in
                collection.targetLayer.kanataName.lowercased() == normalizedName
            }
            let removedCollections = collectionCount - ruleCollections.count

            // Remove custom rules targeting this layer
            let ruleCount = customRules.count
            customRules.removeAll { rule in
                rule.targetLayer.kanataName.lowercased() == normalizedName
            }
            let removedRules = ruleCount - customRules.count

            refreshLayerIndicatorState()
            guard await commitRuleMutation(snapshot: snapshot, mutationPermit: permit) else { return }

            AppLogger.shared.log("🗑️ [RuleCollections] Removed layer '\(layerName)': \(removedCollections) collections, \(removedRules) rules")
        }
    }

    /// Create a new custom layer with Leader key activator
    func createLayer(_ name: String) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard !name.isEmpty else { return }
            guard await recoverAndSnapshotRuleState(mutationPermit: permit) != nil else { return }

            // Sanitize the layer name
            let sanitizedName = name.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }

            guard !sanitizedName.isEmpty else { return }

            // Check for duplicates by looking at existing collections' target layers
            let existingLayers = Set(ruleCollections.map { $0.targetLayer.kanataName.lowercased() })
            if existingLayers.contains(sanitizedName) {
                AppLogger.shared.warn("⚠️ [RuleCollections] Layer already exists: \(sanitizedName)")
                return
            }

            // Create a RuleCollection for this layer with Leader key activator
            // Activator: first letter of layer name, from nav layer (Leader → letter)
            let activatorKey = String(sanitizedName.prefix(1))
            let targetLayer = RuleCollectionLayer.custom(sanitizedName)

            let collection = RuleCollection(
                id: UUID(),
                name: sanitizedName.capitalized,
                summary: "Custom layer: \(sanitizedName)",
                category: .custom,
                mappings: [],
                isEnabled: true,
                icon: "square.stack.3d.up",
                tags: ["custom-layer"],
                targetLayer: targetLayer,
                momentaryActivator: MomentaryActivator(
                    input: activatorKey,
                    targetLayer: targetLayer,
                    sourceLayer: .navigation
                ),
                activationHint: "Leader → \(activatorKey.uppercased())",
                configuration: .list
            )

            guard await addCollection(collection, mutationPermit: permit) else { return }
            AppLogger.shared.log("📚 [RuleCollections] Created new layer: \(sanitizedName) (Leader → \(activatorKey.uppercased()))")
        }
    }

    /// Update a single-key picker collection's selected output and regenerate its mapping
    func updateCollectionOutput(id: UUID, output: String) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            guard var candidate = ruleCollections.first(where: { $0.id == id })
                ?? RuleCollectionCatalog().defaultCollections().first(where: { $0.id == id })
            else { return }
            let leaderSnapshot = snapshotLeaderPreference()
            candidate.configuration.updateSelectedOutput(output)
            candidate.isEnabled = true
            if let config = candidate.configuration.singleKeyPickerConfig, config.inputKey != "leader" {
                let description = config.presetOptions.first { $0.output == output }?.label ?? "Custom"
                let action: KeyAction = output.hasPrefix("(") ? .rawKanata(output) : .keystroke(key: output)
                candidate.mappings = [KeyMapping(input: config.inputKey, action: action, description: description)]
            }
            if let index = ruleCollections.firstIndex(where: { $0.id == id }) { ruleCollections[index] = candidate }
            else { ruleCollections.append(candidate) }
            if id == RuleCollectionIdentifier.leaderKey {
                applyLeaderKeyToMomentaryActivators(output)
                syncLeaderKeyPreference(key: output, enabled: true)
            }
            dedupeRuleCollectionsInPlace()
            refreshLayerIndicatorState()
            await commitRuleMutation(snapshot: snapshot, failureContext: candidate.name,
                                     leaderPreferenceBefore: id == RuleCollectionIdentifier.leaderKey ? leaderSnapshot : nil,
                                     mutationPermit: permit)
        }
    }

    /// Update a tap-hold picker collection's tap output
    func updateCollectionTapOutput(id: UUID, tapOutput: String) async {
        _ = await updateCollectionSettings(id: id) { rule in
            rule.configuration.updateSelectedTapOutput(tapOutput)
        }
    }

    /// Update a tap-hold picker collection's hold output
    func updateCollectionHoldOutput(id: UUID, holdOutput: String) async {
        _ = await updateCollectionSettings(id: id) { rule in
            rule.configuration.updateSelectedHoldOutput(holdOutput)
        }
    }

    /// Update a layer preset picker collection's selected preset
    func updateCollectionLayerPreset(id: UUID, presetId: String) async {
        _ = await updateCollectionSettings(id: id) { rule in
            rule.configuration.updateSelectedPreset(presetId)
        }
    }

    /// Update window snapping key convention (Standard vs Vim)
    func updateWindowKeyConvention(id: UUID, convention: WindowKeyConvention) async {
        _ = await updateCollectionSettings(id: id) { rule in
            rule.windowKeyConvention = convention
            rule.mappings = RuleCollectionCatalog.windowMappings(for: convention)
        }
    }

    /// Update function key mode (Media Keys vs Function Keys)
    func updateFunctionKeyMode(id: UUID, mode: FunctionKeyMode) async {
        _ = await updateCollectionSettings(id: id) { rule in
            rule.functionKeyMode = mode
            rule.mappings = RuleCollectionCatalog.functionKeyMappings(for: mode)
        }
    }

    /// Update home row mods configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateHomeRowModsConfig(id: UUID, config: HomeRowModsConfig) async -> Bool {
        await withRuleMutation(failure: false) { [self] permit in
            guard await recoverAndSnapshotRuleState(mutationPermit: permit) != nil else { return false }
            guard var candidate = ruleCollections.first(where: { $0.id == id })
                ?? RuleCollectionCatalog().defaultCollections().first(where: { $0.id == id })
            else {
                return false
            }

            let wasNewlyEnabled = !candidate.isEnabled
            candidate.configuration.updateHomeRowModsConfig(config)
            candidate.isEnabled = true

            let appliedProviderIDs = await applyProposedCollectionWithPrerequisites(
                candidate,
                mutationPermit: permit
            )
            return appliedProviderIDs != nil && wasNewlyEnabled
        }
    }

    /// Update home row layer toggles configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateHomeRowLayerTogglesConfig(id: UUID, config: HomeRowLayerTogglesConfig) async -> Bool {
        await withRuleMutation(failure: false) { [self] permit in
            guard await recoverAndSnapshotRuleState(mutationPermit: permit) != nil else { return false }
            guard var candidate = ruleCollections.first(where: { $0.id == id })
                ?? RuleCollectionCatalog().defaultCollections().first(where: { $0.id == id })
            else {
                return false
            }

            let wasNewlyEnabled = !candidate.isEnabled
            candidate.configuration.updateHomeRowLayerTogglesConfig(config)
            candidate.isEnabled = true

            let appliedProviderIDs = await applyProposedCollectionWithPrerequisites(
                candidate,
                mutationPermit: permit
            )
            return appliedProviderIDs != nil && wasNewlyEnabled
        }
    }

    /// Update chord groups configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateChordGroupsConfig(id: UUID, config: ChordGroupsConfig) async -> Bool {
        await updateCollectionSettings(id: id) { rule in
            rule.configuration.updateChordGroupsConfig(config)
        }
    }

    /// Update sequences configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateSequencesConfig(id: UUID, config: SequencesConfig) async -> Bool {
        await updateCollectionSettings(id: id) { rule in
            rule.configuration.updateSequencesConfig(config)
        }
    }

    /// Update launcher grid configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateLauncherConfig(id: UUID, config: LauncherGridConfig) async -> Bool {
        await withRuleMutation(failure: false) { [self] permit in
            guard await recoverAndSnapshotRuleState(mutationPermit: permit) != nil else { return false }
            guard let candidate = ruleCollections.first(where: { $0.id == id })
                ?? RuleCollectionCatalog().defaultCollections().first(where: { $0.id == id })
            else {
                return false
            }

            let wasNewlyEnabled = !candidate.isEnabled
            let applied = await applyLauncherConfig(id: id, config: config, mutationPermit: permit)
            return applied && wasNewlyEnabled
        }
    }

    /// Applies and persists launcher configuration, optionally leaving the
    /// runtime reload to a typed caller.
    /// - Returns: `true` only when the proposed configuration was saved.
    @discardableResult
    func applyLauncherConfig(
        id: UUID,
        config: LauncherGridConfig,
        skipReload: Bool = false,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async -> Bool {
        await withRuleMutation(using: mutationPermit, failure: false) { [self] permit in
            guard await recoverAndSnapshotRuleState(mutationPermit: permit) != nil else { return false }
            guard var candidate = ruleCollections.first(where: { $0.id == id })
                ?? RuleCollectionCatalog().defaultCollections().first(where: { $0.id == id })
            else {
                return false
            }
            guard case .launcherGrid = candidate.configuration else {
                return false
            }

            candidate.configuration.updateLauncherGridConfig(config)
            candidate.isEnabled = true

            let appliedProviderIDs = await applyProposedCollectionWithPrerequisites(
                candidate,
                skipReload: skipReload,
                mutationPermit: permit
            )
            guard appliedProviderIDs != nil else {
                return false
            }

            await warmLauncherIconCache(for: config)
            return true
        }
    }

    /// Update auto shift symbols configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateAutoShiftSymbolsConfig(id: UUID, config: AutoShiftSymbolsConfig) async -> Bool {
        await updateCollectionSettings(id: id, enableExisting: false) { rule in
            rule.configuration.updateAutoShiftSymbolsConfig(config)
        }
    }

    /// Update key repeat control configuration
    /// - Returns: `true` if the collection was newly enabled (was disabled before this call)
    @discardableResult
    func updateKeyRepeatControlConfig(id: UUID, config: KeyRepeatControlConfig) async -> Bool {
        await updateCollectionSettings(id: id, enableExisting: false) { rule in
            rule.configuration.updateKeyRepeatControlConfig(config)
        }
    }

    /// Update window snapping activation mode
    /// - Returns: name of auto-enabled dependency, or nil
    func updateWindowSnappingActivationMode(id: UUID, mode: WindowSnappingActivationMode) async -> String? {
        await withRuleMutation(failure: nil) { [self] permit in
            guard await recoverAndSnapshotRuleState(mutationPermit: permit) != nil else { return nil }
            guard var candidate = ruleCollections.first(where: { $0.id == id }) else {
                return nil
            }

            candidate.windowSnappingActivationMode = mode
            candidate.momentaryActivator = Self.momentaryActivatorForWindowSnapping(mode)
            candidate.activationHint = Self.activationHintForWindowSnapping(mode)

            guard let enabledProviderIDs = await applyProposedCollectionWithPrerequisites(
                candidate,
                nonInteractiveChoice: .enableRequiredProvidersAndApply,
                mutationPermit: permit
            ) else {
                return nil
            }

            return enabledProviderIDs.compactMap { providerID in
                ruleCollections.first(where: { $0.id == providerID })?.name
            }.first
        }
    }

    private static func momentaryActivatorForWindowSnapping(_ mode: WindowSnappingActivationMode) -> MomentaryActivator {
        switch mode {
        case .leader:
            MomentaryActivator(input: "w", targetLayer: .custom("window"), sourceLayer: .navigation)
        case .quickLauncher:
            MomentaryActivator(input: "w", targetLayer: .custom("window"), sourceLayer: .custom("launcher"))
        }
    }

    private static func activationHintForWindowSnapping(_ mode: WindowSnappingActivationMode) -> String {
        switch mode {
        case .leader: "Leader → w → action key"
        case .quickLauncher: "Hyper + w → action key"
        }
    }

    /// Pre-cache icons for launcher mappings (called when config changes)
    func warmLauncherIconCache(for config: LauncherGridConfig) async {
        let enabledMappings = config.mappings.filter(\.isEnabled)
        AppLogger.shared.debug("🖼️ [RuleCollections] Warming cache for \(enabledMappings.count) launcher mappings")

        for mapping in enabledMappings {
            await IconResolverService.shared.preloadIcon(for: mapping.action)
        }
    }

    /// Pre-cache icons for layer-based app launches (e.g., Vim nav mode apps)
    func warmLayerIconCache(for collection: RuleCollection) async {
        await IconResolverService.shared.preloadLayerIcons(from: [collection])
    }

    /// Update the leader key for all collections that use momentary activation
    func updateLeaderKey(_ newKey: String, mutationPermit: ConfigurationOperationGate.Permit? = nil) async {
        await withRuleMutation(using: mutationPermit, failure: ()) { [self] permit in
            AppLogger.shared.log("🔑 [RuleCollections] Updating leader key to '\(newKey)'")
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            let leaderPreferenceSnapshot = snapshotLeaderPreference()

            applyLeaderKeyToMomentaryActivators(newKey)
            syncLeaderKeyPreference(key: newKey, enabled: true)
            dedupeRuleCollectionsInPlace()
            refreshLayerIndicatorState()
            await commitRuleMutation(snapshot: snapshot, failureContext: "Leader Key",
                                     leaderPreferenceBefore: leaderPreferenceSnapshot, mutationPermit: permit)
        }
    }

    private func applyLeaderKeyToMomentaryActivators(_ newKey: String) {
        // Update all collections that have a momentary activator
        for index in ruleCollections.indices {
            if let oldActivator = ruleCollections[index].momentaryActivator {
                ruleCollections[index].momentaryActivator = MomentaryActivator(
                    input: newKey,
                    targetLayer: oldActivator.targetLayer,
                    sourceLayer: oldActivator.sourceLayer
                )
                AppLogger.shared.log(
                    "🔑 [RuleCollections] Updated '\(ruleCollections[index].name)' activator to '\(newKey)'"
                )
            }
        }
    }

    /// Rewrite the input of only the *leader* activators — those that transition from the
    /// base layer into the leader's target layer (e.g. base → nav). Unlike
    /// `applyLeaderKeyToMomentaryActivators`, this deliberately leaves unrelated base-layer
    /// activators alone (e.g. Home Row Arrows on "f", Quick Launcher on "hyper") and
    /// chained sub-layer activators (sourceLayer != .base, e.g. nav → window), which have
    /// their own activation keys. Used by the passive reconcile path, which fires on every
    /// headless load where the preference diverges — the broad rewrite would stomp those
    /// unrelated features (and, for Quick Launcher's "hyper", collide two base-layer
    /// bindings onto the same key). See issue #889.
    private func applyLeaderKeyToLeaderActivators(_ newKey: String, targetLayer: RuleCollectionLayer) {
        // Shared pure transform (same one the CLI apply path uses) keeps the two reconcile
        // sites in agreement. Logging stays here for the in-process load-path trace.
        for index in ruleCollections.indices
            where ruleCollections[index].momentaryActivator.map({
                $0.sourceLayer == .base && $0.targetLayer == targetLayer
            }) == true
        {
            AppLogger.shared.log(
                "🔑 [RuleCollections] Reconciled leader activator on '\(ruleCollections[index].name)' to '\(newKey)'"
            )
        }
        ruleCollections = LeaderKeyPreference.reconcileLeaderActivators(
            in: ruleCollections,
            key: newKey,
            targetLayer: targetLayer
        )
    }

    private func leaderKeyOutput(from collection: RuleCollection) -> String? {
        guard let config = collection.configuration.singleKeyPickerConfig else { return nil }
        return config.selectedOutput ?? config.presetOptions.first?.output
    }

    private func syncLeaderKeyPreference(key: String? = nil, enabled: Bool, persistImmediately: Bool = false) {
        var preference = preferencesService.leaderKeyPreference
        if let key {
            preference.key = key
        }
        preference.enabled = enabled
        if persistImmediately { preferencesService.leaderKeyPreference = preference }
        else { pendingLeaderKeyPreference = preference }
    }

    /// Reconcile the system `leaderKeyPreference` (and the base→nav leader activator) from
    /// the enabled Leader Key collection's `selectedOutput`.
    ///
    /// The in-app picker routes through `updateLeaderKey`, which keeps both stores in
    /// sync. Headless mutations — direct JSON edits and import/restore — change
    /// `selectedOutput` without touching `leaderKeyPreference`, so config generation
    /// (which derives the leader key from the preference) would silently ignore them.
    /// Calling this on the in-process load paths (`bootstrap`/`replaceCollections`)
    /// reconciles the preference so a subsequent app/daemon config regen honors the
    /// edited collection. See issue #889.
    ///
    /// The standalone `keypath-cli config apply` path runs the equivalent reconcile in
    /// `ConfigFacade.applyConfiguration` (it never constructs a `RuleCollectionsManager`),
    /// sharing the pure rule in `LeaderKeyPreference.reconciled(from:current:)` /
    /// `.reconcileLeaderActivators(in:key:targetLayer:)`. Unifying config *generation* on the
    /// collection as the single source of truth is still deferred to #865/#888.
    ///
    /// Only an *explicit* `selectedOutput` reconciles — a nil `selectedOutput` means the
    /// collection expresses no opinion, so a leader key configured via the system
    /// preference path is left untouched (no fallback to the first preset).
    ///
    /// Scope (see #889): this only reconciles the enabled-with-explicit-output case. A
    /// headless edit that *disables* a previously-reconciled collection leaves
    /// `leaderKeyPreference` stale (still enabled with the old key). Forcing it disabled
    /// here would clobber a leader configured via the system-preference path while the
    /// collection is off, so full bidirectional reconciliation is deferred to the
    /// single-source-of-truth work in #865/#888.
    /// - Returns: `true` if it staged a preference/activator change for the caller's rule
    ///   transaction, `false` if it was a no-op.
    @discardableResult
    func reconcileLeaderKeyFromCollection(persistImmediately: Bool = false) -> Bool {
        let current = pendingLeaderKeyPreference ?? preferencesService.leaderKeyPreference
        // Shared, pure reconcile rule — same statement the CLI apply path uses
        // (ConfigFacade), so all headless paths agree. See LeaderKeyPreference.reconciled.
        guard let reconciled = LeaderKeyPreference.reconciled(from: ruleCollections, current: current) else {
            return false
        }

        AppLogger.shared.log(
            "🔑 [RuleCollections] Reconciling leader key from collection selectedOutput: '\(reconciled.key)' (was '\(current.key)', enabled=\(current.enabled))"
        )
        applyLeaderKeyToLeaderActivators(reconciled.key, targetLayer: current.targetLayer)
        syncLeaderKeyPreference(key: reconciled.key, enabled: true, persistImmediately: persistImmediately)
        return true
    }

    /// Save or update a custom rule
    /// - Parameters:
    ///   - autoResolveConflicts: When true, automatically wins over conflicting rules without prompting.
    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false, autoResolveConflicts: Bool = false, mutationPermit: ConfigurationOperationGate.Permit? = nil) async -> Bool {
        await withRuleMutation(using: mutationPermit, failure: false) { [self] permit in
            AppLogger.shared.log("💾 [CustomRules] saveCustomRule called: id=\(rule.id), input='\(rule.input)', action='\(rule.action.displayName)'")
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return false }

            guard await updateCustomRuleInMemory(rule, autoResolveConflicts: autoResolveConflicts, mutationPermit: permit) else { return false }

            return await commitRuleMutation(snapshot: snapshot, skipReload: skipReload, mutationPermit: permit)
        }
    }

    /// Prepare the intended rule state under admission. Persistence belongs to the
    /// caller so the mapper can retain its transaction through runtime recovery.
    func updateCustomRuleInMemory(_ rule: CustomRule, autoResolveConflicts: Bool = false,
                                  mutationPermit: ConfigurationOperationGate.Permit) async -> Bool
    {
        await withRuleMutation(using: mutationPermit, failure: false) { [self] _ in
            if rule.isEnabled,
               let conflict = conflictInfo(for: rule)
            {
                if autoResolveConflicts {
                    AppLogger.shared.log(
                        "🔄 [CustomRules] Auto-resolving conflict: \(rule.displayTitle) wins over \(conflict.displayName) on \(conflict.keys)"
                    )
                    await disableConflicting(conflict.source, regenerate: false)
                } else {
                    let context = RuleConflictContext(
                        newRule: .customRule(rule),
                        existingRule: conflict.source,
                        conflictingKeys: conflict.keys
                    )

                    AppLogger.shared.log(
                        "⚠️ [CustomRules] Conflict saving \(rule.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
                    )

                    guard let choice = await onConflictResolution?(context) else {
                        return false
                    }

                    switch choice {
                    case .keepNew:
                        await disableConflicting(conflict.source, regenerate: false)
                    case .keepExisting:
                        return false
                    }
                }
            }

            let existingIndex = customRules.firstIndex(where: { $0.id == rule.id })

            if let index = existingIndex {
                AppLogger.shared.log("💾 [CustomRules] Updating existing rule at index \(index)")
                customRules[index] = rule
            } else {
                AppLogger.shared.log("💾 [CustomRules] Adding new rule (count will be \(customRules.count + 1))")
                customRules.append(rule)
            }

            return true
        }
    }

    /// Toggle a custom rule on/off
    func toggleCustomRule(id: UUID, isEnabled: Bool) async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            guard let existing = customRules.first(where: { $0.id == id }) else { return }

            if !isEnabled {
                guard await confirmedDisableOfProvider(
                    id: existing.id,
                    name: existing.displayTitle
                ) else {
                    return
                }
            }

            if isEnabled,
               let conflict = conflictInfo(for: existing)
            {
                // Show conflict resolution dialog
                let context = RuleConflictContext(
                    newRule: .customRule(existing),
                    existingRule: conflict.source,
                    conflictingKeys: conflict.keys
                )

                AppLogger.shared.log(
                    "⚠️ [CustomRules] Conflict enabling \(existing.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
                )

                guard let choice = await onConflictResolution?(context) else {
                    // User cancelled - don't enable
                    return
                }

                switch choice {
                case .keepNew:
                    // Disable the conflicting rule, then proceed with enabling this one
                    await disableConflicting(conflict.source, regenerate: false)
                case .keepExisting:
                    // User chose to keep the existing rule - don't enable the new one
                    return
                }
            }

            if let index = customRules.firstIndex(where: { $0.id == id }) {
                customRules[index].isEnabled = isEnabled
            }
            _ = await commitRuleMutation(snapshot: snapshot, mutationPermit: permit)
        }
    }

    /// Remove a custom rule
    func removeCustomRule(id: UUID, mutationPermit: ConfigurationOperationGate.Permit? = nil) async {
        await withRuleMutation(using: mutationPermit, failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            let beforeCount = customRules.count
            AppLogger.shared.log("🗑️ [CustomRules] removeCustomRule called: id=\(id), beforeCount=\(beforeCount)")
            customRules.removeAll { $0.id == id }
            let afterCount = customRules.count
            AppLogger.shared.log("🗑️ [CustomRules] After removal: afterCount=\(afterCount), removed=\(beforeCount - afterCount)")
            _ = await commitRuleMutation(snapshot: snapshot, mutationPermit: permit)
        }
    }

    /// Clear all custom rules (without affecting rule collections)
    func clearAllCustomRules() async {
        await withRuleMutation(failure: ()) { [self] permit in
            guard let snapshot = await recoverAndSnapshotRuleState(mutationPermit: permit) else { return }
            let count = customRules.count
            AppLogger.shared.log("🧹 [CustomRules] Clearing all \(count) custom rules")
            customRules.removeAll()
            if await commitRuleMutation(snapshot: snapshot, mutationPermit: permit) {
                AppLogger.shared.log("✅ [CustomRules] All custom rules cleared")
            }
        }
    }

    /// Create or update a custom rule for the given input/output
    func makeCustomRule(input: String, output: String) -> CustomRule {
        let action: KeyAction = output.hasPrefix("(") ? .rawKanata(output) : .keystroke(key: output)
        if let existing = customRules.first(where: {
            $0.input.caseInsensitiveCompare(input) == .orderedSame
        }) {
            return CustomRule(
                id: existing.id,
                title: existing.title,
                input: input,
                action: action,
                shiftedOutput: existing.shiftedOutput,
                isEnabled: true,
                notes: existing.notes,
                createdAt: existing.createdAt,
                deviceOverrides: existing.deviceOverrides
            )
        } else {
            return CustomRule(input: input, action: action)
        }
    }

    /// Get existing custom rule for the given input key, if any
    func getCustomRule(forInput input: String) -> CustomRule? {
        customRules.first { $0.input.caseInsensitiveCompare(input) == .orderedSame }
    }
}
