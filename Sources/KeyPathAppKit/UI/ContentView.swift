import AppKit
import Combine
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @State var keyboardCapture: KeyboardCapture?
    @EnvironmentObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @Environment(\.permissionSnapshotProvider) var permissionSnapshotProvider
    @StateObject var stateController = MainAppStateController.shared // 🎯 Phase 3: Shared controller
    @StateObject var recordingCoordinator = RecordingCoordinator()
    @State var showingInstallationWizard = false {
        didSet {
            AppLogger.shared.log(
                "🎭 [ContentView] showingInstallationWizard changed from \(oldValue) to \(showingInstallationWizard)"
            )
        }
    }

    // Gate modal presentation until after early startup phases
    @State var canPresentModals = false
    @State var pendingShowWizardRequest = false

    @State var hasCheckedRequirements = false
    @State var showStatusMessage = false
    @State var statusMessage = ""
    @State var showingEmergencyAlert = false

    @State var showingConfigCorruptionAlert = false
    @State var configCorruptionDetails = ""
    @State var configRepairSuccessful = false
    @State var showingRepairFailedAlert = false
    @State var repairFailedDetails = ""
    @State var failedConfigBackupPath = ""
    @State var showingInstallAlert = false
    @State var showingKanataNotRunningAlert = false
    @State var showingKanataServiceStoppedAlert = false
    @State var showingSimpleMods = false
    @State var showingEmergencyStopDialog = false
    @State var showingUninstallDialog = false
    @State var toastManager = WizardToastManager()

    @State var saveDebounceTimer: Timer?
    let saveDebounceDelay: TimeInterval = 0.1

    @State var statusMessageTask: Task<Void, Never>?

    @State var lastInputDisabledReason: String = ""
    @State var lastOutputDisabledReason: String = ""
    @State var isInitialConfigLoad = true
    @State var showSetupBanner = false
    @State var showingConfigValidationError = false
    @State var configValidationErrorMessage = ""
    @State var showingValidationFailureModal = false
    @State var validationFailureErrors: [String] = []
    @State var validationFailureCopyText: String = ""
    @State var isAttemptingAIRepair = false
    @State var aiRepairError: String?
    @State var aiRepairBackupPath: String?
    @State var lastKanataServiceIssuePresent = false
    @State var hasSeenHealthyKanataService = false

    // Observer registration guards (prevent duplicate NotificationCenter registrations)
    @State var startupObserversInstalled = false
    @State var recoveryHandlersInstalled = false

    private var wizardInitialPage: WizardPage? {
        // Check for FDA restart restore point (used when app restarts for Full Disk Access)
        if let restorePoint = UserDefaults.standard.string(forKey: "KeyPath.WizardRestorePoint") {
            let restoreTime = UserDefaults.standard.double(forKey: "KeyPath.WizardRestoreTime")
            let timeSinceRestore = Date().timeIntervalSince1970 - restoreTime

            // Clear the restore point immediately
            UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestorePoint")
            UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestoreTime")

            // Only restore if within 5 minutes
            if timeSinceRestore < 300 {
                // Map string identifier to WizardPage
                let page = WizardPage.allCases.first { $0.rawValue == restorePoint }
                    ?? WizardPage.allCases.first { String(describing: $0) == restorePoint }
                if let page {
                    AppLogger.shared.log("🔄 [ContentView] Restoring wizard to \(page.displayName) after app restart")
                    return page
                }
            } else {
                AppLogger.shared.log("⏱️ [ContentView] Wizard restore point expired (\(Int(timeSinceRestore))s old)")
            }
        }

        if UserDefaults.standard.bool(forKey: "wizard_return_to_summary") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_summary")
            AppLogger.shared.log("✅ [ContentView] Permissions granted - returning to Summary")
            return .summary
        } else if UserDefaults.standard.bool(forKey: "wizard_return_to_input_monitoring") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_input_monitoring")
            return .inputMonitoring
        } else if UserDefaults.standard.bool(forKey: "wizard_return_to_accessibility") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_accessibility")
            return .accessibility
        }
        return nil
    }

    // MARK: - View Composition

    private var contentWithLayout: some View {
        ContentViewMainTab(
            stateController: stateController,
            recordingCoordinator: recordingCoordinator,
            kanataManager: kanataManager,
            showSetupBanner: $showSetupBanner,
            showingInstallationWizard: $showingInstallationWizard,
            onInputRecord: { handleInputRecordTap() },
            onOutputRecord: { handleOutputRecordTap() },
            onSave: { debouncedSave() },
            onOpenSystemStatus: { openSystemStatusSettings() },
            onShowMessage: { message in showStatusMessage(message: message) }
        )
        .padding(.horizontal)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(width: 500, alignment: .top)
        .onAppear {
            if FeatureFlags.allowOptionalWizard {
                Task { @MainActor in
                    let snapshot = await PermissionOracle.shared.currentSnapshot()
                    showSetupBanner = !snapshot.keyPath.hasAllPermissions
                    AppLogger.shared.log("🔄 [ContentView] Initial setup banner: keyPath.hasAllPermissions=\(snapshot.keyPath.hasAllPermissions), showBanner=\(showSetupBanner)")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Status message toast
            Group {
                if showStatusMessage {
                    StatusMessageView(
                        message: statusMessage,
                        isVisible: true
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                } else {
                    Color.clear
                        .frame(height: 0)
                }
            }
            .frame(height: showStatusMessage ? 80 : 0)
            .animation(.easeInOut(duration: 0.25), value: showStatusMessage)
        }
    }

    private var contentWithSheets: some View {
        contentWithLayout
            // Wizard is now shown in its own window via WizardWindowController
            .onChange(of: showingInstallationWizard) { _, showing in
                if showing {
                    WizardWindowController.shared.showWindow(
                        initialPage: wizardInitialPage,
                        kanataViewModel: kanataManager,
                        onDismiss: { [weak kanataManager] in
                            Task { @MainActor in
                                await kanataManager?.updateStatus()
                            }
                        }
                    )
                    // Reset the flag since window is now open
                    showingInstallationWizard = false
                }
            }
            .sheet(isPresented: $showingSimpleMods) {
                SimpleModsView(configPath: kanataManager.configPath)
                    .environmentObject(kanataManager)
            }
            .sheet(isPresented: $showingEmergencyStopDialog) {
                EmergencyStopDialog(isActivated: kanataManager.emergencyStopActivated)
            }
            .sheet(isPresented: $showingUninstallDialog) {
                UninstallKeyPathDialog()
                    .environmentObject(kanataManager)
            }
    }

    private var contentWithLifecycle: some View {
        contentWithSheets
            .onAppear {
                AppLogger.shared.log("🔍 [ContentView] onAppear called")
                AppLogger.shared.log(
                    "🏗️ [ContentView] Using shared SimpleRuntimeCoordinator"
                )

                // 🎯 Phase 3/4: Configure recording coordinator with underlying RuntimeCoordinator
                // Business logic components need the actual manager, not the ViewModel
                // NOTE: MainAppStateController.configure() is now called in App.init() to ensure
                // it's ready before the overlay starts observing health state.
                recordingCoordinator.configure(
                    kanataManager: kanataManager.underlyingManager,
                    statusHandler: { message in showStatusMessage(message: message) },
                    permissionProvider: permissionSnapshotProvider
                )

                // 🎯 Phase 3: Validation runs ONLY via notification at T+1000ms (after service starts at T+500ms)
                // Do NOT validate here - service isn't running yet, would show false errors

                // Observe phased startup notifications
                setupStartupObservers()

                // Check if we're returning from permission granting (Input Monitoring settings)
                let isReturningFromPermissionGrant = checkForPendingPermissionGrant()

                // Check if we're returning from an app restart for FDA permission
                if let restorePoint = UserDefaults.standard.string(forKey: "KeyPath.WizardRestorePoint") {
                    let restoreTime = UserDefaults.standard.double(forKey: "KeyPath.WizardRestoreTime")
                    let timeSinceRestore = Date().timeIntervalSince1970 - restoreTime
                    if timeSinceRestore < 300 { // Within 5 minutes
                        AppLogger.shared.log("🔄 [ContentView] Found wizard restore point '\(restorePoint)' - auto-opening wizard")
                        // Delay slightly to ensure UI is ready
                        Task { @MainActor in
                            try await Task.sleep(for: .milliseconds(500))
                            showingInstallationWizard = true
                        }
                    }
                }

                // Set up notification handlers for recovery actions
                setupRecoveryActionHandlers()

                // ContentView no longer forwards triggers directly; RecordingSection handles triggers via NotificationCenter

                // StartupCoordinator will publish auto-launch; if user returned from Settings,
                // we'll skip inside the observer.
                if isReturningFromPermissionGrant {
                    AppLogger.shared.log(
                        "🔧 [ContentView] Skipping auto-launch - returning from permission granting"
                    )
                    WizardLogger.shared.log("SKIPPING auto-launch (would reset wizard flag)")
                }

                if !hasCheckedRequirements {
                    AppLogger.shared.log("🔍 [ContentView] First time setup")
                    hasCheckedRequirements = true
                }

                // The StartupCoordinator will trigger emergency monitoring when safe.

                // Status monitoring now handled centrally by SimpleRuntimeCoordinator
                // Defer these UI state reads to the next runloop to avoid doing work
                // during the initial display cycle (prevents AppKit layout reentrancy).
                Task { @MainActor in
                    logInputDisabledReason()
                    logOutputDisabledReason()
                }

                // Trigger first-run validation on launch to drive the status indicator immediately
                Task {
                    await stateController.performInitialValidation()
                }
            }
            .onReceive(recordingCoordinator.$input.map(\.isRecording).removeDuplicates()) { isRecording in
                AppLogger.shared.log("🔁 [UI] isRecording changed -> \(isRecording)")
                logInputDisabledReason()
            }
            .onReceive(recordingCoordinator.$output.map(\.isRecording).removeDuplicates()) {
                isRecordingOutput in
                AppLogger.shared.log("🔁 [UI] isRecordingOutput changed -> \(isRecordingOutput)")
                logOutputDisabledReason()
            }
            .onReceive(recordingCoordinator.$isSequenceMode.removeDuplicates()) { mode in
                AppLogger.shared.log("🔁 [UI] isSequenceMode changed -> \(mode ? "sequence" : "chord")")
            }
            // Removed: onChange(of: kanataManager.showWizard) - legacy plumbing removed
            .onChange(of: kanataManager.lastConfigUpdate) { _, _ in
                // Skip toast on initial config load at app startup
                guard !isInitialConfigLoad else {
                    isInitialConfigLoad = false
                    return
                }

                // Show status message when config is updated externally
                showStatusMessage(message: "Key mappings updated")
                // NOTE: Do NOT trigger validation here - causes validation spam during startup
                // Validation happens on: app launch, wizard close, manual refresh only
            }
            .onDisappear {
                // Stop emergency monitoring when view disappears
                keyboardCapture?.stopEmergencyMonitoring()

                // Status monitoring handled centrally - no cleanup needed
            }
    }

    private var contentWithAlerts: some View {
        let base = contentWithLifecycle
            .alert("Emergency Stop Activated", isPresented: $showingEmergencyAlert) {
                Button("OK") {
                    showingEmergencyAlert = false
                }
            } message: {
                Text(
                    "The Kanata emergency stop sequence (Ctrl+Space+Esc) was detected. Kanata has been stopped for safety."
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWizard"))) { _ in
                showingInstallationWizard = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSimpleMods"))) { _ in
                showingSimpleMods = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowEmergencyStop"))) { _ in
                showingEmergencyStopDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUninstall"))) { _ in
                showingUninstallDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .keyPathUninstallCompleted)) { _ in
                showingUninstallDialog = false
                showStatusMessage(
                    message: "✅ KeyPath uninstalled\nYour config file was saved. You can quit now."
                )
            }
            // Note: Wizard close handling is now done in WizardWindowController.onDismiss
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                // Check if this is the wizard window closing
                if let window = notification.object as? NSWindow, window.title == "KeyPath Setup" {
                    // Trigger fresh validation to sync System indicator with wizard state
                    Task { @MainActor in
                        AppLogger.shared.log("🔄 [ContentView] Wizard window closed - triggering revalidation")
                        await stateController.revalidate()

                        // Refresh setup banner state after wizard closes
                        if FeatureFlags.allowOptionalWizard {
                            let snapshot = await PermissionOracle.shared.forceRefresh()
                            // Show banner if KeyPath lacks permissions - Kanata permissions are handled separately
                            showSetupBanner = !snapshot.keyPath.hasAllPermissions
                            AppLogger.shared.log("🔄 [ContentView] Setup banner refreshed: keyPath.hasAllPermissions=\(snapshot.keyPath.hasAllPermissions), showBanner=\(showSetupBanner)")
                        }
                    }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        startEmergencyMonitoringIfPossible()
                    }
                }
            }

        let primaryAlerts = base
            .alert("Kanata Installation Required", isPresented: $showingInstallAlert) {
                Button("Open Wizard") {
                    showingInstallationWizard = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Install the Kanata binary into /Library/KeyPath/bin using the Installation Wizard before recording shortcuts."
                )
            }
            .alert("Configuration Issue Detected", isPresented: $showingConfigCorruptionAlert) {
                Button("OK") { showingConfigCorruptionAlert = false }
                Button("View Diagnostics") {
                    showingConfigCorruptionAlert = false
                    openSystemStatusSettings()
                }
            } message: {
                Text(configCorruptionDetails)
            }
            .alert("Configuration Repair Failed", isPresented: $showingRepairFailedAlert) {
                Button("OK") { showingRepairFailedAlert = false }
                Button("Open Failed Config in Zed") {
                    showingRepairFailedAlert = false
                    Task { kanataManager.openFileInZed(failedConfigBackupPath) }
                }
                Button("View Diagnostics") {
                    showingRepairFailedAlert = false
                    openSystemStatusSettings()
                }
            } message: {
                Text(repairFailedDetails)
            }

        let serviceAlerts = primaryAlerts
            .alert("Kanata Not Running", isPresented: $showingKanataNotRunningAlert) {
                Button("OK") { showingKanataNotRunningAlert = false }
                Button("Open Wizard") {
                    showingKanataNotRunningAlert = false
                    showingInstallationWizard = true
                }
            } message: {
                Text(
                    "Cannot save configuration because the Kanata service is not running. Please start Kanata using the Installation Wizard."
                )
            }
            .alert("Kanata Service Stopped", isPresented: $showingKanataServiceStoppedAlert) {
                Button("Restart Service") {
                    showingKanataServiceStoppedAlert = false
                    Task {
                        let restarted = await kanataManager.restartKanata(
                            reason: "Service stopped alert"
                        )
                        if restarted {
                            showStatusMessage(message: "✅ Kanata restarted")
                        } else {
                            showStatusMessage(message: "❌ Failed to restart Kanata")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The remapping service stopped unexpectedly.")
            }

        return serviceAlerts
            .alert("Configuration Validation Failed", isPresented: $showingConfigValidationError) {
                Button("OK") { showingConfigValidationError = false }
                Button("View Diagnostics") {
                    showingConfigValidationError = false
                    openSystemStatusSettings()
                }
            } message: {
                Text(configValidationErrorMessage)
            }
            .sheet(isPresented: $showingValidationFailureModal, onDismiss: {
                validationFailureErrors = []
                validationFailureCopyText = ""
                aiRepairError = nil
                aiRepairBackupPath = nil
            }) {
                ValidationFailureDialog(
                    errors: validationFailureErrors,
                    configPath: kanataManager.configPath,
                    onCopyErrors: { copyValidationErrorsToClipboard() },
                    onOpenConfig: {
                        showingValidationFailureModal = false
                        openCurrentConfigInEditor()
                    },
                    onOpenDiagnostics: {
                        showingValidationFailureModal = false
                        openSystemStatusSettings()
                    },
                    onDismiss: {
                        showingValidationFailureModal = false
                    },
                    onRepairWithAI: KeychainService.shared.hasClaudeAPIKey ? { attemptAIConfigRepair() } : nil,
                    isRepairing: $isAttemptingAIRepair,
                    repairError: aiRepairError,
                    backupPath: aiRepairBackupPath
                )
                .customizeSheetWindow()
            }
            .onChange(of: kanataManager.lastError) { _, newError in
                AppLogger.shared.debug("🚨 [ContentView] onChange(lastError): newError = \(String(describing: newError))")
                if let error = newError {
                    // Show the full validation failure modal instead of a simple alert
                    // Split error message by newlines to show as separate error items
                    let errorLines = error.components(separatedBy: "\n").filter { !$0.isEmpty }
                    presentValidationFailureModal(errorLines)
                    // Clear the error so it doesn't re-trigger
                    kanataManager.lastError = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .configValidationFailed)) { notification in
                let errors = notification.userInfo?["errors"] as? [String] ?? []
                guard !errors.isEmpty else { return }
                presentValidationFailureModal(errors)
            }
            .onReceive(stateController.$issues) { newIssues in
                handleKanataServiceIssueChange(newIssues)
            }
    }

    var body: some View {
        contentWithAlerts
            .withToasts(toastManager)
    }

    // MARK: - Utilities

    func showStatusMessage(message: String) {
        // Cancel any existing timer
        statusMessageTask?.cancel()

        // Show message as toast
        statusMessage = message
        showStatusMessage = true

        // Errors get 10 seconds, success messages get 5 seconds
        let isError = message.contains("❌") || message.contains("⚠️")
        let duration: Double = isError ? 10 : 5

        statusMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            showStatusMessage = false
        }
    }

    func openSystemStatusSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsSystemStatus, object: nil)
    }

    func openRulesSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsRules, object: nil)
    }
}
