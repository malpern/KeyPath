import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathRulesCore
import KeyPathWizardCore
import Observation
import SwiftUI

/// Presents runtime status, dialogs, and toasts to SwiftUI.
/// Rule views observe the settled state on RuleCollectionsManager directly.
@MainActor
@Observable
class KanataViewModel {
    var lastError: String? {
        manager.lastError
    }

    var reportedError: RuntimeCoordinator.ReportedError? {
        manager.reportedError
    }

    var ruleCollections: [RuleCollection] {
        manager.ruleCollectionsManager.committedRuleCollections
    }

    var customRules: [CustomRule] {
        manager.ruleCollectionsManager.committedCustomRules
    }

    var currentLayerName: String {
        manager.currentLayerName
    }

    /// Why the running session leaves Caps Lock rules inactive, if it does.
    var capsPausedMessage: String? {
        manager.serviceLifecycleCoordinator.sessionCapsPaused
    }

    /// Emergency stop state
    var emergencyStopActivated: Bool = false

    // Toast notifications
    var toastMessage: String?
    var toastType: ToastType = .success
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    var pendingRuleConflict: RuleConflictContext? {
        manager.pendingRuleConflict
    }

    var showRuleConflictDialog: Bool {
        get { pendingRuleConflict != nil }
        set {
            if !newValue, pendingRuleConflict != nil { resolveRuleConflict(with: nil) }
        }
    }

    var pendingMappingConflict: MappingConflictContext? {
        manager.pendingMappingConflict
    }

    var showMappingConflictDialog: Bool {
        get { pendingMappingConflict != nil }
        set {
            if !newValue, pendingMappingConflict != nil { resolveMappingConflict(disabling: nil) }
        }
    }

    var pendingRuleSetup: RuleSetupSession? {
        manager.pendingRuleSetup
    }

    var pendingPrerequisiteResolution: RulePrerequisiteDialogModel? {
        manager.pendingPrerequisiteResolution
    }

    var showPrerequisiteResolutionDialog: Bool {
        get { pendingPrerequisiteResolution != nil }
        set {
            if !newValue, pendingPrerequisiteResolution != nil { resolvePrerequisiteResolution(with: nil) }
        }
    }

    var pendingDependentResolution: RuleDependentResolutionDialogModel? {
        manager.pendingDependentResolution
    }

    var showDependentResolutionDialog: Bool {
        get { pendingDependentResolution != nil }
        set {
            if !newValue, pendingDependentResolution != nil { resolveDependentResolution(with: nil) }
        }
    }

    enum ToastType {
        case success
        case error
        case info
        case warning
    }

    // MARK: - Private Properties

    @ObservationIgnored private let manager: RuntimeCoordinator

    // MARK: - Manager Access

    /// Provides access to the underlying RuntimeCoordinator for business logic components
    /// Use this sparingly - only when business logic components need direct manager access
    var underlyingManager: RuntimeCoordinator {
        manager
    }

    // MARK: - Initialization

    init(manager: RuntimeCoordinator) {
        self.manager = manager
        manager.onWarning = { [weak self] warning in self?.showRuntimeWarning(warning) }
        if let warning = manager.lastWarning {
            showRuntimeWarning(warning)
        }
    }

    deinit {
        toastTask?.cancel()
    }

    private func showRuntimeWarning(_ warning: String) {
        // Conflict warnings need more reading time.
        showToast(warning, type: .warning, duration: warning.contains("conflicts") ? 10.0 : 5.0)
    }

    // MARK: - Rule Collection Actions

    func catalogUpdatePreviews() -> [CatalogUpdatePreview] {
        manager.catalogUpdatePreviews()
    }

    func applyCatalogUpdates(ids: Set<UUID>) async -> CatalogUpdateApplicationResult {
        await manager.applyCatalogUpdates(ids: ids)
    }

    func batchEnableCollections(_ ids: [UUID]) async {
        await manager.batchEnableCollections(ids: ids)
    }

    func toggleRuleCollection(_ id: UUID, enabled: Bool) async {
        let result = await manager.ruleCollectionsManager.toggleCollectionResult(id: id, isEnabled: enabled)
        manager.refreshRuleMappings()

        guard result.success else {
            if let error = result.error, !(error is CancellationError) {
                showToast(error.localizedDescription, type: .error)
            }
            return
        }

        let collection = ruleCollections.first { $0.id == id }
        let collectionName = collection?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")

        // Special handling for macOS Function Keys
        if id == RuleCollectionIdentifier.macFunctionKeys {
            if enabled {
                // Automatically enable "Use F1, F2, etc. as standard function keys" in macOS
                // This is required for Kanata to intercept F10/F11/F12 and remap to volume keys
                let wasSet = await setMacOSFunctionKeyMode(useStandardFKeys: true)
                if wasSet {
                    showToast(String(localized: "Function Keys enabled — macOS setting updated automatically"), type: .success, duration: 5.0)
                } else {
                    showToast(String(localized: "Function Keys enabled"), type: .success)
                }
            } else {
                // When disabling, we leave the macOS setting as-is (user may want to keep it)
                showToast(String(localized: "Function Keys disabled"), type: .info)
            }
            return
        }

        // Special message for Home Row Mods
        if id == RuleCollectionIdentifier.homeRowMods {
            if enabled {
                showToast(String(localized: "Home Row Mods enabled - tap keys for letters, hold for modifiers"), type: .success)
            } else {
                showToast(String(localized: "Home Row Mods disabled"), type: .info)
            }
        } else {
            if enabled {
                showToast(String(localized: "\(collectionName) enabled"), type: .success)
            } else {
                showToast(String(localized: "\(collectionName) disabled"), type: .info)
            }
        }
    }

    /// Set macOS "Use F1, F2, etc. keys as standard function keys" preference
    /// - Parameter useStandardFKeys: true to use standard F-keys, false for media keys
    /// - Returns: true if the setting was changed, false if it was already set or failed
    private func setMacOSFunctionKeyMode(useStandardFKeys: Bool) async -> Bool {
        let currentValue = CFPreferencesCopyValue(
            "com.apple.keyboard.fnState" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? Bool ?? false

        if currentValue == useStandardFKeys {
            AppLogger.shared.log("🎹 [KanataViewModel] macOS fnState already set to \(useStandardFKeys)")
            return false
        }

        // `defaults write -g com.apple.keyboard.fnState -bool …`, in the same domain the read above uses.
        CFPreferencesSetValue(
            "com.apple.keyboard.fnState" as CFString,
            useStandardFKeys as CFBoolean,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            AppLogger.shared.warn("⚠️ [KanataViewModel] Failed to set macOS fnState")
            return false
        }
        AppLogger.shared.log("🎹 [KanataViewModel] Set macOS fnState to \(useStandardFKeys)")
        return true
    }

    func removeCustomRule(_ id: UUID) async {
        await manager.removeCustomRule(withID: id)
    }

    func saveCustomRule(_ rule: CustomRule) async {
        let success = await manager.saveCustomRule(rule)
        if success {
            showToast(String(localized: "Rule saved"), type: .success)
        } else {
            showToast(String(localized: "Failed to save rule"), type: .error)
        }
    }

    func toggleCustomRule(_ id: UUID, enabled: Bool) async {
        let result = await manager.ruleCollectionsManager.toggleCustomRule(id: id, isEnabled: enabled)
        manager.refreshRuleMappings()
        guard let result else { return }
        guard result.success else {
            if let error = result.error, !(error is CancellationError) {
                showToast(error.localizedDescription, type: .error)
            }
            return
        }

        SoundManager.shared.playTinkSound()
        let rule = customRules.first { $0.id == id }
        let ruleName = rule?.displayTitle ?? String(localized: "Rule", comment: "Fallback name in a toast")
        if enabled {
            showToast(String(localized: "\(ruleName) enabled"), type: .success)
        } else {
            showToast(String(localized: "\(ruleName) disabled"), type: .info)
        }
    }

    @discardableResult
    func addRuleCollection(_ collection: RuleCollection) async -> Bool {
        await manager.addRuleCollection(collection)
    }

    func updateCollectionOutput(_ id: UUID, output: String) async {
        await manager.updateCollectionOutput(id: id, output: output)
    }

    func updateCollectionTapOutput(_ id: UUID, tapOutput: String) async {
        await manager.updateCollectionTapOutput(id: id, tapOutput: tapOutput)
    }

    func updateCollectionHoldOutput(_ id: UUID, holdOutput: String) async {
        await manager.updateCollectionHoldOutput(id: id, holdOutput: holdOutput)
    }

    func updateCollectionLayerPreset(_ id: UUID, presetId: String) async {
        await manager.updateCollectionLayerPreset(id, presetId: presetId)
    }

    func updateWindowKeyConvention(_ id: UUID, convention: WindowKeyConvention) async {
        await manager.updateWindowKeyConvention(id, convention: convention)
    }

    func updateFunctionKeyMode(_ id: UUID, mode: FunctionKeyMode) async {
        await manager.updateFunctionKeyMode(id, mode: mode)
    }

    @discardableResult
    func updateHomeRowModsConfig(collectionId: UUID, config: HomeRowModsConfig) async -> HomeRowModsConfig {
        let wasNewlyEnabled = await manager.updateHomeRowModsConfig(collectionId: collectionId, config: config)
        let persistedConfig = Self.persistedHomeRowModsConfig(
            collectionId: collectionId,
            collections: ruleCollections
        )
        AppLogger.shared.log(
            "🧪 [QA] Persisted Home Row Mods config collection=\(collectionId.uuidString) mode=\(config.holdMode.rawValue) keys=\(config.enabledKeys.sorted().joined(separator: ",")) tapWindow=\(config.timing.tapWindow) holdDelay=\(config.timing.holdDelay)"
        )
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
        return persistedConfig
    }

    static func persistedHomeRowModsConfig(
        collectionId: UUID,
        collections: [RuleCollection]
    ) -> HomeRowModsConfig {
        collections
            .first(where: { $0.id == collectionId })?
            .configuration.homeRowModsConfig
            ?? RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == collectionId })?
            .configuration.homeRowModsConfig
            ?? HomeRowModsConfig()
    }

    func updateHomeRowLayerTogglesConfig(collectionId: UUID, config: HomeRowLayerTogglesConfig) async {
        let wasNewlyEnabled = await manager.updateHomeRowLayerTogglesConfig(collectionId: collectionId, config: config)
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
    }

    func updateChordGroupsConfig(collectionId: UUID, config: ChordGroupsConfig) async {
        let wasNewlyEnabled = await manager.updateChordGroupsConfig(collectionId: collectionId, config: config)
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
    }

    func updateSequencesConfig(collectionId: UUID, config: SequencesConfig) async {
        let wasNewlyEnabled = await manager.updateSequencesConfig(collectionId: collectionId, config: config)
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
    }

    func updateLauncherConfig(_ collectionId: UUID, config: LauncherGridConfig) async {
        let wasNewlyEnabled = await manager.updateLauncherConfig(collectionId: collectionId, config: config)
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
    }

    func updateAutoShiftSymbolsConfig(collectionId: UUID, config: AutoShiftSymbolsConfig) async {
        let wasNewlyEnabled = await manager.updateAutoShiftSymbolsConfig(collectionId: collectionId, config: config)
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
    }

    func updateKeyRepeatControlConfig(collectionId: UUID, config: KeyRepeatControlConfig) async {
        let wasNewlyEnabled = await manager.updateKeyRepeatControlConfig(collectionId: collectionId, config: config)
        if wasNewlyEnabled {
            let name = ruleCollections.first(where: { $0.id == collectionId })?.name ?? String(localized: "Collection", comment: "Fallback name in a toast")
            showToast(String(localized: "Turned on \(name)"), type: .success)
        }
    }

    func updateWindowSnappingActivationMode(collectionId: UUID, mode: WindowSnappingActivationMode) async -> String? {
        await manager.updateWindowSnappingActivationMode(collectionId: collectionId, mode: mode)
    }

    /// Update the leader key for all collections that use momentary activation
    func updateLeaderKey(_ newKey: String) async {
        await manager.updateLeaderKey(newKey)
    }

    @discardableResult
    func applyShortcutListGenerationInput(_ input: ShortcutListGenerationInput) async -> Bool {
        await manager.applyShortcutListGenerationInput(input)
    }

    @discardableResult
    func applyDeviceSelections(_ selections: [DeviceSelection]) async -> Bool {
        await manager.applyDeviceSelections(selections)
    }

    func isCompletelyInstalled() -> Bool {
        manager.isCompletelyInstalled()
    }

    func createDefaultUserConfigIfMissing() async -> Bool {
        await manager.createDefaultUserConfigIfMissing()
    }

    func openFileInZed(_ path: String) {
        Task { await manager.openFileInZed(path) }
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
        -> String
    {
        try await manager.backupFailedConfigAndApplySafe(failedConfig: failedConfig, mappings: mappings)
    }

    func autoFixDiagnostic(_ diagnostic: KanataDiagnostic) async {
        _ = await manager.autoFixDiagnostic(diagnostic)
    }

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        await manager.validateConfigFile()
    }

    func resetToDefaultConfig() async throws {
        try await manager.resetToDefaultConfig()
    }

    func createPreEditBackup() -> Bool {
        manager.createPreEditBackup()
    }

    var configPath: String {
        manager.configPath
    }

    // MARK: - Service Maintenance Actions

    func inspectSystemContext() async -> SystemContext {
        await manager.inspectSystemContext()
    }

    func uninstall(deleteConfig: Bool) async -> InstallerReport {
        await manager.uninstall(deleteConfig: deleteConfig)
    }

    // MARK: - Service Controls

    func startKanata(reason: String = "User action") async -> Bool {
        await manager.startKanata(reason: reason)
    }

    func stopKanata(reason: String = "User action") async -> Bool {
        await manager.stopKanata(reason: reason)
    }

    /// Switch to a different layer via Kanata TCP command.
    /// Returns true if the layer was changed successfully.
    func changeLayer(_ layerName: String) async -> Bool {
        await manager.changeLayer(layerName)
    }

    // MARK: - Toast Notifications

    private func showToast(_ message: String, type: ToastType, duration: TimeInterval = 3.0) {
        toastTask?.cancel()
        toastMessage = message
        toastType = type

        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    func restartKanata(reason: String = "User action") async -> Bool {
        await manager.restartKanata(reason: reason)
    }

    func setCapsSelection(_ selection: SessionCapsSelection?, automaticSetupDisabled: Bool? = nil,
                          selectedKeyboardOnly: Bool? = nil) async -> Bool
    {
        await manager.setCapsSelection(selection, automaticSetupDisabled: automaticSetupDisabled,
                                       selectedKeyboardOnly: selectedKeyboardOnly)
    }

    func setCapsExcludedKeyboardIDs(_ ids: Set<String>) async -> Bool {
        await manager.setCapsExcludedKeyboardIDs(ids)
    }

    func currentRuntimeStatus() async -> RuntimeStatus {
        await manager.currentRuntimeStatusInternal()
    }

    // MARK: - Rule Conflict Resolution

    /// Called when user makes a choice in the conflict resolution dialog
    func resolveRuleConflict(with choice: RuleConflictChoice?) {
        manager.resolveConflict(with: choice)
    }

    /// Called when the user resolves (or dismisses) a save-time mapping conflict (#460).
    /// Pass the collection id to disable, or nil to cancel.
    func resolveMappingConflict(disabling collectionID: UUID?) {
        manager.resolveMappingConflict(disabling: collectionID)
    }

    func resolvePrerequisiteResolution(
        with choice: RulePrerequisiteResolutionChoice?
    ) {
        manager.resolvePrerequisiteResolution(with: choice)
    }

    func resolveDependentResolution(
        with choice: RuleDependentResolutionChoice?
    ) {
        manager.resolveDependentResolution(with: choice)
    }
}
