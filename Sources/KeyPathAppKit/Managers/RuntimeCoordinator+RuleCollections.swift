import Foundation
import KeyPathCore
import KeyPathRulesCore

extension RuntimeCoordinator {
    // MARK: - Rule Collections

    func catalogUpdatePreviews() -> [CatalogUpdatePreview] {
        ruleCollectionsManager.catalogUpdatePreviews()
    }

    func applyCatalogUpdates(ids: Set<UUID>) async -> CatalogUpdateApplicationResult {
        let result = await ruleCollectionsManager.applyCatalogUpdates(ids: ids)
        if result.saveResult.success { refreshRuleMappings() }
        return result
    }

    func replaceRuleCollections(_ collections: [RuleCollection]) async {
        await ruleCollectionsManager.replaceCollections(collections)
        refreshRuleMappings()
    }

    @MainActor
    func applyKeyMappings(_ mappings: [KeyMapping]) {
        keyMappings = mappings
    }

    func refreshRuleMappings() {
        let mappings = ruleCollectionsManager.committedRuleCollections.enabledMappings() + ruleCollectionsManager.committedCustomRules.enabledMappings()
        applyKeyMappings(mappings)
        notifyStateChanged()
    }

    func batchEnableCollections(ids: [UUID]) async {
        await ruleCollectionsManager.batchEnableCollections(ids: ids)
        refreshRuleMappings()
    }

    @discardableResult
    func addRuleCollection(_ collection: RuleCollection) async -> Bool {
        let result = await ruleCollectionsManager.addCollection(collection)
        refreshRuleMappings()
        return result
    }

    func updateCollectionOutput(id: UUID, output: String) async {
        await ruleCollectionsManager.updateCollectionOutput(id: id, output: output)
        refreshRuleMappings()
    }

    func updateCollectionTapOutput(id: UUID, tapOutput: String) async {
        await ruleCollectionsManager.updateCollectionTapOutput(id: id, tapOutput: tapOutput)
        refreshRuleMappings()
    }

    func updateCollectionHoldOutput(id: UUID, holdOutput: String) async {
        await ruleCollectionsManager.updateCollectionHoldOutput(id: id, holdOutput: holdOutput)
        refreshRuleMappings()
    }

    func updateCollectionLayerPreset(_ id: UUID, presetId: String) async {
        await ruleCollectionsManager.updateCollectionLayerPreset(id: id, presetId: presetId)
        refreshRuleMappings()
    }

    func updateWindowKeyConvention(_ id: UUID, convention: WindowKeyConvention) async {
        await ruleCollectionsManager.updateWindowKeyConvention(id: id, convention: convention)
        refreshRuleMappings()
    }

    func updateFunctionKeyMode(_ id: UUID, mode: FunctionKeyMode) async {
        await ruleCollectionsManager.updateFunctionKeyMode(id: id, mode: mode)
        refreshRuleMappings()
    }

    @discardableResult
    func updateHomeRowModsConfig(collectionId: UUID, config: HomeRowModsConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateHomeRowModsConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    @discardableResult
    func updateHomeRowLayerTogglesConfig(collectionId: UUID, config: HomeRowLayerTogglesConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateHomeRowLayerTogglesConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    @discardableResult
    func updateChordGroupsConfig(collectionId: UUID, config: ChordGroupsConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateChordGroupsConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    @discardableResult
    func updateSequencesConfig(collectionId: UUID, config: SequencesConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateSequencesConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    @discardableResult
    func updateLauncherConfig(collectionId: UUID, config: LauncherGridConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateLauncherConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    @discardableResult
    func updateAutoShiftSymbolsConfig(collectionId: UUID, config: AutoShiftSymbolsConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateAutoShiftSymbolsConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    @discardableResult
    func updateKeyRepeatControlConfig(collectionId: UUID, config: KeyRepeatControlConfig) async -> Bool {
        let result = await ruleCollectionsManager.updateKeyRepeatControlConfig(id: collectionId, config: config)
        refreshRuleMappings()
        return result
    }

    func updateWindowSnappingActivationMode(collectionId: UUID, mode: WindowSnappingActivationMode) async -> String? {
        let result = await ruleCollectionsManager.updateWindowSnappingActivationMode(id: collectionId, mode: mode)
        refreshRuleMappings()
        return result
    }

    func updateLeaderKey(_ newKey: String) async {
        await ruleCollectionsManager.updateLeaderKey(newKey)
        refreshRuleMappings()
    }

    @discardableResult
    func applyShortcutListGenerationInput(_ input: ShortcutListGenerationInput) async -> Bool {
        await ruleCollectionsManager.applyShortcutListGenerationInput(input)
    }

    @discardableResult
    func applyDeviceSelections(_ selections: [DeviceSelection]) async -> Bool {
        await ruleCollectionsManager.applyDeviceSelections(selections) { [weak self] in
            guard let self else { return false }
            return await restartKanata(reason: "Device selection changed")
        }
    }

    /// What admission says about saving `rule`, before anything is written.
    func reviewAdmission(forProposed rule: CustomRule) -> AdmissionReview {
        ruleCollectionsManager.reviewAdmission(forProposed: rule)
    }

    /// What admission says about turning `collection` on.
    func reviewAdmission(forEnabling collection: RuleCollection) -> AdmissionReview {
        ruleCollectionsManager.reviewAdmission(forEnabling: collection)
    }

    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false, autoResolveConflicts: Bool = false) async -> Bool {
        let saved = await ruleCollectionsManager.saveCustomRule(rule, skipReload: skipReload, autoResolveConflicts: autoResolveConflicts)
        refreshRuleMappings()
        if saved { SoundManager.shared.playGlassSound() }
        return saved
    }

    func removeCustomRule(withID id: UUID) async {
        await ruleCollectionsManager.removeCustomRule(id: id)
        refreshRuleMappings()
    }

    /// Clear all custom rules without affecting rule collections
    func clearAllCustomRules() async {
        await ruleCollectionsManager.clearAllCustomRules()
        refreshRuleMappings()
    }

    /// Creates or returns an existing custom rule for the given input key.
    /// If a rule already exists with the same input, returns a copy with the same ID but updated output.
    /// This prevents duplicate keys in the generated Kanata config.
    func makeCustomRule(input: String, output: String) -> CustomRule {
        ruleCollectionsManager.makeCustomRule(input: input, output: output)
    }

    /// Get existing custom rule for the given input key, if any
    func getCustomRule(forInput input: String) -> CustomRule? {
        ruleCollectionsManager.getCustomRule(forInput: input)
    }
}
