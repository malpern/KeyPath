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
        lastError = state.lastError
        keyMappings = state.keyMappings
        ruleCollections = state.ruleCollections
        customRules = state.customRules
        diagnostics = state.diagnostics
        lastProcessExitCode = state.lastProcessExitCode
        lastConfigUpdate = state.lastConfigUpdate
        saveStatus = state.saveStatus
        // Note: emergencyStopActivated is managed locally in ViewModel, not synced from manager

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
        Task {
            await manager.clearValidationError()
        }
    }

    // MARK: - Action Delegation to RuntimeCoordinator

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

    func restartKanata(reason: String = "User action") async -> Bool {
        await manager.restartKanata(reason: reason)
    }

    func currentServiceState() async -> KanataService.ServiceState {
        await manager.currentServiceState()
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
