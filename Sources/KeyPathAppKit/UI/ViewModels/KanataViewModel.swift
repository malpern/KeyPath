import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import SwiftUI

/// MVVM ViewModel for RuntimeCoordinator
///
/// This class provides a thin UI-focused layer between SwiftUI views and RuntimeCoordinator.
/// It owns all @Published properties for UI reactivity and delegates business logic to RuntimeCoordinator.
///
/// Architecture:
/// - ObservableObject for SwiftUI reactivity
/// - All @Published properties moved from RuntimeCoordinator
/// - Thin adapter - no business logic
/// - Observes RuntimeCoordinator state changes
/// - Delegates all actions to RuntimeCoordinator
@MainActor
class KanataViewModel: ObservableObject {
    // MARK: - Published Properties (moved from RuntimeCoordinator)

    // Core Status Properties
    @Published var lastError: String?
    @Published var lastWarning: String?
    @Published var keyMappings: [KeyMapping] = []
    @Published var ruleCollections: [RuleCollection] = []
    @Published var customRules: [CustomRule] = []
    @Published var currentLayerName: String = RuleCollectionLayer.base.displayName
    @Published var diagnostics: [KanataDiagnostic] = []
    @Published var lastProcessExitCode: Int32?
    @Published var lastConfigUpdate: Date = .init()

    // UI State Properties (Legacy state removed - use InstallerEngine/SystemContext)
    // Removed: errorReason, showWizard, launchFailureStatus

    // Validation-specific UI state
    @Published var showingValidationAlert = false
    @Published var validationAlertTitle = ""
    @Published var validationAlertMessage = ""
    @Published var validationAlertActions: [ValidationAlertAction] = []

    // Save progress feedback
    @Published var saveStatus: SaveStatus = .idle

    // Emergency stop state
    @Published var emergencyStopActivated: Bool = false

    // Toast notifications
    @Published var toastMessage: String?
    @Published var toastType: ToastType = .success
    private var toastTask: Task<Void, Never>?

    // Rule conflict resolution
    @Published var showRuleConflictDialog = false
    @Published var pendingRuleConflict: RuleConflictContext?

    enum ToastType {
        case success
        case error
        case info
        case warning
    }

    // MARK: - Private Properties

    private let manager: RuntimeCoordinator
    private var stateObservationTask: Task<Void, Never>?

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
        // Debug: Log custom rules count when updating UI with object identity
        AppLogger.shared.log("📊 [KanataViewModel] updateUI: customRules.count = \(state.customRules.count), vmID=\(ObjectIdentifier(self))")

        if let error = state.lastError {
            AppLogger.shared.debug("🚨 [KanataViewModel] updateUI: receiving lastError = \(error)")
        }
        lastError = state.lastError
        keyMappings = state.keyMappings
        ruleCollections = state.ruleCollections
        customRules = state.customRules
        currentLayerName = state.currentLayerName
        diagnostics = state.diagnostics
        lastProcessExitCode = state.lastProcessExitCode
        lastConfigUpdate = state.lastConfigUpdate
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

        // Map validation error to alert properties
        if let error = state.validationError {
            showingValidationAlert = true

            switch error {
            case let .invalidStartup(errors, backupPath):
                validationAlertTitle = "Configuration File Invalid"
                validationAlertMessage = """
                KeyPath detected errors in your configuration file and has automatically created a backup and restored default settings.

                Errors found:
                \(errors.joined(separator: "\n• "))

                Your original configuration has been backed up to:
                \(backupPath)

                KeyPath is now using a default configuration (Caps Lock → Escape).
                """
                validationAlertActions = [
                    ValidationAlertAction(title: "OK", style: .default) { [weak self] in
                        self?.clearValidationError()
                    },
                    ValidationAlertAction(title: "Open Backup Location", style: .default) { [weak self] in
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backupPath)])
                        self?.clearValidationError()
                    }
                ]

            case let .saveFailed(title, errors):
                validationAlertTitle = title
                validationAlertMessage = """
                KeyPath found errors in the configuration:

                \(errors.joined(separator: "\n• "))

                What would you like to do?
                """
                validationAlertActions = [
                    ValidationAlertAction(title: "Cancel", style: .cancel) { [weak self] in
                        self?.clearValidationError()
                    },
                    ValidationAlertAction(title: "Use Default Config", style: .destructive) { [weak self] in
                        Task {
                            try? await self?.resetToDefaultConfig()
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

    // MARK: - Action Delegation to RuntimeCoordinator

    // Note: Removed manual syncFromManager() calls - AsyncStream automatically updates UI

    func toggleRuleCollection(_ id: UUID, enabled: Bool) async {
        await manager.toggleRuleCollection(id: id, isEnabled: enabled)
        let collection = ruleCollections.first { $0.id == id }
        let collectionName = collection?.name ?? "Collection"

        // Special message for Home Row Mods
        if id == RuleCollectionIdentifier.homeRowMods {
            if enabled {
                showToast("Home Row Mods enabled - tap keys for letters, hold for modifiers", type: .success)
            } else {
                showToast("Home Row Mods disabled", type: .info)
            }
        } else {
            if enabled {
                showToast("\(collectionName) enabled", type: .success)
            } else {
                showToast("\(collectionName) disabled", type: .info)
            }
        }
    }

    func removeCustomRule(_ id: UUID) async {
        await manager.removeCustomRule(withID: id)
    }

    func saveCustomRule(_ rule: CustomRule) async {
        let success = await manager.saveCustomRule(rule)
        if success {
            showToast("Rule saved", type: .success)
        } else {
            showToast("Failed to save rule", type: .error)
        }
    }

    func toggleCustomRule(_ id: UUID, enabled: Bool) async {
        await manager.toggleCustomRule(id: id, isEnabled: enabled)
        let rule = customRules.first { $0.id == id }
        let ruleName = rule?.displayTitle ?? "Rule"
        if enabled {
            showToast("\(ruleName) enabled", type: .success)
        } else {
            showToast("\(ruleName) disabled", type: .info)
        }
    }

    func addRuleCollection(_ collection: RuleCollection) async {
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

    func updateHomeRowModsConfig(collectionId: UUID, config: HomeRowModsConfig) async {
        await manager.updateHomeRowModsConfig(collectionId: collectionId, config: config)
    }

    func updateLauncherConfig(_ collectionId: UUID, config: LauncherGridConfig) async {
        await manager.updateLauncherConfig(collectionId: collectionId, config: config)
    }

    /// Update the leader key for all collections that use momentary activation
    func updateLeaderKey(_ newKey: String) async {
        await manager.updateLeaderKey(newKey)
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

    func regenerateServices() async -> Bool {
        await manager.regenerateServices()
    }

    func updateStatus() async {
        await manager.updateStatus()
    }

    func inspectSystemContext() async -> SystemContext {
        await manager.inspectSystemContext()
    }

    func uninstall(deleteConfig: Bool) async -> InstallerReport {
        await manager.uninstall(deleteConfig: deleteConfig)
    }

    func runFullRepair(reason: String) async -> InstallerReport {
        await manager.runFullRepair(reason: reason)
    }

    func runFullInstall(reason: String) async -> InstallerReport {
        await manager.runFullInstall(reason: reason)
    }

    // MARK: - Service Controls

    func startKanata(reason: String = "User action") async -> Bool {
        await manager.startKanata(reason: reason)
    }

    func stopKanata(reason: String = "User action") async -> Bool {
        await manager.stopKanata(reason: reason)
    }

    // MARK: - Toast Notifications

    private func showToast(_ message: String, type: ToastType, duration: TimeInterval = 3.0) {
        toastTask?.cancel()
        toastMessage = message
        toastType = type

        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    func restartKanata(reason: String = "User action") async -> Bool {
        await manager.restartKanata(reason: reason)
    }

    func currentServiceState() async -> KanataService.ServiceState {
        await manager.currentServiceState()
    }

    // MARK: - Rule Conflict Resolution

    /// Called when user makes a choice in the conflict resolution dialog
    func resolveRuleConflict(with choice: RuleConflictChoice?) {
        showRuleConflictDialog = false
        manager.resolveConflict(with: choice)
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
