import AppKit
import Combine
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - File Navigation (1,125 lines)

//
// This file is the main recording UI. Use CMD+F to jump to:
//
// UI Sections:
//   - inputSection            Input key recording UI and controls
//   - outputSection           Output key recording UI and controls
//
// Recording Logic:
//   - handleInputRecordTap()  Start/stop input recording
//   - handleOutputRecordTap() Start/stop output recording
//   - inputDisabledReason()   Check why input recording is disabled
//   - outputDisabledReason()  Check why output recording is disabled
//
// Save & Validation:
//   - debouncedSave()         Debounced save trigger
//   - performSave()           Actual save logic
//   - handleSaveSuccess()     Success handling
//   - handleSaveError()       Error handling
//
// Startup & Status:
//   - setupStartupObservers()        Initialize observers
//   - checkForPendingPermissionGrant() Check permission state
//   - showStatusMessage()            Display status to user
//   - startEmergencyMonitoringIfPossible() Emergency recovery

struct ContentView: View {
    @State private var keyboardCapture: KeyboardCapture?
    @EnvironmentObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @Environment(\.permissionSnapshotProvider) private var permissionSnapshotProvider
    @StateObject private var stateController = MainAppStateController.shared // 🎯 Phase 3: Shared controller
    @StateObject private var recordingCoordinator = RecordingCoordinator()
    @State private var showingInstallationWizard = false {
        didSet {
            AppLogger.shared.log(
                "🎭 [ContentView] showingInstallationWizard changed from \(oldValue) to \(showingInstallationWizard)"
            )
        }
    }

    // Gate modal presentation until after early startup phases
    @State private var canPresentModals = false
    @State private var pendingShowWizardRequest = false

    @State private var hasCheckedRequirements = false
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var showingEmergencyAlert = false

    // Diagnostics view state (now navigates to Settings → System Status)
    // @State private var showingDiagnostics = false  // Removed: now uses Settings tab
    @State private var showingConfigCorruptionAlert = false
    @State private var configCorruptionDetails = ""
    @State private var configRepairSuccessful = false
    @State private var showingRepairFailedAlert = false
    @State private var repairFailedDetails = ""
    @State private var failedConfigBackupPath = ""
    @State private var showingInstallAlert = false
    @State private var showingKanataNotRunningAlert = false
    @State private var showingSimpleMods = false
    @State private var showingEmergencyStopDialog = false
    @State private var showingUninstallDialog = false
    @State private var toastManager = WizardToastManager()

    @State private var saveDebounceTimer: Timer?
    private let saveDebounceDelay: TimeInterval = 0.1

    @State private var statusMessageTask: Task<Void, Never>?

    @State private var lastInputDisabledReason: String = ""
    @State private var lastOutputDisabledReason: String = ""
    @State private var isInitialConfigLoad = true
    @State private var showSetupBanner = false
    @State private var showingConfigValidationError = false
    @State private var configValidationErrorMessage = ""
    @State private var showingValidationFailureModal = false
    @State private var validationFailureErrors: [String] = []
    @State private var validationFailureCopyText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if FeatureFlags.allowOptionalWizard, showSetupBanner {
                SetupBanner {
                    showingInstallationWizard = true
                }
                .padding(.horizontal, 8)
            }
            // Header
            let hasLayeredCollections = kanataManager.ruleCollections.contains {
                $0.isEnabled && $0.targetLayer != .base
            }
            ContentViewHeader(
                validator: stateController, // 🎯 Phase 3: New controller
                showingInstallationWizard: $showingInstallationWizard,
                onWizardRequest: { showingInstallationWizard = true },
                layerIndicatorVisible: hasLayeredCollections,
                currentLayerName: kanataManager.currentLayerName
            )

            // Recording Section (no solid wrapper; let glass show through)
            RecordingSection(
                coordinator: recordingCoordinator,
                onInputRecord: { handleInputRecordTap() },
                onOutputRecord: { handleOutputRecordTap() },
                onShowMessage: { message in showStatusMessage(message: message) }
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            // Save button - only visible when input OR output has content
            if recordingCoordinator.capturedInputSequence() != nil
                || recordingCoordinator.capturedOutputSequence() != nil {
                HStack {
                    Spacer()
                    Button(
                        action: { debouncedSave() },
                        label: {
                            HStack {
                                if kanataManager.saveStatus.isActive {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 16, height: 16)
                                    Text(kanataManager.saveStatus.message)
                                        .font(.caption)
                                } else {
                                    Text("Save")
                                }
                            }
                            .frame(minWidth: 100)
                        }
                    )
                    .buttonStyle(.borderedProminent)
                    .focusable(false) // Prevent keyboard activation on main page
                    .disabled(
                        recordingCoordinator.capturedInputSequence() == nil
                            || recordingCoordinator.capturedOutputSequence() == nil
                            || kanataManager.saveStatus.isActive
                    )
                    .accessibilityIdentifier("save-mapping-button")
                    .accessibilityLabel("Save key mapping")
                    .accessibilityHint("Save the input and output key mapping to your configuration")
                }
            }

            // Debug row removed in production UI

            // Emergency Stop Pause Card (similar to low battery pause)
            if kanataManager.emergencyStopActivated {
                EmergencyStopPauseCard(
                    onRestart: {
                        Task { @MainActor in
                            kanataManager.emergencyStopActivated = false
                            let restarted = await kanataManager.restartKanata(
                                reason: "Emergency stop recovery"
                            )
                            if !restarted {
                                showStatusMessage(
                                    message: "❌ Failed to restart Kanata after emergency stop"
                                )
                            }
                            await kanataManager.updateStatus()
                        }
                    }
                )
            }

            // Diagnostic Summary (show critical issues)
            if !kanataManager.diagnostics.isEmpty {
                let criticalIssues = kanataManager.diagnostics.filter {
                    $0.severity == .critical || $0.severity == .error
                }
                if !criticalIssues.isEmpty {
                    DiagnosticSummaryView(criticalIssues: criticalIssues) {
                        openSystemStatusSettings()
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 40)
        .padding(.bottom, 0)
        .frame(width: 500, alignment: .top)
        .onAppear {
            if FeatureFlags.allowOptionalWizard {
                Task { @MainActor in
                    let snapshot = await PermissionOracle.shared.currentSnapshot()
                    // Show banner if KeyPath lacks permissions - Kanata permissions are handled separately
                    // by the wizard and don't need to block the main UI
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
                        isVisible: true,
                        isError: statusMessage.contains("❌")
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
        .sheet(isPresented: $showingInstallationWizard) {
            // Determine initial page if we're returning from permission granting or app restart
            let initialPage: WizardPage? = {
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
            }()

            InstallationWizardView(initialPage: initialPage)
                .customizeSheetWindow() // Remove border and fix dark mode
                .onAppear {
                    AppLogger.shared.log("🔍 [ContentView] Installation wizard sheet is being presented")
                    if let page = initialPage {
                        AppLogger.shared.log(
                            "🔍 [ContentView] Starting at \(page.displayName) page after permission grant")
                    }
                    LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
                }
                .onDisappear {
                    // When wizard closes, call SimpleRuntimeCoordinator to handle the closure
                    AppLogger.shared.log("🎭 [ContentView] ========== WIZARD CLOSED ==========")
                    AppLogger.shared.log("🎭 [ContentView] Installation wizard sheet dismissed by user")
                    // onWizardClosed removed - legacy status plumbing is gone

                    Task {
                        // Note: validation triggered via .kp_startupRevalidate notification
                        // Do NOT trigger here to avoid duplicate validations
                        await kanataManager.updateStatus()
                    }

                    LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()
                }
                .environmentObject(kanataManager)
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
        .onAppear {
            AppLogger.shared.log("🔍 [ContentView] onAppear called")
            AppLogger.shared.log(
                "🏗️ [ContentView] Using shared SimpleRuntimeCoordinator"
            )

            // 🎯 Phase 3/4: Configure state controller and recording coordinator with underlying RuntimeCoordinator
            // Business logic components need the actual manager, not the ViewModel
            stateController.configure(with: kanataManager.underlyingManager)
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
            // we’ll skip inside the observer.
            if isReturningFromPermissionGrant {
                AppLogger.shared.log(
                    "🔧 [ContentView] Skipping auto-launch - returning from permission granting")
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSimpleMods"))) {
            _ in
            showingSimpleMods = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowEmergencyStop"))) { _ in
            showingEmergencyStopDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUninstall"))) {
            _ in
            showingUninstallDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .keyPathUninstallCompleted)) { _ in
            showingUninstallDialog = false
            showStatusMessage(
                message: "✅ KeyPath uninstalled\nYour config file was saved. You can quit now.")
        }
        .onChange(of: showingInstallationWizard) { _, showing in
            // When wizard closes, try to start emergency monitoring if we now have permissions
            if !showing {
                // Trigger fresh validation to sync System indicator with wizard state
                Task { @MainActor in
                    AppLogger.shared.log("🔄 [ContentView] Wizard closed - triggering revalidation")
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
                }
            )
            .customizeSheetWindow()
        }
        .onChange(of: kanataManager.lastError) { _, newError in
            if let error = newError {
                configValidationErrorMessage = error
                showingConfigValidationError = true
                // Clear the error so it doesn't re-trigger
                kanataManager.lastError = nil
            }
        }
        .withToasts(toastManager)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let toastMessage = kanataManager.toastMessage {
                    ToastView(message: toastMessage, type: kanataManager.toastType)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1000)
                }

                // Active rules indicator - appears below toast
                if !kanataManager.customRules.filter(\.isEnabled).isEmpty {
                    let activeCount = kanataManager.customRules.filter(\.isEnabled).count
                    Text("\(activeCount) active rule\(activeCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            openRulesSettings()
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .transition(.opacity)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: kanataManager.toastMessage)
        .animation(.easeInOut(duration: 0.2), value: kanataManager.customRules.count)
    }

    private func showStatusMessage(message: String) {
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

    private func openSystemStatusSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsSystemStatus, object: nil)
    }

    private func openRulesSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsRules, object: nil)
    }

    private func startEmergencyMonitoringIfPossible() {
        // Phase 2: JIT permission gate for emergency monitoring (AX)
        if FeatureFlags.useJustInTimePermissionRequests {
            Task { @MainActor in
                await PermissionGate.shared.checkAndRequestPermissions(
                    for: .emergencyStop,
                    onGranted: {
                        await startEmergencyMonitoringInternal()
                    },
                    onDenied: {
                        // No-op; user can try again later
                    }
                )
            }
            return
        }
        Task { @MainActor in
            await startEmergencyMonitoringInternal()
        }
    }

    @MainActor
    private func startEmergencyMonitoringInternal() async {
        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
            AppLogger.shared.log("🎹 [ContentView] KeyboardCapture initialized for emergency monitoring")
        }

        guard let capture = keyboardCapture else { return }

        capture.startEmergencyMonitoring { Task { @MainActor in
            let stopped = await kanataManager.stopKanata(reason: "Emergency stop hotkey")
            if stopped {
                AppLogger.shared.log("🛑 [EmergencyStop] Kanata service stopped via façade")
            } else {
                AppLogger.shared.warn("⚠️ [EmergencyStop] Failed to stop Kanata service via façade")
            }
            kanataManager.emergencyStopActivated = true
            showStatusMessage(message: "🚨 Emergency stop activated - Kanata stopped")
            UserNotificationService.shared.notifyLaunchFailure(
                .serviceFailure("Emergency stop activated"))
            showingEmergencyAlert = true
        } }
    }

    // MARK: - Startup Observers

    private func setupStartupObservers() {
        NotificationCenter.default.addObserver(forName: .kp_startupWarm, object: nil, queue: .main) {
            _ in
            AppLogger.shared.log("🚦 [Startup] Warm phase")
            // Lightweight warm-ups (noop for now)
        }

        NotificationCenter.default.addObserver(
            forName: .kp_startupAutoLaunch, object: nil, queue: .main
        ) { _ in
            AppLogger.shared.log("🚦 [Startup] AutoLaunch phase")
            Task { @MainActor in
                // Respect permission-grant return to avoid resetting wizard state
                let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()
                if !result.shouldRestart {
                    AppLogger.shared.log("🚀 [ContentView] Starting auto-launch sequence (coordinated)")
                    let success = await kanataManager.startKanata(reason: "Auto-launch phase")
                    if success {
                        AppLogger.shared.log("✅ [ContentView] Auto-launch sequence completed")
                    } else {
                        AppLogger.shared.error("❌ [ContentView] Auto-launch failed via KanataService")
                    }
                    await kanataManager.updateStatus()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kp_startupEmergencyMonitor, object: nil, queue: .main
        ) { _ in
            AppLogger.shared.log("🚦 [Startup] Emergency monitor phase")
            // Emergency monitoring setup is now handled elsewhere
        }

        // 🎯 Phase 3: Single notification handler for validation (startup + wizard close)
        NotificationCenter.default.addObserver(
            forName: .kp_startupRevalidate, object: nil, queue: .main
        ) { [stateController] _ in
            AppLogger.shared.log("🎯 [Phase 3] Validation requested via notification")
            Task { @MainActor in
                // Use performInitialValidation - handles both first run (waits for service) and subsequent runs
                await stateController.performInitialValidation()
            }
        }

        // Revalidate when wizard closes (system state may have changed)
        NotificationCenter.default.addObserver(forName: .wizardClosed, object: nil, queue: .main) {
            [stateController] _ in
            AppLogger.shared.log("🔄 [ContentView] Wizard closed notification - triggering revalidation")
            Task { @MainActor in
                await stateController.revalidate()
            }
        }
    }

    // Status monitoring functions removed - now handled centrally by SimpleRuntimeCoordinator

    /// Check if we're returning from granting permissions using the unified coordinator
    /// Returns true if we detected a pending permission grant restart, false otherwise
    @discardableResult
    private func checkForPendingPermissionGrant() -> Bool {
        let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()

        if result.shouldRestart, let permissionType = result.permissionType {
            AppLogger.shared.log(
                "🔧 [ContentView] Detected return from \(permissionType.displayName) permission granting")

            // Perform the permission restart using the coordinator
            PermissionGrantCoordinator.shared.performPermissionRestart(
                for: permissionType,
                kanataManager: kanataManager.underlyingManager // Phase 4: Business logic needs underlying manager
            ) { _ in
                // Show wizard after service restart completes to display results
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    // Reopen wizard to the appropriate permission page
                    PermissionGrantCoordinator.shared.reopenWizard(for: permissionType)
                }
            }

            return true // We detected and are handling the permission grant restart
        }

        return false // No pending permission grant restart
    }

    /// Set up notification handlers for recovery actions
    private func setupRecoveryActionHandlers() {
        // Handle opening installation wizard
        NotificationCenter.default.addObserver(
            forName: .openInstallationWizard, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in showingInstallationWizard = true }
        }

        // Handle resetting to safe config
        NotificationCenter.default.addObserver(forName: .resetToSafeConfig, object: nil, queue: .main) {
            _ in
            Task { @MainActor in
                _ = await kanataManager.createDefaultUserConfigIfMissing()
                await stateController.revalidate()
                showStatusMessage(message: "✅ Configuration reset to safe defaults")
            }
        }

        // Handle user feedback from PermissionGrantCoordinator
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowUserFeedback"), object: nil, queue: .main
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                Task { @MainActor in showStatusMessage(message: message) }
            }
        }
    }

    private func debouncedSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) {
            _ in
            Task { await performSave() }
        }
    }

    private func performSave() async {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil

        // Check running state via KanataService
        var serviceState = await kanataManager.currentServiceState()

        // If Kanata is not running but we're recording, stop recording first (resumes Kanata)
        if !serviceState.isRunning,
           recordingCoordinator.isInputRecording() || recordingCoordinator.isOutputRecording() {
            AppLogger.shared.log("🔄 [ContentView] Kanata paused during recording - resuming before save")
            await MainActor.run {
                recordingCoordinator.stopAllRecording()
            }

            // Wait briefly for Kanata to resume
            try? await Task.sleep(for: .milliseconds(500)) // 500ms
            serviceState = await kanataManager.currentServiceState()
        }

        // Pre-flight check: Ensure kanata is running before attempting save
        guard serviceState.isRunning else {
            AppLogger.shared.log("⚠️ [ContentView] Cannot save - kanata service is not running")
            await MainActor.run {
                showingKanataNotRunningAlert = true
            }
            return
        }

        await recordingCoordinator.saveMapping(
            kanataManager: kanataManager.underlyingManager, // Phase 4: Business logic needs underlying manager
            existingRules: kanataManager.customRules,
            onSuccess: { message in handleSaveSuccess(message) },
            onError: { error in handleSaveError(error) }
        )
    }

    private func handleSaveSuccess(_ message: String) {
        showStatusMessage(message: message)
    }

    private func handleSaveError(_ error: Error) {
        // Handle coordination errors - invalid state (missing input/output)
        if case KeyPathError.coordination(.invalidState) = error {
            showStatusMessage(message: "❌ Please capture both input and output keys first")
            return
        }

        // Handle coordination errors - recording failed (validation errors like self-reference)
        if case let KeyPathError.coordination(.recordingFailed(reason)) = error {
            showStatusMessage(message: "❌ Recording failed: \(reason)")
            return
        }

        // Handle TCP connectivity errors (before config validation to avoid false positives)
        if case let KeyPathError.configuration(.loadFailed(reason)) = error {
            let reasonLower = reason.lowercased()
            if reasonLower.contains("tcp"),
               reasonLower.contains("required") || reasonLower.contains("unresponsive")
               || reasonLower.contains("failed") || reasonLower.contains("reload") {
                // TCP connectivity issues - open wizard directly to Communication page
                showStatusMessage(message: "⚠️ Service connection failed - opening setup wizard...")
                Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(500))
                    NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
                }
                return
            }
        }

        // Handle configuration validation errors with detailed feedback
        if case let KeyPathError.configuration(.validationFailed(errors)) = error {
            presentValidationFailureModal(errors)
            showStatusMessage(message: "❌ Configuration validation failed")
            return
        }

        // Handle configuration corruption with repair details
        if case let KeyPathError.configuration(.corruptedFormat(details)) = error {
            configCorruptionDetails = """
            Configuration corruption detected:

            \(details)

            KeyPath attempted automatic repair. If the repair was successful, your mapping has been saved with a corrected configuration.
            """
            configRepairSuccessful = false
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "⚠️ Config repaired automatically")
            return
        }

        // Handle repair failures
        if case let KeyPathError.configuration(.repairFailed(reason)) = error {
            configCorruptionDetails = """
            Configuration repair failed:

            \(reason)

            A safe fallback configuration has been applied. Your system should continue working with basic functionality.
            """
            configRepairSuccessful = false
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "❌ Config repair failed - using safe fallback")
            return
        }

        // Generic error handling for all other cases
        // Open wizard to help diagnose and fix the issue
        let errorDesc = error.localizedDescription
        showStatusMessage(message: "⚠️ \(errorDesc)")
        Task { @MainActor in
            try await Task.sleep(for: .seconds(1))
            NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
        }
    }

    private func presentValidationFailureModal(_ errors: [String]) {
        let state = ValidationFailureState(rawErrors: errors)
        validationFailureErrors = state.errors
        validationFailureCopyText = state.copyText
        showingValidationFailureModal = true
    }

    private func copyValidationErrorsToClipboard() {
        guard !validationFailureErrors.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let combined = validationFailureCopyText.isEmpty ? validationFailureErrors.joined(separator: "\n") : validationFailureCopyText
        pasteboard.setString(combined, forType: .string)
    }

    private func openCurrentConfigInEditor() {
        kanataManager.openFileInZed(kanataManager.configPath)
    }

    private func handleInputRecordTap() {
        if recordingCoordinator.isInputRecording() {
            recordingCoordinator.toggleInputRecording()
            return
        }

        guard kanataManager.isCompletelyInstalled() else {
            showingInstallAlert = true
            return
        }

        // Stop output recording if active before starting input
        if recordingCoordinator.isOutputRecording() {
            recordingCoordinator.toggleOutputRecording()
        }

        recordingCoordinator.toggleInputRecording()
    }

    private func handleOutputRecordTap() {
        if recordingCoordinator.isOutputRecording() {
            recordingCoordinator.toggleOutputRecording()
            return
        }

        guard kanataManager.isCompletelyInstalled() else {
            showingInstallAlert = true
            return
        }

        // Stop input recording if active before starting output
        if recordingCoordinator.isInputRecording() {
            recordingCoordinator.toggleInputRecording()
        }

        recordingCoordinator.toggleOutputRecording()
    }

    private func inputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled(), !recordingCoordinator.isInputRecording() {
            reasons.append("notInstalled")
        }
        if NSApp?.isActive == false {
            reasons.append("appNotActive")
        }
        if NSApp?.keyWindow == nil {
            reasons.append("noKeyWindow")
        }
        return reasons.isEmpty ? "enabled" : reasons.joined(separator: "+")
    }

    private func outputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled(), !recordingCoordinator.isOutputRecording() {
            reasons.append("notInstalled")
        }
        if NSApp?.isActive == false {
            reasons.append("appNotActive")
        }
        if NSApp?.keyWindow == nil {
            reasons.append("noKeyWindow")
        }
        return reasons.isEmpty ? "enabled" : reasons.joined(separator: "+")
    }

    private func logInputDisabledReason() {
        let reason = inputDisabledReason()
        if reason != lastInputDisabledReason {
            lastInputDisabledReason = reason
            AppLogger.shared.log("🧭 [UI] Input record button state: \(reason)")
        }
    }

    private func logOutputDisabledReason() {
        let reason = outputDisabledReason()
        if reason != lastOutputDisabledReason {
            lastOutputDisabledReason = reason
            AppLogger.shared.log("🧭 [UI] Output record button state: \(reason)")
        }
    }
}

private struct ValidationFailureDialog: View {
    let errors: [String]
    let configPath: String
    let onCopyErrors: () -> Void
    let onOpenConfig: () -> Void
    let onOpenDiagnostics: () -> Void
    let onDismiss: () -> Void

    private var normalizedErrors: [String] {
        errors.isEmpty
            ? ["Kanata returned an unknown validation error."]
            : errors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configuration Validation Failed")
                        .font(.title2.weight(.semibold))
                    Text("Kanata refused to load the generated config. KeyPath left the previous configuration in place until you fix the issues below.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(normalizedErrors.enumerated()), id: \.offset) { index, error in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.body.bold())
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180, maxHeight: 260)

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(configPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                Button("Copy Errors") {
                    onCopyErrors()
                }
                Button("Open Config in Zed") {
                    onOpenConfig()
                }
                Spacer()
                Button("Diagnostics") {
                    onOpenDiagnostics()
                }
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minWidth: 520, idealWidth: 580, maxWidth: 640)
        .padding(24)
    }
}

#Preview {
    let manager = RuntimeCoordinator()
    let viewModel = KanataViewModel(manager: manager)
    ContentView()
        .environmentObject(viewModel)
}
