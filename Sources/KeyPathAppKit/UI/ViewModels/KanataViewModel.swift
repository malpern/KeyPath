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
    // MARK: - Observable Properties (moved from RuntimeCoordinator)

    // Core Status Properties
    var lastError: String?
    var lastWarning: String?
    var keyMappings: [KeyMapping] = []
    var ruleCollections: [RuleCollection] {
        manager.ruleCollectionsManager.committedRuleCollections
    }

    var customRules: [CustomRule] {
        manager.ruleCollectionsManager.committedCustomRules
    }

    var currentLayerName: String = RuleCollectionLayer.base.displayName
    var diagnostics: [KanataDiagnostic] = []
    var lastProcessExitCode: Int32?
    var lastConfigUpdate: Date = .init()
    var activeRuntimePathTitle: String?
    var activeRuntimePathDetail: String?
    /// Why the running session leaves Caps Lock rules inactive, if it does.
    var capsPausedMessage: String?

    // Validation-specific UI state
    var showingValidationAlert = false
    var validationAlertTitle = ""
    var validationAlertMessage = ""
    var validationAlertActions: [ValidationAlertAction] = []

    /// Save progress feedback
    var saveStatus: SaveStatus = .idle

    /// Emergency stop state
    var emergencyStopActivated: Bool = false

    // Toast notifications
    var toastMessage: String?
    var toastType: ToastType = .success
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // Rule conflict resolution
    var showRuleConflictDialog = false
    var pendingRuleConflict: RuleConflictContext?

    // Save-time mapping conflict resolution (#460)
    var showMappingConflictDialog = false
    var pendingMappingConflict: MappingConflictContext?

    // Enable/save prerequisite resolution (#869)
    var pendingRuleSetup: RuleSetupSession?
    var showPrerequisiteResolutionDialog = false
    var pendingPrerequisiteResolution: RulePrerequisiteDialogModel?

    // Disable-time dependent resolution (#868)
    var showDependentResolutionDialog = false
    var pendingDependentResolution: RuleDependentResolutionDialogModel?

    enum ToastType {
        case success
        case error
        case info
        case warning
    }

    // MARK: - Private Properties

    @ObservationIgnored private let manager: RuntimeCoordinator
    @ObservationIgnored private var stateObservationTask: Task<Void, Never>?

    // MARK: - Manager Access

    /// Provides access to the underlying RuntimeCoordinator for business logic components
    /// Use this sparingly - only when business logic components need direct manager access
    var underlyingManager: RuntimeCoordinator {
        manager
    }

    // MARK: - Initialization

    init(manager: RuntimeCoordinator) {
        self.manager = manager
        setupObservation()
    }

    deinit {
        stateObservationTask?.cancel()
    }

    // MARK: - Observation Setup

    /// Observe RuntimeCoordinator state changes via AsyncStream (event-driven, not polling)
    /// This dramatically reduces unnecessary UI updates by only reacting to actual state changes
    private func setupObservation() {
        stateObservationTask = Task { @MainActor in
            for await state in manager.stateChanges {
                guard !Task.isCancelled else { break }
                updateUI(with: state)
            }
        }
    }

    /// Update UI properties from state snapshot
    /// Only called when state actually changes (not on a timer)
    private func updateUI(with state: KanataUIState) {
        if let error = state.lastError {
            AppLogger.shared.debug("🚨 [KanataViewModel] updateUI: receiving lastError = \(error)")
        }
        lastError = state.lastError
        keyMappings = state.keyMappings
        currentLayerName = state.currentLayerName
        diagnostics = state.diagnostics
        lastProcessExitCode = state.lastProcessExitCode
        lastConfigUpdate = state.lastConfigUpdate
        activeRuntimePathTitle = state.activeRuntimePathTitle
        activeRuntimePathDetail = state.activeRuntimePathDetail
        capsPausedMessage = state.capsPausedMessage
        saveStatus = state.saveStatus
        // Note: emergencyStopActivated is managed locally in ViewModel, not synced from manager

        // Show warning toast if there's a new warning
        if let warning = state.lastWarning, warning != lastWarning {
            lastWarning = warning
            // Conflict warnings get 2x duration (10s vs 5s) since they're important
            let isConflictWarning = warning.contains("conflicts")
            let duration: TimeInterval = isConflictWarning ? 10.0 : 5.0
            showToast(warning, type: .warning, duration: duration)
        } else {
            lastWarning = state.lastWarning
        }

        // Handle rule conflict resolution dialog
        pendingRuleConflict = state.pendingRuleConflict
        showRuleConflictDialog = state.pendingRuleConflict != nil

        // Handle save-time mapping conflict resolution dialog (#460)
        pendingMappingConflict = state.pendingMappingConflict
        showMappingConflictDialog = state.pendingMappingConflict != nil

        pendingRuleSetup = manager.pendingRuleSetup
        pendingPrerequisiteResolution = state.pendingPrerequisiteResolution
        showPrerequisiteResolutionDialog = state.pendingPrerequisiteResolution != nil

        pendingDependentResolution = state.pendingDependentResolution
        showDependentResolutionDialog = state.pendingDependentResolution != nil

        // Map validation error to alert properties
        if let error = state.validationError {
            showingValidationAlert = true

            switch error {
            case let .invalidStartup(errors, backupPath):
                validationAlertTitle = String(localized: "Configuration File Invalid")
                validationAlertMessage = String(localized: """
                KeyPath detected errors in your configuration file and has automatically created a backup and restored default settings.

                Errors found:
                \(errors.joined(separator: "\n• "))

                Your original configuration has been backed up to:
                \(backupPath)

                KeyPath is now using a default configuration (Caps Lock → Escape).
                """)
                validationAlertActions = [
                    ValidationAlertAction(title: String(localized: "OK"), style: .default) { [weak self] in
                        self?.clearValidationError()
                    },
                    ValidationAlertAction(title: String(localized: "Open Backup Location"), style: .default) { [weak self] in
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backupPath)])
                        self?.clearValidationError()
                    }
                ]

            case let .saveFailed(title, errors):
                validationAlertTitle = title
                validationAlertMessage = String(localized: """
                KeyPath found errors in the configuration:

                \(errors.joined(separator: "\n• "))

                What would you like to do?
                """)
                validationAlertActions = [
                    ValidationAlertAction(title: String(localized: "Cancel"), style: .cancel) { [weak self] in
                        self?.clearValidationError()
                    },
                    ValidationAlertAction(title: String(localized: "Use Default Config"), style: .destructive) { [weak self] in
                        Task {
                            do {
                                try await self?.resetToDefaultConfig()
                            } catch {
                                AppLogger.shared.warn("⚠️ [KanataViewModel] Failed to reset to default config: \(error.localizedDescription)")
                            }
                            self?.clearValidationError()
                        }
                    }
                ]
            }
        } else {
            showingValidationAlert = false
            validationAlertActions = []
        }
    }

    private func clearValidationError() {
        manager.clearValidationError()
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

    func updateStatus() async {
        await manager.updateStatus()
    }

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

        toastTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            toastMessage = nil
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
        showRuleConflictDialog = false
        manager.resolveConflict(with: choice)
    }

    /// Called when the user resolves (or dismisses) a save-time mapping conflict (#460).
    /// Pass the collection id to disable, or nil to cancel.
    func resolveMappingConflict(disabling collectionID: UUID?) {
        showMappingConflictDialog = false
        manager.resolveMappingConflict(disabling: collectionID)
    }

    func resolvePrerequisiteResolution(
        with choice: RulePrerequisiteResolutionChoice?
    ) {
        showPrerequisiteResolutionDialog = false
        manager.resolvePrerequisiteResolution(with: choice)
    }

    func resolveDependentResolution(
        with choice: RuleDependentResolutionChoice?
    ) {
        showDependentResolutionDialog = false
        manager.resolveDependentResolution(with: choice)
    }
}

/// Actions available in validation error dialogs
struct ValidationAlertAction: Identifiable {
    let id = UUID()
    let title: String
    let style: ActionStyle
    let action: () -> Void

    enum ActionStyle {
        case `default`
        case cancel
        case destructive
    }
}
