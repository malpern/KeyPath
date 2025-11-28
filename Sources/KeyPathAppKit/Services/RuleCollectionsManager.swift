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
        async let storedCollectionsTask = ruleCollectionStore.loadCollections()
        async let storedCustomRulesTask = customRulesStore.loadRules()

        var storedCollections = await storedCollectionsTask
        var storedCustomRules = await storedCustomRulesTask

        // Migrate legacy custom mappings if needed
        if storedCustomRules.isEmpty,
           let customIndex = storedCollections.firstIndex(where: {
               $0.id == RuleCollectionIdentifier.customMappings
           }) {
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

        ruleCollections = storedCollections
        customRules = storedCustomRules
        AppLogger.shared.log("📊 [RuleCollectionsManager] bootstrap: loaded \(customRules.count) custom rules from store")
        ensureDefaultCollectionsIfNeeded()
        refreshLayerIndicatorState()

        await regenerateConfigFromCollections()
    }

    // MARK: - Event Monitoring

    /// Start listening for events from Kanata TCP server (layer changes, action URIs)
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
    private func handleUnknownMessage(_ message: String) {
        AppLogger.shared.log("⚠️ [RuleCollectionsManager] Unknown message: \(message)")

        // Report error via ActionDispatcher
        ActionDispatcher.shared.onError?("Received non-keypath:// message: \(message)")

        // Also notify any external observers
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
        ruleCollections = collections
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
                onError?(
                    "Cannot enable \(candidate.name). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
                )
                AppLogger.shared.log(
                    "⚠️ [RuleCollections] Conflict enabling \(candidate.name) vs \(conflict.displayName) on \(conflict.keys)"
                )
                return
            }
        }

        guard let resolvedCandidate = candidate else { return }

        if let index = ruleCollections.firstIndex(where: { $0.id == id }) {
            ruleCollections[index].isEnabled = isEnabled
        } else {
            var newCollection = resolvedCandidate
            newCollection.isEnabled = isEnabled
            ruleCollections.append(newCollection)
        }

        // Special handling: If Leader Key collection is toggled off, reset all momentary activators to default (space)
        if id == RuleCollectionIdentifier.leaderKey, !isEnabled {
            await updateLeaderKey("space")
            return // updateLeaderKey already calls regenerateConfigFromCollections
        }

        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Add or update a rule collection
    func addCollection(_ collection: RuleCollection) async {
        if let conflict = conflictInfo(for: collection) {
            onError?(
                "Cannot enable \(collection.name). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
            )
            AppLogger.shared.log(
                "⚠️ [RuleCollections] Conflict adding \(collection.name) vs \(conflict.displayName) on \(conflict.keys)"
            )
            return
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
        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Update a single-key picker collection's selected output and regenerate its mapping
    func updateCollectionOutput(id: UUID, output: String) async {
        guard let index = ruleCollections.firstIndex(where: { $0.id == id }) else {
            // Try to find in catalog and add it
            let catalog = RuleCollectionCatalog()
            if var catalogCollection = catalog.defaultCollections().first(where: { $0.id == id }) {
                catalogCollection.selectedOutput = output
                catalogCollection.isEnabled = true
                // Update the mapping based on selected output
                if let inputKey = catalogCollection.pickerInputKey {
                    let description = catalogCollection.presetOptions.first { $0.output == output }?.label ?? "Custom"
                    catalogCollection.mappings = [KeyMapping(input: inputKey, output: output, description: description)]
                }
                ruleCollections.append(catalogCollection)
                refreshLayerIndicatorState()
                await regenerateConfigFromCollections()
            }
            return
        }

        ruleCollections[index].selectedOutput = output
        ruleCollections[index].isEnabled = true

        // Update the mapping based on selected output (skip for Leader Key which has no mappings)
        if let inputKey = ruleCollections[index].pickerInputKey, inputKey != "leader" {
            let description = ruleCollections[index].presetOptions.first { $0.output == output }?.label ?? "Custom"
            ruleCollections[index].mappings = [KeyMapping(input: inputKey, output: output, description: description)]
        }

        // Special handling: If this is the Leader Key collection, update all momentary activators
        if id == RuleCollectionIdentifier.leaderKey {
            await updateLeaderKey(output)
            return // updateLeaderKey already calls regenerateConfigFromCollections
        }

        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
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

        refreshLayerIndicatorState()
        await regenerateConfigFromCollections()
    }

    /// Save or update a custom rule
    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false) async -> Bool {
        AppLogger.shared.log("💾 [CustomRules] saveCustomRule called: id=\(rule.id), input='\(rule.input)', output='\(rule.output)'")

        if rule.isEnabled,
           let conflict = conflictInfo(for: rule) {
            onError?(
                "Cannot enable \(rule.displayTitle). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
            )
            AppLogger.shared.log(
                "⚠️ [CustomRules] Conflict saving \(rule.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
            )
            return false
        }

        if let index = customRules.firstIndex(where: { $0.id == rule.id }) {
            AppLogger.shared.log("💾 [CustomRules] Updating existing rule at index \(index)")
            customRules[index] = rule
        } else {
            AppLogger.shared.log("💾 [CustomRules] Adding new rule (count will be \(customRules.count + 1))")
            customRules.append(rule)
        }
        await regenerateConfigFromCollections(skipReload: skipReload)
        AppLogger.shared.log("💾 [CustomRules] Save complete, customRules.count = \(customRules.count)")
        return true
    }

    /// Toggle a custom rule on/off
    func toggleCustomRule(id: UUID, isEnabled: Bool) async {
        guard let existing = customRules.first(where: { $0.id == id }) else { return }

        if isEnabled,
           let conflict = conflictInfo(for: existing) {
            onError?(
                "Cannot enable \(existing.displayTitle). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
            )
            AppLogger.shared.log(
                "⚠️ [CustomRules] Conflict enabling \(existing.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
            )
            return
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

    // MARK: - Private Helpers

    private func ensureDefaultCollectionsIfNeeded() {
        if ruleCollections.isEmpty {
            ruleCollections = RuleCollectionCatalog().defaultCollections()
        }
        refreshLayerIndicatorState()
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

    private func regenerateConfigFromCollections(skipReload: Bool = false) async {
        do {
            try await ruleCollectionStore.saveCollections(ruleCollections)
            try await customRulesStore.saveRules(customRules)
            try await configurationService.saveConfiguration(
                ruleCollections: ruleCollections,
                customRules: customRules
            )

            if !skipReload {
                await onRulesChanged?()
            }
        } catch {
            AppLogger.shared.log("❌ [RuleCollections] Failed to regenerate config: \(error)")
        }
    }

    // MARK: - Conflict Detection

    private func normalizedKeys(for collection: RuleCollection) -> Set<String> {
        Set(collection.mappings.map { KanataKeyConverter.convertToKanataKey($0.input) })
    }

    private func normalizedActivator(for collection: RuleCollection) -> String? {
        collection.momentaryActivator?.input.lowercased()
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
               let act2 = normalizedActivator(for: other),
               act1 == act2 {
                return RuleConflictInfo(source: .collection(other), keys: [act1])
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
}
