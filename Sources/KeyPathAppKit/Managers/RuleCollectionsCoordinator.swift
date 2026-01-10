import Foundation
import KeyPathCore

/// Coordinates rule collection operations with UI state updates
///
/// This coordinator handles the pattern of:
/// 1. Performing rule collection operations
/// 2. Applying key mappings to UI state
/// 3. Notifying observers of state changes
///
/// Extracted from RuntimeCoordinator to reduce its size and improve separation of concerns.
@MainActor
final class RuleCollectionsCoordinator {
    // MARK: - Dependencies

    private let ruleCollectionsManager: RuleCollectionsManager

    /// Callback to apply key mappings after rule changes
    private var applyMappings: ([KeyMapping]) -> Void

    /// Callback to notify state changes
    private var notifyStateChanged: () -> Void

    // MARK: - Initialization

    init(ruleCollectionsManager: RuleCollectionsManager) {
        self.ruleCollectionsManager = ruleCollectionsManager
        // Initialize with no-ops, will be set after RuntimeCoordinator is fully initialized
        applyMappings = { _ in }
        notifyStateChanged = {}
    }

    /// Configure callbacks (called after RuntimeCoordinator initialization)
    func configure(
        applyMappings: @escaping ([KeyMapping]) -> Void,
        notifyStateChanged: @escaping () -> Void
    ) {
        self.applyMappings = applyMappings
        self.notifyStateChanged = notifyStateChanged
    }

    // MARK: - Rule Collection Operations

    /// Toggle a rule collection's enabled state
    func toggleRuleCollection(id: UUID, isEnabled: Bool) async {
        await ruleCollectionsManager.toggleCollection(id: id, isEnabled: isEnabled)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Add a new rule collection
    func addRuleCollection(_ collection: RuleCollection) async {
        await ruleCollectionsManager.addCollection(collection)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Replace all rule collections
    func replaceRuleCollections(_ collections: [RuleCollection]) async {
        await ruleCollectionsManager.replaceCollections(collections)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update a single-key picker collection's selected output
    func updateCollectionOutput(id: UUID, output: String) async {
        await ruleCollectionsManager.updateCollectionOutput(id: id, output: output)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update a tap-hold picker collection's tap output
    func updateCollectionTapOutput(id: UUID, tapOutput: String) async {
        await ruleCollectionsManager.updateCollectionTapOutput(id: id, tapOutput: tapOutput)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update a tap-hold picker collection's hold output
    func updateCollectionHoldOutput(id: UUID, holdOutput: String) async {
        await ruleCollectionsManager.updateCollectionHoldOutput(id: id, holdOutput: holdOutput)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update a layer preset picker collection's selected preset
    func updateCollectionLayerPreset(id: UUID, presetId: String) async {
        await ruleCollectionsManager.updateCollectionLayerPreset(id: id, presetId: presetId)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update window snapping key convention
    func updateWindowKeyConvention(id: UUID, convention: WindowKeyConvention) async {
        await ruleCollectionsManager.updateWindowKeyConvention(id: id, convention: convention)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update function key mode (Media Keys vs Function Keys)
    func updateFunctionKeyMode(id: UUID, mode: FunctionKeyMode) async {
        await ruleCollectionsManager.updateFunctionKeyMode(id: id, mode: mode)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update home row mods configuration
    func updateHomeRowModsConfig(id: UUID, config: HomeRowModsConfig) async {
        await ruleCollectionsManager.updateHomeRowModsConfig(id: id, config: config)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update home row layer toggles configuration
    func updateHomeRowLayerTogglesConfig(id: UUID, config: HomeRowLayerTogglesConfig) async {
        await ruleCollectionsManager.updateHomeRowLayerTogglesConfig(id: id, config: config)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update chord groups configuration
    func updateChordGroupsConfig(id: UUID, config: ChordGroupsConfig) async {
        await ruleCollectionsManager.updateChordGroupsConfig(id: id, config: config)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update sequences configuration
    func updateSequencesConfig(id: UUID, config: SequencesConfig) async {
        await ruleCollectionsManager.updateSequencesConfig(id: id, config: config)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update launcher grid configuration
    func updateLauncherConfig(id: UUID, config: LauncherGridConfig) async {
        await ruleCollectionsManager.updateLauncherConfig(id: id, config: config)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Update the leader key for all collections that use momentary activation
    func updateLeaderKey(_ newKey: String) async {
        await ruleCollectionsManager.updateLeaderKey(newKey)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    // MARK: - Custom Rule Operations

    /// Save a custom rule
    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false) async -> Bool {
        let result = await ruleCollectionsManager.saveCustomRule(rule, skipReload: skipReload)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
        if result {
            SoundManager.shared.playGlassSound()
        }
        return result
    }

    /// Toggle a custom rule's enabled state
    func toggleCustomRule(id: UUID, isEnabled: Bool) async {
        await ruleCollectionsManager.toggleCustomRule(id: id, isEnabled: isEnabled)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
        SoundManager.shared.playTinkSound()
    }

    /// Remove a custom rule
    func removeCustomRule(withID id: UUID) async {
        await ruleCollectionsManager.removeCustomRule(id: id)
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Clear all custom rules (without affecting rule collections)
    func clearAllCustomRules() async {
        await ruleCollectionsManager.clearAllCustomRules()
        applyMappings(ruleCollectionsManager.enabledMappings())
        notifyStateChanged()
    }

    /// Create a custom rule for saving
    func makeCustomRule(input: String, output: String) -> CustomRule {
        ruleCollectionsManager.makeCustomRule(input: input, output: output)
    }

    /// Get existing custom rule for the given input key, if any
    func getCustomRule(forInput input: String) -> CustomRule? {
        ruleCollectionsManager.getCustomRule(forInput: input)
    }

    // MARK: - Read-Only Access

    /// Get enabled mappings from all collections
    func enabledMappings() -> [KeyMapping] {
        ruleCollectionsManager.enabledMappings()
    }

    /// Get all rule collections
    var ruleCollections: [RuleCollection] {
        ruleCollectionsManager.ruleCollections
    }

    /// Get all custom rules
    var customRules: [CustomRule] {
        ruleCollectionsManager.customRules
    }
}
