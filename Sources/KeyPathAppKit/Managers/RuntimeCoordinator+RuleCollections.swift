import Foundation
import KeyPathCore

extension RuntimeCoordinator {
    // MARK: - Rule Collections (delegates to RuleCollectionsCoordinator)

    func replaceRuleCollections(_ collections: [RuleCollection]) async {
        await ruleCollectionsCoordinator.replaceRuleCollections(collections)
    }

    func enabledMappingsFromCollections() -> [KeyMapping] {
        ruleCollectionsCoordinator.enabledMappings()
    }

    @MainActor
    func applyKeyMappings(_ mappings: [KeyMapping], persistCollections _: Bool = true) {
        keyMappings = mappings
        lastConfigUpdate = Date()
    }

    func toggleRuleCollection(id: UUID, isEnabled: Bool) async {
        AppLogger.shared.log("🎚️ [RuntimeCoordinator] toggleRuleCollection: id=\(id), isEnabled=\(isEnabled)")
        await ruleCollectionsCoordinator.toggleRuleCollection(id: id, isEnabled: isEnabled)
        AppLogger.shared.log("🎚️ [RuntimeCoordinator] toggleRuleCollection completed")
    }

    func addRuleCollection(_ collection: RuleCollection) async {
        await ruleCollectionsCoordinator.addRuleCollection(collection)
    }

    func updateCollectionOutput(id: UUID, output: String) async {
        await ruleCollectionsCoordinator.updateCollectionOutput(id: id, output: output)
    }

    func updateCollectionTapOutput(id: UUID, tapOutput: String) async {
        await ruleCollectionsCoordinator.updateCollectionTapOutput(id: id, tapOutput: tapOutput)
    }

    func updateCollectionHoldOutput(id: UUID, holdOutput: String) async {
        await ruleCollectionsCoordinator.updateCollectionHoldOutput(id: id, holdOutput: holdOutput)
    }

    func updateCollectionLayerPreset(_ id: UUID, presetId: String) async {
        await ruleCollectionsCoordinator.updateCollectionLayerPreset(id: id, presetId: presetId)
    }

    func updateWindowKeyConvention(_ id: UUID, convention: WindowKeyConvention) async {
        await ruleCollectionsCoordinator.updateWindowKeyConvention(id: id, convention: convention)
    }

    func updateFunctionKeyMode(_ id: UUID, mode: FunctionKeyMode) async {
        await ruleCollectionsCoordinator.updateFunctionKeyMode(id: id, mode: mode)
    }

    func updateHomeRowModsConfig(collectionId: UUID, config: HomeRowModsConfig) async {
        await ruleCollectionsCoordinator.updateHomeRowModsConfig(id: collectionId, config: config)
    }

    func updateHomeRowLayerTogglesConfig(collectionId: UUID, config: HomeRowLayerTogglesConfig) async {
        await ruleCollectionsCoordinator.updateHomeRowLayerTogglesConfig(id: collectionId, config: config)
    }

    func updateChordGroupsConfig(collectionId: UUID, config: ChordGroupsConfig) async {
        await ruleCollectionsCoordinator.updateChordGroupsConfig(id: collectionId, config: config)
    }

    func updateSequencesConfig(collectionId: UUID, config: SequencesConfig) async {
        await ruleCollectionsCoordinator.updateSequencesConfig(id: collectionId, config: config)
    }

    func updateLauncherConfig(collectionId: UUID, config: LauncherGridConfig) async {
        await ruleCollectionsCoordinator.updateLauncherConfig(id: collectionId, config: config)
    }

    func updateLeaderKey(_ newKey: String) async {
        await ruleCollectionsCoordinator.updateLeaderKey(newKey)
    }

    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false) async -> Bool {
        await ruleCollectionsCoordinator.saveCustomRule(rule, skipReload: skipReload)
    }

    func toggleCustomRule(id: UUID, isEnabled: Bool) async {
        await ruleCollectionsCoordinator.toggleCustomRule(id: id, isEnabled: isEnabled)
    }

    func removeCustomRule(withID id: UUID) async {
        await ruleCollectionsCoordinator.removeCustomRule(withID: id)
    }

    /// Clear all custom rules without affecting rule collections
    func clearAllCustomRules() async {
        await ruleCollectionsCoordinator.clearAllCustomRules()
    }

    func makeCustomRuleForSave(input: String, output: String) -> CustomRule {
        ruleCollectionsCoordinator.makeCustomRule(input: input, output: output)
    }

    /// Creates or returns an existing custom rule for the given input key.
    /// If a rule already exists with the same input, returns a copy with the same ID but updated output.
    /// This prevents duplicate keys in the generated Kanata config.
    func makeCustomRule(input: String, output: String) -> CustomRule {
        ruleCollectionsCoordinator.makeCustomRule(input: input, output: output)
    }

    /// Get existing custom rule for the given input key, if any
    func getCustomRule(forInput input: String) -> CustomRule? {
        ruleCollectionsCoordinator.getCustomRule(forInput: input)
    }
}
