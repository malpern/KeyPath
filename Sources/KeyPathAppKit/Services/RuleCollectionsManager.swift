import Foundation
import KeyPathCore
import KeyPathPermissions

// MARK: - Rule Conflict Detection

/// Information about a conflict between rule sources
@MainActor
struct RuleConflictInfo {
    enum Source {
        case collection(RuleCollection)
        case customRule(CustomRule)

        var name: String {
            switch self {
            case let .collection(collection): collection.name
            case let .customRule(rule): rule.displayTitle
            }
        }
    }

    let source: Source
    let keys: [String]

    var displayName: String { source.name }
}

// MARK: - RuleCollectionsManager

/// Manages rule collections and custom rules with conflict detection.
///
/// Extracted from RuntimeCoordinator to reduce its size and improve
/// separation of concerns. This manager handles:
/// - Loading/saving rule collections and custom rules
/// - Conflict detection between rules
/// - Layer state management
/// - Configuration regeneration on changes
@MainActor
final class RuleCollectionsManager {
    // MARK: - State

    private(set) var ruleCollections: [RuleCollection] = []
    private(set) var customRules: [CustomRule] = []
    private(set) var currentLayerName: String = RuleCollectionLayer.base.displayName

    /// Active keymap layout ID (e.g., "colemak-dh", "dvorak")
    /// When set to non-QWERTY, generates remapping rules in the config
    private(set) var activeKeymapId: String = LogicalKeymap.defaultId

    /// Whether to include punctuation in keymap remapping
    private(set) var keymapIncludesPunctuation: Bool = false

    // MARK: - Dependencies

    private let ruleCollectionStore: RuleCollectionStore
    private let customRulesStore: CustomRulesStore
    private let configurationService: ConfigurationService
    private let eventListener: KanataEventListener

    /// Callback invoked when rules change (for config regeneration)
    var onRulesChanged: (() async -> Void)?

    /// Callback invoked when layer changes (for UI updates)
    var onLayerChanged: ((String) -> Void)?

    /// Callback invoked when a keypath:// action URI is received via push-msg
    var onActionURI: ((KeyPathActionURI) -> Void)?

    /// Callback invoked when an unknown (non-keypath://) message is received
    var onUnknownMessage: ((String) -> Void)?

    /// Callback for reporting errors
    var onError: ((String) -> Void)?

    /// Callback for reporting warnings (non-blocking)
    var onWarning: ((String) -> Void)?

    /// Callback for interactive conflict resolution
    /// Returns the user's choice, or nil if cancelled
    var onConflictResolution: ((RuleConflictContext) async -> RuleConflictChoice?)?

    /// Callback to suppress file watcher before internal saves (prevents double-reload beep)
    var onBeforeSave: (() -> Void)?

    // MARK: - Initialization

    init(
        ruleCollectionStore: RuleCollectionStore = .shared,
        customRulesStore: CustomRulesStore = .shared,
        configurationService: ConfigurationService,
        eventListener: KanataEventListener = KanataEventListener()
    ) {
        self.ruleCollectionStore = ruleCollectionStore
        self.customRulesStore = customRulesStore
        self.configurationService = configurationService
        self.eventListener = eventListener
    }

    deinit {
        let listener = eventListener
        Task.detached(priority: .background) {
            await listener.stop()
        }
    }

    // MARK: - Bootstrap

    /// Load rule collections and custom rules from persistent storage
    func bootstrap() async {
        // Restore keymap state first (before loading collections)
        restoreKeymapState()

        async let storedCollectionsTask = ruleCollectionStore.loadCollections()
        async let storedCustomRulesTask = customRulesStore.loadRules()

        var storedCollections = await storedCollectionsTask
        var storedCustomRules = await storedCustomRulesTask

        // Migrate legacy custom mappings if needed
        if storedCustomRules.isEmpty,
           let customIndex = storedCollections.firstIndex(where: {
               $0.id == RuleCollectionIdentifier.customMappings
           })
        {
            let legacy = storedCollections.remove(at: customIndex)
            storedCustomRules = legacy.mappings.map { mapping in
                CustomRule(
                    id: mapping.id,
                    title: "",
                    input: mapping.input,
                    output: mapping.output,
                    isEnabled: legacy.isEnabled
                )
            }
            AppLogger.shared.log(
                "♻️ [RuleCollections] Migrated \(storedCustomRules.count) legacy custom mapping(s) into CustomRulesStore"
            )
            do {
                try await customRulesStore.saveRules(storedCustomRules)
            } catch {
                AppLogger.shared.log(
                    "⚠️ [RuleCollections] Failed to persist migrated custom rules: \(error)")
            }
            do {
                try await ruleCollectionStore.saveCollections(storedCollections)
            } catch {
                AppLogger.shared.log(
                    "⚠️ [RuleCollections] Failed to persist collections after migration: \(error)")
            }
        }

        ruleCollections = RuleCollectionDeduplicator.dedupe(storedCollections)
        customRules = storedCustomRules
        AppLogger.shared.log("📊 [RuleCollectionsManager] bootstrap: loaded \(customRules.count) custom rules from store")

        ensureDefaultCollectionsIfNeeded()
        runMigrations()

        // Restore keymap collection if a non-QWERTY layout was active
        if activeKeymapId != LogicalKeymap.defaultId {
            if let keymapCollection = KeymapMappingGenerator.generateCollection(
                for: activeKeymapId,
                includePunctuation: keymapIncludesPunctuation
            ) {
                // Remove any stale keymap collection first
                ruleCollections.removeAll { $0.id == RuleCollectionIdentifier.keymapLayout }
                // Insert at beginning so custom rules take priority
                ruleCollections.insert(keymapCollection, at: 0)
                AppLogger.shared.log("⌨️ [RuleCollections] Restored keymap collection for \(activeKeymapId)")
            }
        }

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()

        await regenerateConfigFromCollections()
    }

    // MARK: - Event Monitoring

    /// Start listening for events from Kanata TCP server (layer changes, action URIs, key input)
    func startEventMonitoring(port: Int) {
        AppLogger.shared.log("🌐 [RuleCollectionsManager] Starting event monitoring on port \(port)")
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.log("🌐 [RuleCollectionsManager] Skipping event monitoring (test environment)")
            return
        }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await eventListener.start(
                port: port,
                onLayerChange: { [weak self] layer in
                    guard let self else { return }
                    await MainActor.run {
                        self.updateActiveLayerName(layer)
                    }
                },
                onActionURI: { [weak self] actionURI in
                    guard let self else { return }
                    await MainActor.run {
                        self.handleActionURI(actionURI)
                    }
                },
                onUnknownMessage: { [weak self] message in
                    guard let self else { return }
                    await MainActor.run {
                        self.handleUnknownMessage(message)
                    }
                },
                onKeyInput: { key, action in
                    // Post notification for TCP-based physical key input events
                    // Used by KeyboardVisualizationViewModel for overlay highlighting
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataKeyInput,
                            object: nil,
                            userInfo: ["key": key, "action": action.rawValue.lowercased()]
                        )
                    }
                },
                onHoldActivated: { activation in
                    // Post notification when tap-hold key transitions to hold state
                    // Used by KeyboardVisualizationViewModel for showing hold labels
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataHoldActivated,
                            object: nil,
                            userInfo: ["key": activation.key, "action": activation.action]
                        )
                    }
                },
                onTapActivated: { activation in
                    // Post notification when tap-hold key triggers its tap action
                    // Used by KeyboardVisualizationViewModel for suppressing output keys
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataTapActivated,
                            object: nil,
                            userInfo: ["key": activation.key, "action": activation.action]
                        )
                    }
                },
                onOneShotActivated: { activation in
                    // Post notification when one-shot modifier key is activated
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataOneShotActivated,
                            object: nil,
                            userInfo: ["key": activation.key, "modifiers": activation.modifiers]
                        )
                    }
                },
                onChordResolved: { resolution in
                    // Post notification when chord (multi-key combo) resolves
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataChordResolved,
                            object: nil,
                            userInfo: ["keys": resolution.keys, "action": resolution.action]
                        )
                    }
                },
                onTapDanceResolved: { resolution in
                    // Post notification when tap-dance resolves to action
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataTapDanceResolved,
                            object: nil,
                            userInfo: [
                                "key": resolution.key,
                                "tapCount": resolution.tapCount,
                                "action": resolution.action
                            ]
                        )
                    }
                }
            )
        }
    }

    /// Handle a keypath:// action URI received via push-msg
    private func handleActionURI(_ actionURI: KeyPathActionURI) {
        AppLogger.shared.log("🎯 [RuleCollectionsManager] Action URI: \(actionURI.url.absoluteString)")

        // Dispatch to ActionDispatcher
        ActionDispatcher.shared.dispatch(actionURI)

        // Also notify any external observers
        onActionURI?(actionURI)
    }

    /// Handle an unknown (non-keypath://) message
    /// These are typically icon/emphasis messages: "icon:arrow-left", "emphasis:h,j,k,l"
    private func handleUnknownMessage(_ message: String) {
        AppLogger.shared.log("📨 [RuleCollectionsManager] Push message: \(message)")

        // Post notification for keyboard visualization (icon/emphasis handling)
        NotificationCenter.default.post(
            name: .kanataMessagePush,
            object: nil,
            userInfo: ["message": message]
        )

        // Also notify external observers
        onUnknownMessage?(message)
    }

    /// Deprecated: Use startEventMonitoring instead
    @available(*, deprecated, renamed: "startEventMonitoring")
    func startLayerMonitoring(port: Int) {
        startEventMonitoring(port: port)
    }

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
        let catalogMatch = RuleCollectionCatalog().defaultCollections().first { $0.id == id }
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

        // Special handling: If Leader Key collection is toggled off, reset all momentary activators to default (space)
        if id == RuleCollectionIdentifier.leaderKey, !isEnabled {
            await updateLeaderKey("space")
            return // updateLeaderKey already calls regenerateConfigFromCollections
        }

        refreshLayerIndicatorState()
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
           config.inputKey != "leader"
        {
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
    private func warmLauncherIconCache(for config: LauncherGridConfig) async {
        let enabledMappings = config.mappings.filter(\.isEnabled)
        AppLogger.shared.debug("🖼️ [RuleCollections] Warming cache for \(enabledMappings.count) launcher mappings")

        for mapping in enabledMappings {
            await IconResolverService.shared.preloadIcon(for: mapping.target)
        }
    }

    /// Pre-cache icons for layer-based app launches (e.g., Vim nav mode apps)
    private func warmLayerIconCache(for collection: RuleCollection) async {
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
           let conflict = conflictInfo(for: rule)
        {
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

    // MARK: - Keymap Layout Management

    /// Set the active keyboard layout and regenerate the config.
    ///
    /// When a non-QWERTY layout is selected, this generates Kanata rules that
    /// remap physical QWERTY keys to output the target layout's characters.
    ///
    /// - Parameters:
    ///   - keymapId: The layout ID (e.g., "colemak-dh", "dvorak", or "qwerty-us" for none)
    ///   - includePunctuation: Whether to remap punctuation keys (relevant for Dvorak)
    /// - Returns: Array of conflicting custom rules, if any
    @discardableResult
    func setActiveKeymap(_ keymapId: String, includePunctuation: Bool) async -> [RuleConflictInfo] {
        AppLogger.shared.log("⌨️ [RuleCollections] Setting active keymap to '\(keymapId)' (punctuation: \(includePunctuation))")

        let previousKeymapId = activeKeymapId
        activeKeymapId = keymapId
        keymapIncludesPunctuation = includePunctuation

        // Check for conflicts with custom rules
        let conflicts = detectKeymapConflicts(keymapId: keymapId, includePunctuation: includePunctuation)

        if !conflicts.isEmpty {
            let conflictKeys = conflicts.flatMap(\.keys).joined(separator: ", ")
            onWarning?(
                "⚠️ Layout change affects custom rules on: \(conflictKeys). Custom rules will override layout mappings for those keys."
            )
            AppLogger.shared.log("⚠️ [RuleCollections] Keymap conflicts with custom rules on: \(conflictKeys)")
        }

        // Remove any existing keymap collection
        ruleCollections.removeAll { $0.id == RuleCollectionIdentifier.keymapLayout }

        // Add new keymap collection if not QWERTY
        if let keymapCollection = KeymapMappingGenerator.generateCollection(
            for: keymapId,
            includePunctuation: includePunctuation
        ) {
            // Insert at the beginning so custom rules take priority
            ruleCollections.insert(keymapCollection, at: 0)
            AppLogger.shared.log("⌨️ [RuleCollections] Added keymap collection with \(keymapCollection.mappings.count) mappings")
        } else if keymapId == LogicalKeymap.defaultId {
            AppLogger.shared.log("⌨️ [RuleCollections] QWERTY selected - no keymap collection needed")
        }

        // Persist keymap state
        await persistKeymapState()

        // Regenerate config
        let success = await regenerateConfigFromCollections()

        if !success {
            // Rollback on failure
            AppLogger.shared.log("⌨️ [RuleCollections] Keymap change failed - rolling back")
            activeKeymapId = previousKeymapId
            ruleCollections.removeAll { $0.id == RuleCollectionIdentifier.keymapLayout }
            if let previousCollection = KeymapMappingGenerator.generateCollection(
                for: previousKeymapId,
                includePunctuation: keymapIncludesPunctuation
            ) {
                ruleCollections.insert(previousCollection, at: 0)
            }
        }

        return conflicts
    }

    /// Detect conflicts between the keymap layout and existing custom rules.
    ///
    /// Returns information about which custom rules target keys that the keymap will remap.
    func detectKeymapConflicts(keymapId: String, includePunctuation: Bool) -> [RuleConflictInfo] {
        guard let keymap = LogicalKeymap.find(id: keymapId),
              keymapId != LogicalKeymap.defaultId
        else {
            return []
        }

        let keymapMappings = KeymapMappingGenerator.generateMappings(
            to: keymap,
            includePunctuation: includePunctuation
        )

        let keymapKeys = Set(keymapMappings.map { KanataKeyConverter.convertToKanataKey($0.input) })

        var conflicts: [RuleConflictInfo] = []

        for rule in customRules where rule.isEnabled {
            let normalizedInput = KanataKeyConverter.convertToKanataKey(rule.input)
            if keymapKeys.contains(normalizedInput) {
                conflicts.append(RuleConflictInfo(source: .customRule(rule), keys: [normalizedInput]))
            }
        }

        return conflicts
    }

    /// Persist the current keymap state to UserDefaults
    private func persistKeymapState() async {
        UserDefaults.standard.set(activeKeymapId, forKey: "activeKeymapId")
        UserDefaults.standard.set(keymapIncludesPunctuation, forKey: "keymapIncludesPunctuation")
        AppLogger.shared.log("💾 [RuleCollections] Persisted keymap state: \(activeKeymapId)")
    }

    /// Restore keymap state from UserDefaults (called during bootstrap)
    private func restoreKeymapState() {
        if let storedKeymapId = UserDefaults.standard.string(forKey: "activeKeymapId") {
            activeKeymapId = storedKeymapId
        }
        keymapIncludesPunctuation = UserDefaults.standard.bool(forKey: "keymapIncludesPunctuation")
        AppLogger.shared.log("📂 [RuleCollections] Restored keymap state: \(activeKeymapId) (punctuation: \(keymapIncludesPunctuation))")
    }

    // MARK: - Private Helpers

    private func ensureDefaultCollectionsIfNeeded() {
        if ruleCollections.isEmpty {
            ruleCollections = RuleCollectionCatalog().defaultCollections()
        }
        refreshLayerIndicatorState()
    }

    // MARK: - Migrations

    private enum MigrationKey {
        static let launcherEnabledByDefault = "RuleCollections.Migration.LauncherEnabledByDefault"
    }

    /// Run one-time migrations for collection state changes
    private func runMigrations() {
        // Migration: Enable Quick Launcher by default (added in 1.1)
        // This runs once for existing users who had launcher disabled by old default
        if !UserDefaults.standard.bool(forKey: MigrationKey.launcherEnabledByDefault) {
            if let index = ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                if !ruleCollections[index].isEnabled {
                    ruleCollections[index].isEnabled = true
                    AppLogger.shared.log("♻️ [RuleCollections] Migration: Enabled Quick Launcher by default")
                }
            }
            UserDefaults.standard.set(true, forKey: MigrationKey.launcherEnabledByDefault)
        }
    }

    private func dedupeRuleCollectionsInPlace() {
        ruleCollections = RuleCollectionDeduplicator.dedupe(ruleCollections)
    }

    private func refreshLayerIndicatorState() {
        let hasLayered = ruleCollections.contains { $0.isEnabled && $0.targetLayer != .base }
        if !hasLayered {
            updateActiveLayerName(RuleCollectionLayer.base.kanataName)
        }
    }

    private func updateActiveLayerName(_ rawName: String) {
        let normalized = rawName.isEmpty ? RuleCollectionLayer.base.kanataName : rawName
        let display = normalized.capitalized

        if currentLayerName == display { return }

        currentLayerName = display
        onLayerChanged?(display)

        // Show visual layer indicator
        AppLogger.shared.log("🎯 [RuleCollectionsManager] Calling LayerIndicatorManager.showLayer('\(display)')")
        LayerIndicatorManager.shared.showLayer(display)
    }

    /// Regenerates the Kanata configuration from collections and custom rules.
    /// Returns `true` on success, `false` if validation or saving fails.
    @discardableResult
    private func regenerateConfigFromCollections(skipReload: Bool = false) async -> Bool {
        dedupeRuleCollectionsInPlace()

        AppLogger.shared.log("🔄 [RuleCollections] regenerateConfigFromCollections: \(ruleCollections.count) collections, \(customRules.count) custom rules")

        // INVARIANT: In production, ruleCollections should never be empty (at minimum, macOS Function Keys)
        // Tests may create isolated scenarios with empty collections, so only warn in debug builds
        if ruleCollections.isEmpty {
            AppLogger.shared.log("⚠️ [RuleCollections] regenerateConfigFromCollections called with empty collections")
        }

        // INVARIANT: At least one collection should be enabled (macOS Function Keys is system default)
        // Log warning instead of assert to avoid crashing in edge cases
        if !ruleCollections.contains(where: \.isEnabled), !ruleCollections.isEmpty {
            AppLogger.shared.log("⚠️ [RuleCollections] No enabled collections - config will only have defaults")
        }

        do {
            // Suppress file watcher before saving to prevent double-reload race condition
            // Without this, the file watcher detects our write and tries to reload,
            // which can race with onRulesChanged reload and cause an error beep
            onBeforeSave?()

            AppLogger.shared.log("🔄 [RuleCollections] Calling configurationService.saveConfiguration...")
            // IMPORTANT: Save config FIRST (validates before writing)
            // Only persist to stores AFTER config is successfully written
            // This prevents store/config mismatch if validation fails
            try await configurationService.saveConfiguration(
                ruleCollections: ruleCollections,
                customRules: customRules
            )
            AppLogger.shared.log("✅ [RuleCollections] configurationService.saveConfiguration succeeded")

            // Config write succeeded - now persist to stores
            try await ruleCollectionStore.saveCollections(ruleCollections)
            try await customRulesStore.saveRules(customRules)
            AppLogger.shared.log("✅ [RuleCollections] Stores persisted")

            // Notify observers and play success sound
            await MainActor.run {
                NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                SoundManager.shared.playTinkSound()
            }

            if !skipReload {
                await onRulesChanged?()
            }

            return true
        } catch {
            AppLogger.shared.log("❌ [RuleCollections] Failed to regenerate config: \(error)")
            AppLogger.shared.log("❌ [RuleCollections] Error details: \(String(describing: error))")

            // Extract user-friendly error message
            let userMessage = if let keyPathError = error as? KeyPathError,
                                 case let .configuration(configError) = keyPathError,
                                 case let .validationFailed(errors) = configError
            {
                "Configuration validation failed:\n\n" + errors.joined(separator: "\n")
            } else {
                "Failed to save configuration: \(error.localizedDescription)"
            }

            // Notify user via callback
            AppLogger.shared.debug("🚨 [RuleCollectionsManager] About to call onError, callback is \(onError == nil ? "nil" : "set"): \(userMessage)")
            onError?(userMessage)

            await MainActor.run {
                SoundManager.shared.playErrorSound()
            }

            return false
        }
    }

    // MARK: - Conflict Detection

    private func normalizedKeys(for collection: RuleCollection) -> Set<String> {
        Set(collection.mappings.map { KanataKeyConverter.convertToKanataKey($0.input) })
    }

    private func normalizedActivator(for collection: RuleCollection) -> (input: String, layer: RuleCollectionLayer)? {
        guard let activator = collection.momentaryActivator else { return nil }
        return (KanataKeyConverter.convertToKanataKey(activator.input), activator.targetLayer)
    }

    private func conflictInfo(for candidate: RuleCollection) -> RuleConflictInfo? {
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

        if candidate.targetLayer == .base {
            if let conflict = conflictWithCustomRules(candidateKeys) {
                return conflict
            }
        }

        return nil
    }

    private func conflictInfo(for rule: CustomRule) -> RuleConflictInfo? {
        let normalizedKey = KanataKeyConverter.convertToKanataKey(rule.input)

        for collection in ruleCollections where collection.isEnabled && collection.targetLayer == .base {
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

    private func conflictWithCustomRules(_ keys: Set<String>) -> RuleConflictInfo? {
        for rule in customRules where rule.isEnabled {
            let normalized = KanataKeyConverter.convertToKanataKey(rule.input)
            if keys.contains(normalized) {
                return RuleConflictInfo(source: .customRule(rule), keys: [normalized])
            }
        }
        return nil
    }

    // MARK: - Conflict Resolution

    /// Disable a conflicting rule source (collection or custom rule)
    private func disableConflicting(_ source: RuleConflictInfo.Source) async {
        switch source {
        case let .collection(collection):
            await toggleCollection(id: collection.id, isEnabled: false)
        case let .customRule(rule):
            await toggleCustomRule(id: rule.id, isEnabled: false)
        }
    }
}
