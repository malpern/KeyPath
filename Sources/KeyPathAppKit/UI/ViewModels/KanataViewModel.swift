import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import SwiftUI

/// MVVM ViewModel for KanataManager
///
/// This class provides a thin UI-focused layer between SwiftUI views and KanataManager.
/// It owns all @Published properties for UI reactivity and delegates business logic to KanataManager.
///
/// Architecture:
/// - ObservableObject for SwiftUI reactivity
/// - All @Published properties moved from KanataManager
/// - Thin adapter - no business logic
/// - Observes KanataManager state changes
/// - Delegates all actions to KanataManager
@MainActor
class KanataViewModel: ObservableObject {
    // MARK: - Published Properties (moved from KanataManager)

    // Core Status Properties
    @Published var lastError: String?
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

    // MARK: - Private Properties

    private let manager: KanataManager
    private var stateObservationTask: Task<Void, Never>?

    // MARK: - Manager Access

    /// Provides access to the underlying KanataManager for business logic components
    /// Use this sparingly - only when business logic components need direct manager access
    var underlyingManager: KanataManager {
        manager
    }

    // MARK: - Initialization

    init(manager: KanataManager) {
        self.manager = manager
        setupObservation()
    }

    deinit {
        stateObservationTask?.cancel()
    }

    // MARK: - Observation Setup

    /// Observe KanataManager state changes via AsyncStream (event-driven, not polling)
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
        lastError = state.lastError
        keyMappings = state.keyMappings
        ruleCollections = state.ruleCollections
        customRules = state.customRules
        diagnostics = state.diagnostics
        lastProcessExitCode = state.lastProcessExitCode
        lastConfigUpdate = state.lastConfigUpdate
        showingValidationAlert = state.showingValidationAlert
        validationAlertTitle = state.validationAlertTitle
        validationAlertMessage = state.validationAlertMessage
        validationAlertActions = state.validationAlertActions
        saveStatus = state.saveStatus
        // Note: emergencyStopActivated is managed locally in ViewModel, not synced from manager
    }

    // MARK: - Action Delegation to KanataManager

    // Note: Removed manual syncFromManager() calls - AsyncStream automatically updates UI

    func toggleRuleCollection(_ id: UUID, enabled: Bool) async {
        await manager.toggleRuleCollection(id: id, isEnabled: enabled)
    }

    func removeCustomRule(_ id: UUID) async {
        await manager.removeCustomRule(withID: id)
    }

    func saveCustomRule(_ rule: CustomRule) async {
        _ = await manager.saveCustomRule(rule)
    }

    func toggleCustomRule(_ id: UUID, enabled: Bool) async {
        await manager.toggleCustomRule(id: id, isEnabled: enabled)
    }

    func addRuleCollection(_ collection: RuleCollection) async {
        await manager.addRuleCollection(collection)
    }

    func isCompletelyInstalled() -> Bool {
        manager.isCompletelyInstalled()
    }

    func createDefaultUserConfigIfMissing() async -> Bool {
        await manager.createDefaultUserConfigIfMissing()
    }

    func openFileInZed(_ path: String) {
        manager.openFileInZed(path)
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
        -> String {
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
}
