import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
    // MARK: - Public API

    /// Get all enabled mappings from collections and custom rules
    func enabledMappings() -> [KeyMapping] {
        ruleCollections.enabledMappings() + customRules.enabledMappings()
    }

    /// Replace all rule collections
    func replaceCollections(_ collections: [RuleCollection]) async {
        ruleCollections = RuleCollectionDeduplicator.dedupe(collections)
        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Toggle a rule collection on/off
    func toggleCollection(id: UUID, isEnabled: Bool) async {
        AppLogger.shared.log("🔀 [RuleCollections] toggleCollection called: id=\(id), isEnabled=\(isEnabled)")
        let catalogMatch = RuleCollectionCatalog().defaultCollections().first { $0.id == id }
        AppLogger.shared.log("🔀 [RuleCollections] catalogMatch=\(catalogMatch?.name ?? "nil")")
        let candidate = ruleCollections.first(where: { $0.id == id }) ?? catalogMatch

        if var candidate, isEnabled {
            candidate.isEnabled = true
            if let conflict = conflictInfo(for: candidate) {
                // Show conflict resolution dialog
                let context = RuleConflictContext(
                    newRule: .collection(candidate),
                    existingRule: conflict.source,
                    conflictingKeys: conflict.keys
                )

                AppLogger.shared.log(
                    "⚠️ [RuleCollections] Conflict enabling \(candidate.name) vs \(conflict.displayName) on \(conflict.keys)"
                )

                guard let choice = await onConflictResolution?(context) else {
                    // User cancelled - don't enable
                    return
                }

                switch choice {
                case .keepNew:
                    // Disable the conflicting rule, then proceed with enabling this one
                    await disableConflicting(conflict.source)
                case .keepExisting:
                    // User chose to keep the existing rule - don't enable the new one
                    return
                }
            }
        }

        guard let resolvedCandidate = candidate else { return }

        if let index = ruleCollections.firstIndex(where: { $0.id == id }) {
            ruleCollections[index].isEnabled = isEnabled
            // Ensure home row mods config exists if this is a home row mods collection
            if case .homeRowMods = ruleCollections[index].configuration {
                // Already has config, nothing to do
            } else if resolvedCandidate.displayStyle == .homeRowMods {
                ruleCollections[index].configuration = .homeRowMods(HomeRowModsConfig())
            }
        } else {
            var newCollection = resolvedCandidate
            newCollection.isEnabled = isEnabled
            // Ensure home row mods config exists if this is a home row mods collection
            if newCollection.displayStyle == .homeRowMods {
                if case .homeRowMods = newCollection.configuration {
                    // Already has config
                } else {
                    newCollection.configuration = .homeRowMods(HomeRowModsConfig())
                }
            }
            ruleCollections.append(newCollection)
        }

        dedupeRuleCollectionsInPlace()

        AppLogger.shared.log("🔀 [RuleCollections] After toggle - collections: \(ruleCollections.map { "\($0.name) (enabled: \($0.isEnabled))" }.joined(separator: ", "))")

        // Special handling: If Leader Key collection is toggled off, reset all momentary activators to default (space)
        if id == RuleCollectionIdentifier.leaderKey, !isEnabled {
            await updateLeaderKey("space")
            return // updateLeaderKey already calls regenerateConfigFromCollections
        }

        refreshLayerIndicatorState()
        AppLogger.shared.log("🔀 [RuleCollections] Calling regenerateConfigFromCollections...")
        await regenerateConfigFromCollections()

        // Pre-cache icons for collections with app launches (e.g., Vim nav layer)
        if isEnabled, let collection = ruleCollections.first(where: { $0.id == id }) {
            await warmLayerIconCache(for: collection)
        }
    }

    /// Add or update a rule collection
    func addCollection(_ collection: RuleCollection) async {
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
                return
            }

            switch choice {
            case .keepNew:
                // Disable the conflicting rule, then proceed with adding this one
                await disableConflicting(conflict.source)
            case .keepExisting:
                // User chose to keep the existing rule - don't add the new one
                return
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
        await regenerateConfigFromCollections()
    }

    /// Remove a rule collection by ID
    func removeCollection(id: UUID) async {
        ruleCollections.removeAll { $0.id == id }
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
        AppLogger.shared.log("🗑️ [RuleCollections] Removed collection: \(id)")
    }

    /// Remove all collections and custom rules for a specific layer
    func removeLayer(_ layerName: String) async {
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

        // Persist custom rules to disk
        do {
            try await customRulesStore.saveRules(customRules)
        } catch {
            AppLogger.shared.error("❌ [RuleCollections] Failed to persist custom rules after layer removal: \(error)")
        }

        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()

        AppLogger.shared.log("🗑️ [RuleCollections] Removed layer '\(layerName)': \(removedCollections) collections, \(removedRules) rules")
    }

    /// Create a new custom layer with Leader key activator
    func createLayer(_ name: String) async {
        guard !name.isEmpty else { return }

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

        await addCollection(collection)
        AppLogger.shared.log("📚 [RuleCollections] Created new layer: \(sanitizedName) (Leader → \(activatorKey.uppercased()))")
    }

    /// Update a single-key picker collection's selected output and regenerate its mapping
    func updateCollectionOutput(id: UUID, output: String) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateSelectedOutput(output)
                catalogCollection.isEnabled = true
                // Update the mapping based on selected output
                if let config = catalogCollection.configuration.singleKeyPickerConfig {
                    let description = config.presetOptions.first { $0.output == output }?.label ?? "Custom"
                    catalogCollection.mappings = [KeyMapping(input: config.inputKey, output: output, description: description)]
                }
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateSelectedOutput(output)
        ruleCollections[index].isEnabled = true

        // Update the mapping based on selected output (skip for Leader Key which has no mappings)
        if let config = ruleCollections[index].configuration.singleKeyPickerConfig,
           config.inputKey != "leader" {
            let description = config.presetOptions.first { $0.output == output }?.label ?? "Custom"
            ruleCollections[index].mappings = [KeyMapping(input: config.inputKey, output: output, description: description)]
        }

        dedupeRuleCollectionsInPlace()

        // Special handling: If this is the Leader Key collection, update all momentary activators
        if id == RuleCollectionIdentifier.leaderKey {
            await updateLeaderKey(output)
            return
        }

        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update a tap-hold picker collection's tap output
    func updateCollectionTapOutput(id: UUID, tapOutput: String) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateSelectedTapOutput(tapOutput)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateSelectedTapOutput(tapOutput)
        ruleCollections[index].isEnabled = true
        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update a tap-hold picker collection's hold output
    func updateCollectionHoldOutput(id: UUID, holdOutput: String) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateSelectedHoldOutput(holdOutput)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateSelectedHoldOutput(holdOutput)
        ruleCollections[index].isEnabled = true
        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update a layer preset picker collection's selected preset
    func updateCollectionLayerPreset(id: UUID, presetId: String) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateSelectedPreset(presetId)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateSelectedPreset(presetId)
        ruleCollections[index].isEnabled = true
        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update window snapping key convention (Standard vs Vim)
    func updateWindowKeyConvention(id: UUID, convention: WindowKeyConvention) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.windowKeyConvention = convention
                catalogCollection.mappings = RuleCollectionCatalog.windowMappings(for: convention)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].windowKeyConvention = convention
        ruleCollections[index].mappings = RuleCollectionCatalog.windowMappings(for: convention)
        ruleCollections[index].isEnabled = true
        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update function key mode (Media Keys vs Function Keys)
    func updateFunctionKeyMode(id: UUID, mode: FunctionKeyMode) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.functionKeyMode = mode
                catalogCollection.mappings = RuleCollectionCatalog.functionKeyMappings(for: mode)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].functionKeyMode = mode
        ruleCollections[index].mappings = RuleCollectionCatalog.functionKeyMappings(for: mode)
        ruleCollections[index].isEnabled = true
        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update home row mods configuration
    func updateHomeRowModsConfig(id: UUID, config: HomeRowModsConfig) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateHomeRowModsConfig(config)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateHomeRowModsConfig(config)
        ruleCollections[index].isEnabled = true

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update home row layer toggles configuration
    func updateHomeRowLayerTogglesConfig(id: UUID, config: HomeRowLayerTogglesConfig) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateHomeRowLayerTogglesConfig(config)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateHomeRowLayerTogglesConfig(config)
        ruleCollections[index].isEnabled = true

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update chord groups configuration
    func updateChordGroupsConfig(id: UUID, config: ChordGroupsConfig) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateChordGroupsConfig(config)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateChordGroupsConfig(config)
        ruleCollections[index].isEnabled = true

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update sequences configuration
    func updateSequencesConfig(id: UUID, config: SequencesConfig) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateSequencesConfig(config)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].configuration.updateSequencesConfig(config)
        ruleCollections[index].isEnabled = true

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update launcher grid configuration
    func updateLauncherConfig(id: UUID, config: LauncherGridConfig) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.configuration.updateLauncherGridConfig(config)
                catalogCollection.isEnabled = true
                ruleCollections.append(catalogCollection)
                dedupeRuleCollectionsInPlace()
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
                // Cache warm new launcher icons
                await warmLauncherIconCache(for: config)
            }
            return
        }

        ruleCollections[index].configuration.updateLauncherGridConfig(config)
        ruleCollections[index].isEnabled = true

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()

        // Cache warm new launcher icons
        await warmLauncherIconCache(for: config)
    }

    /// Pre-cache icons for launcher mappings (called when config changes)
    func warmLauncherIconCache(for config: LauncherGridConfig) async {
        let enabledMappings = config.mappings.filter(\.isEnabled)
        AppLogger.shared.debug("🖼️ [RuleCollections] Warming cache for \(enabledMappings.count) launcher mappings")

        for mapping in enabledMappings {
            await IconResolverService.shared.preloadIcon(for: mapping.target)
        }
    }

    /// Pre-cache icons for layer-based app launches (e.g., Vim nav mode apps)
    func warmLayerIconCache(for collection: RuleCollection) async {
        await IconResolverService.shared.preloadLayerIcons(from: [collection])
    }

    /// Update the leader key for all collections that use momentary activation
    func updateLeaderKey(_ newKey: String) async {
        AppLogger.shared.log("🔑 [RuleCollections] Updating leader key to '\(newKey)'")

        // Update all collections that have a momentary activator
        for index in ruleCollections.indices {
            if ruleCollections[index].momentaryActivator != nil {
                let oldActivator = ruleCollections[index].momentaryActivator!
                ruleCollections[index].momentaryActivator = MomentaryActivator(
                    input: newKey,
                    targetLayer: oldActivator.targetLayer
                )
                AppLogger.shared.log(
                    "🔑 [RuleCollections] Updated '\(ruleCollections[index].name)' activator to '\(newKey)'"
                )
            }
        }

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Save or update a custom rule
    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false) async -> Bool {
        AppLogger.shared.log("💾 [CustomRules] saveCustomRule called: id=\(rule.id), input='\(rule.input)', output='\(rule.output)'")

        if rule.isEnabled,
           let conflict = conflictInfo(for: rule) {
            // Show conflict resolution dialog
            let context = RuleConflictContext(
                newRule: .customRule(rule),
                existingRule: conflict.source,
                conflictingKeys: conflict.keys
            )

            AppLogger.shared.log(
                "⚠️ [CustomRules] Conflict saving \(rule.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
            )

            guard let choice = await onConflictResolution?(context) else {
                // User cancelled - don't save
                return false
            }

            switch choice {
            case .keepNew:
                // Disable the conflicting rule, then proceed with saving this one
                await disableConflicting(conflict.source)
            case .keepExisting:
                // User chose to keep the existing rule - don't save the new one
                return false
            }
        }

        // Track state before change for potential rollback
        let existingIndex = customRules.firstIndex(where: { $0.id == rule.id })
        let previousRule = existingIndex.map { customRules[$0] }

        if let index = existingIndex {
            AppLogger.shared.log("💾 [CustomRules] Updating existing rule at index \(index)")
            customRules[index] = rule
        } else {
            AppLogger.shared.log("💾 [CustomRules] Adding new rule (count will be \(customRules.count + 1))")
            customRules.append(rule)
        }

        let success = await regenerateConfigFromCollections(skipReload: skipReload)

        if success {
            AppLogger.shared.log("💾 [CustomRules] Save complete, customRules.count = \(customRules.count)")
        } else {
            // Rollback: restore previous state on failure
            AppLogger.shared.log("💾 [CustomRules] Save failed - rolling back changes")
            if let previous = previousRule, let index = existingIndex {
                customRules[index] = previous
            } else {
                customRules.removeAll { $0.id == rule.id }
            }
            AppLogger.shared.log("💾 [CustomRules] Rollback complete, customRules.count = \(customRules.count)")
        }

        return success
    }

    /// Toggle a custom rule on/off
    func toggleCustomRule(id: UUID, isEnabled: Bool) async {
        guard let existing = customRules.first(where: { $0.id == id }) else { return }

        if isEnabled,
           let conflict = conflictInfo(for: existing) {
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
                await disableConflicting(conflict.source)
            case .keepExisting:
                // User chose to keep the existing rule - don't enable the new one
                return
            }
        }

        if let index = customRules.firstIndex(where: { $0.id == id }) {
            customRules[index].isEnabled = isEnabled
        }
        await regenerateConfigFromCollections()
    }

    /// Remove a custom rule
    func removeCustomRule(id: UUID) async {
        let beforeCount = customRules.count
        AppLogger.shared.log("🗑️ [CustomRules] removeCustomRule called: id=\(id), beforeCount=\(beforeCount)")
        customRules.removeAll { $0.id == id }
        let afterCount = customRules.count
        AppLogger.shared.log("🗑️ [CustomRules] After removal: afterCount=\(afterCount), removed=\(beforeCount - afterCount)")
        await regenerateConfigFromCollections()
    }

    /// Clear all custom rules (without affecting rule collections)
    func clearAllCustomRules() async {
        let count = customRules.count
        AppLogger.shared.log("🧹 [CustomRules] Clearing all \(count) custom rules")
        customRules.removeAll()
        await regenerateConfigFromCollections()
        AppLogger.shared.log("✅ [CustomRules] All custom rules cleared")
    }

    /// Create or update a custom rule for the given input/output
    func makeCustomRule(input: String, output: String) -> CustomRule {
        if let existing = customRules.first(where: {
            $0.input.caseInsensitiveCompare(input) == .orderedSame
        }) {
            CustomRule(
                id: existing.id,
                title: existing.title,
                input: input,
                output: output,
                isEnabled: true,
                notes: existing.notes,
                createdAt: existing.createdAt
            )
        } else {
            CustomRule(input: input, output: output)
        }
    }

    /// Get existing custom rule for the given input key, if any
    func getCustomRule(forInput input: String) -> CustomRule? {
        customRules.first { $0.input.caseInsensitiveCompare(input) == .orderedSame }
    }
}
