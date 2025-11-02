import Combine
import Foundation
import SwiftUI
import KeyPathDaemonLifecycle
import KeyPathWizardCore

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
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var keyMappings: [KeyMapping] = []
    @Published var diagnostics: [KanataDiagnostic] = []
    @Published var lastProcessExitCode: Int32?
    @Published var lastConfigUpdate: Date = .init()

    // UI State Properties (from SimpleKanataManager)
    @Published private(set) var currentState: SimpleKanataState = .starting
    @Published private(set) var errorReason: String?
    @Published private(set) var showWizard: Bool = false
    @Published private(set) var launchFailureStatus: LaunchFailureStatus?
    @Published private(set) var autoStartAttempts: Int = 0
    @Published private(set) var lastHealthCheck: Date?
    @Published private(set) var retryCount: Int = 0
    @Published private(set) var isRetryingAfterFix: Bool = false

    // Lifecycle State Properties (from KanataLifecycleManager)
    @Published var lifecycleState: LifecycleStateMachine.KanataState = .uninitialized
    @Published var lifecycleErrorMessage: String?
    @Published var isBusy: Bool = false
    @Published var canPerformActions: Bool = true
    @Published var autoStartAttempted: Bool = false
    @Published var autoStartSucceeded: Bool = false
    @Published var autoStartFailureReason: String?
    @Published var shouldShowWizard: Bool = false

    // Validation-specific UI state
    @Published var showingValidationAlert = false
    @Published var validationAlertTitle = ""
    @Published var validationAlertMessage = ""
    @Published var validationAlertActions: [ValidationAlertAction] = []

    // Save progress feedback
    @Published var saveStatus: SaveStatus = .idle

    // MARK: - Private Properties

    private let manager: KanataManager
    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - Observation Setup

    /// Observe KanataManager state changes and update UI properties
    private func setupObservation() {
        // Set up observation of manager state
        // This will be implemented to poll or observe manager state changes
        // For now, we'll use a simple polling mechanism

        Task { @MainActor in
            // Initial sync
            await syncFromManager()

            // Start periodic sync (temporary until we implement proper observation)
            Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { @MainActor in
                        await self?.syncFromManager()
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// Synchronize UI state from KanataManager
    private func syncFromManager() async {
        // Get current state from manager
        let state = manager.getCurrentUIState()

        // Update all published properties
        isRunning = state.isRunning
        lastError = state.lastError
        keyMappings = state.keyMappings
        diagnostics = state.diagnostics
        lastProcessExitCode = state.lastProcessExitCode
        lastConfigUpdate = state.lastConfigUpdate
        currentState = state.currentState
        errorReason = state.errorReason
        showWizard = state.showWizard
        launchFailureStatus = state.launchFailureStatus
        autoStartAttempts = state.autoStartAttempts
        lastHealthCheck = state.lastHealthCheck
        retryCount = state.retryCount
        isRetryingAfterFix = state.isRetryingAfterFix
        lifecycleState = state.lifecycleState
        lifecycleErrorMessage = state.lifecycleErrorMessage
        isBusy = state.isBusy
        canPerformActions = state.canPerformActions
        autoStartAttempted = state.autoStartAttempted
        autoStartSucceeded = state.autoStartSucceeded
        autoStartFailureReason = state.autoStartFailureReason
        shouldShowWizard = state.shouldShowWizard
        showingValidationAlert = state.showingValidationAlert
        validationAlertTitle = state.validationAlertTitle
        validationAlertMessage = state.validationAlertMessage
        validationAlertActions = state.validationAlertActions
        saveStatus = state.saveStatus
    }

    // MARK: - Action Delegation to KanataManager

    func startKanata() async {
        await manager.startKanata()
        await syncFromManager()
    }

    func stopKanata() async {
        await manager.stopKanata()
        await syncFromManager()
    }

    func manualStart() async {
        await manager.manualStart()
        await syncFromManager()
    }

    func manualStop() async {
        await manager.manualStop()
        await syncFromManager()
    }

    func updateStatus() async {
        await manager.updateStatus()
        await syncFromManager()
    }

    func forceRefreshStatus() async {
        await manager.forceRefreshStatus()
        await syncFromManager()
    }

    func startAutoLaunch(presentWizardOnFailure: Bool) async {
        await manager.startAutoLaunch(presentWizardOnFailure: presentWizardOnFailure)
        await syncFromManager()
    }

    func onWizardClosed() async {
        await manager.onWizardClosed()
        await syncFromManager()
    }

    func requestWizardPresentation() {
        manager.requestWizardPresentation()
        Task { await syncFromManager() }
    }

    func isCompletelyInstalled() -> Bool {
        manager.isCompletelyInstalled()
    }

    func createDefaultUserConfigIfMissing() async -> Bool {
        let result = await manager.createDefaultUserConfigIfMissing()
        await syncFromManager()
        return result
    }

    func openFileInZed(_ path: String) {
        manager.openFileInZed(path)
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws -> String {
        let result = try await manager.backupFailedConfigAndApplySafe(failedConfig: failedConfig, mappings: mappings)
        await syncFromManager()
        return result
    }

    func autoFixDiagnostic(_ diagnostic: KanataDiagnostic) async {
        _ = await manager.autoFixDiagnostic(diagnostic)
        await syncFromManager()
    }

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        await manager.validateConfigFile()
    }

    func resetToDefaultConfig() async throws {
        try await manager.resetToDefaultConfig()
        await syncFromManager()
    }

    func createPreEditBackup() -> Bool {
        manager.createPreEditBackup()
    }

    var configPath: String {
        manager.configPath
    }
}
