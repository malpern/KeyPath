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
    @StateObject private var stateController = MainAppStateController() // 🎯 Phase 3: New controller
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

    // Enhanced error handling
    @State private var enhancedErrorInfo: ErrorInfo?

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

    @State private var statusMessageTimer: DispatchWorkItem?

    @State private var lastInputDisabledReason: String = ""
    @State private var lastOutputDisabledReason: String = ""
    @State private var isInitialConfigLoad = true
    @State private var showSetupBanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if FeatureFlags.allowOptionalWizard, showSetupBanner {
                SetupBanner {
                    showingInstallationWizard = true
                }
                .padding(.horizontal, 8)
            }
            // Header
            let hasLayeredCollections = kanataManager.ruleCollections.contains { $0.isEnabled && $0.targetLayer != .base }
            ContentViewHeader(
                validator: stateController, // 🎯 Phase 3: New controller
                showingInstallationWizard: $showingInstallationWizard,
                onWizardRequest: { kanataManager.requestWizardPresentation() },
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

            HStack {
                Spacer()
                Button(action: { debouncedSave() }, label: {
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
                })
                .buttonStyle(.borderedProminent)
                .disabled(recordingCoordinator.capturedInputSequence() == nil ||
                    recordingCoordinator.capturedOutputSequence() == nil ||
                    kanataManager.saveStatus.isActive)
                .accessibilityIdentifier("save-mapping-button")
                .accessibilityLabel("Save key mapping")
                .accessibilityHint("Save the input and output key mapping to your configuration")
            }

            // Debug row removed in production UI

            // Enhanced Error Display - persistent and actionable
            EnhancedErrorHandler(errorInfo: $enhancedErrorInfo)

            // Emergency Stop Pause Card (similar to low battery pause)
            if kanataManager.emergencyStopActivated {
                EmergencyStopPauseCard(
                    onRestart: {
                        Task { @MainActor in
                            kanataManager.emergencyStopActivated = false
                            await kanataManager.startKanata()
                            await kanataManager.updateStatus()
                        }
                    }
                )
            }

            // Legacy Error Section (only show if there's an error and no enhanced error)
            if let error = kanataManager.lastError, !kanataManager.isRunning, enhancedErrorInfo == nil {
                ErrorSection(
                    kanataManager: kanataManager, showingInstallationWizard: $showingInstallationWizard,
                    error: error
                )
            }

            // Diagnostic Summary (show critical issues)
            if !kanataManager.diagnostics.isEmpty {
                let criticalIssues = kanataManager.diagnostics.filter { $0.severity == .critical || $0.severity == .error }
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
                    showSetupBanner = !snapshot.isSystemReady
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Fixed 80px space at bottom for toast - always present, stable layout
            Group {
                if showStatusMessage, !statusMessage.contains("❌") {
                    StatusMessageView(message: statusMessage, isVisible: true)
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
            // Determine initial page if we're returning from permission granting
            let initialPage: WizardPage? = {
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
                        AppLogger.shared.log("🔍 [ContentView] Starting at \(page.displayName) page after permission grant")
                    }
                }
                .onDisappear {
                    // When wizard closes, call SimpleKanataManager to handle the closure
                    AppLogger.shared.log("🎭 [ContentView] ========== WIZARD CLOSED ==========")
                    AppLogger.shared.log("🎭 [ContentView] Installation wizard sheet dismissed by user")
                    AppLogger.shared.log("🎭 [ContentView] Calling kanataManager.onWizardClosed()")

                    Task {
                        await kanataManager.onWizardClosed()
                        // Note: validation triggered via .kp_startupRevalidate notification
                        // Do NOT trigger here to avoid duplicate validations
                        await kanataManager.updateStatus()
                    }
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
        }
        .onAppear {
            AppLogger.shared.log("🔍 [ContentView] onAppear called")
            AppLogger.shared.log(
                "🏗️ [ContentView] Using shared SimpleKanataManager, initial showWizard: \(kanataManager.showWizard)"
            )

            // 🎯 Phase 3/4: Configure state controller and recording coordinator with underlying KanataManager
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

            // Set up notification handlers for recovery actions
            setupRecoveryActionHandlers()

            // ContentView no longer forwards triggers directly; RecordingSection handles triggers via NotificationCenter

            // StartupCoordinator will publish auto-launch; if user returned from Settings,
            // we’ll skip inside the observer.
            if isReturningFromPermissionGrant {
                AppLogger.shared.log("🔧 [ContentView] Skipping auto-launch - returning from permission granting")
                WizardLogger.shared.log("SKIPPING auto-launch (would reset wizard flag)")
            }

            if !hasCheckedRequirements {
                AppLogger.shared.log("🔍 [ContentView] First time setup")
                hasCheckedRequirements = true
            }

            // The StartupCoordinator will trigger emergency monitoring when safe.

            // Status monitoring now handled centrally by SimpleKanataManager
            // Defer these UI state reads to the next runloop to avoid doing work
            // during the initial display cycle (prevents AppKit layout reentrancy).
            DispatchQueue.main.async {
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
        .onReceive(recordingCoordinator.$output.map(\.isRecording).removeDuplicates()) { isRecordingOutput in
            AppLogger.shared.log("🔁 [UI] isRecordingOutput changed -> \(isRecordingOutput)")
            logOutputDisabledReason()
        }
        .onReceive(recordingCoordinator.$isSequenceMode.removeDuplicates()) { mode in
            AppLogger.shared.log("🔁 [UI] isSequenceMode changed -> \(mode ? "sequence" : "chord")")
        }
        .onChange(of: kanataManager.showWizard) { _, shouldShow in
            AppLogger.shared.log("🔍 [ContentView] showWizard changed to: \(shouldShow)")
            AppLogger.shared.log(
                "🔍 [ContentView] Current kanataManager state: \(kanataManager.currentState.rawValue)"
            )
            AppLogger.shared.log(
                "🔍 [ContentView] Current errorReason: \(kanataManager.errorReason ?? "nil")")

            if shouldShow, !canPresentModals {
                pendingShowWizardRequest = true
                AppLogger.shared.log("🔍 [ContentView] Deferring wizard presentation until modals are allowed")
                return
            }

            showingInstallationWizard = shouldShow
            AppLogger.shared.log("🔍 [ContentView] showingInstallationWizard set to: \(showingInstallationWizard)")
        }
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
            showStatusMessage(message: "✅ KeyPath uninstalled\nYour config file was saved. You can quit now.")
        }
        .onChange(of: showingInstallationWizard) { _, showing in
            // When wizard closes, try to start emergency monitoring if we now have permissions
            if !showing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
            Text("Install the Kanata binary into /Library/KeyPath/bin using the Installation Wizard before recording shortcuts.")
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
                kanataManager.openFileInZed(failedConfigBackupPath)
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
            Text("Cannot save configuration because the Kanata service is not running. Please start Kanata using the Installation Wizard.")
        }
        .withToasts(toastManager)
    }

    private func showStatusMessage(message: String) {
        // Check if this is an error message
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            // Use enhanced error handler for errors
            let errorText = message.replacingOccurrences(of: "❌ ", with: "")
            let error = NSError(domain: "KeyPath", code: -1, userInfo: [NSLocalizedDescriptionKey: errorText])

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                enhancedErrorInfo = ErrorInfo.from(error)
            }
        } else {
            // Cancel any existing timer to ensure consistent 5-second display
            statusMessageTimer?.cancel()

            // Use traditional status message for success/info messages
            statusMessage = message
            showStatusMessage = true

            // Hide after 5 seconds with simple animation
            let workItem = DispatchWorkItem {
                showStatusMessage = false
            }
            statusMessageTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        }
    }

    private func openSystemStatusSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsSystemStatus, object: nil)
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

        capture.startEmergencyMonitoring {
            Task { @MainActor in
                await kanataManager.stopKanata()
                kanataManager.emergencyStopActivated = true
                showStatusMessage(message: "🚨 Emergency stop activated - Kanata stopped")
                UserNotificationService.shared.notifyLaunchFailure(.serviceFailure("Emergency stop activated"))
                showingEmergencyAlert = true
            }
        }
    }

    // MARK: - Startup Observers

    private func setupStartupObservers() {
        NotificationCenter.default.addObserver(forName: .kp_startupWarm, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] Warm phase")
            // Lightweight warm-ups (noop for now)
        }

        NotificationCenter.default.addObserver(forName: .kp_startupAutoLaunch, object: nil, queue: .main) { [kanataManager] _ in
            AppLogger.shared.log("🚦 [Startup] AutoLaunch phase")
            Task { @MainActor in
                // Respect permission-grant return to avoid resetting wizard state
                let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()
                if !result.shouldRestart {
                    AppLogger.shared.log("🚀 [ContentView] Starting auto-launch sequence (coordinated)")
                    await kanataManager.startAutoLaunch(presentWizardOnFailure: false)
                    AppLogger.shared.log("✅ [ContentView] Auto-launch sequence completed")
                }
            }
        }

        NotificationCenter.default.addObserver(forName: .kp_startupEmergencyMonitor, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] Emergency monitor phase")
            // Emergency monitoring setup is now handled elsewhere
        }

        // 🎯 Phase 3: Single notification handler for validation (startup + wizard close)
        NotificationCenter.default.addObserver(forName: .kp_startupRevalidate, object: nil, queue: .main) { [stateController] _ in
            AppLogger.shared.log("🎯 [Phase 3] Validation requested via notification")
            Task { @MainActor in
                // Use performInitialValidation - handles both first run (waits for service) and subsequent runs
                await stateController.performInitialValidation()
            }
        }

        // Invalidate validation cooldown when wizard closes (system state may have changed)
        NotificationCenter.default.addObserver(forName: .wizardClosed, object: nil, queue: .main) { [stateController] _ in
            AppLogger.shared.log("🔄 [ContentView] Wizard closed - invalidating validation cooldown")
            Task { @MainActor in
                stateController.invalidateValidationCooldown()
            }
        }
    }

    // Status monitoring functions removed - now handled centrally by SimpleKanataManager

    /// Check if we're returning from granting permissions using the unified coordinator
    /// Returns true if we detected a pending permission grant restart, false otherwise
    @discardableResult
    private func checkForPendingPermissionGrant() -> Bool {
        let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()

        if result.shouldRestart, let permissionType = result.permissionType {
            AppLogger.shared.log("🔧 [ContentView] Detected return from \(permissionType.displayName) permission granting")

            // Perform the permission restart using the coordinator
            PermissionGrantCoordinator.shared.performPermissionRestart(
                for: permissionType,
                kanataManager: kanataManager.underlyingManager // Phase 4: Business logic needs underlying manager
            ) { _ in
                // Show wizard after service restart completes to display results
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Reopen wizard to the appropriate permission page
                    PermissionGrantCoordinator.shared.reopenWizard(
                        for: permissionType,
                        kanataManager: kanataManager.underlyingManager // Phase 4: Business logic needs underlying manager
                    )
                }
            }

            return true // We detected and are handling the permission grant restart
        }

        return false // No pending permission grant restart
    }

    /// Set up notification handlers for recovery actions
    private func setupRecoveryActionHandlers() {
        // Handle opening installation wizard
        NotificationCenter.default.addObserver(forName: .openInstallationWizard, object: nil, queue: .main) { _ in
            Task { @MainActor in showingInstallationWizard = true }
        }

        // Handle resetting to safe config
        NotificationCenter.default.addObserver(forName: .resetToSafeConfig, object: nil, queue: .main) { _ in
            Task { @MainActor in
                _ = await kanataManager.createDefaultUserConfigIfMissing()
                await kanataManager.updateStatus()
                showStatusMessage(message: "✅ Configuration reset to safe defaults")
            }
        }

        // Handle opening diagnostics
        NotificationCenter.default.addObserver(forName: .openDiagnostics, object: nil, queue: .main) { _ in
            // This would open a diagnostics window - implementation depends on app structure
            Task { @MainActor in showStatusMessage(message: "ℹ️ Opening diagnostics view...") }
        }

        // Handle user feedback from PermissionGrantCoordinator
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ShowUserFeedback"), object: nil, queue: .main) { notification in
            if let message = notification.userInfo?["message"] as? String {
                Task { @MainActor in showStatusMessage(message: message) }
            }
        }
    }

    private func debouncedSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) { _ in
            Task { await performSave() }
        }
    }

    private func performSave() async {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil

        // If Kanata is not running but we're recording, stop recording first (resumes Kanata)
        if !kanataManager.isRunning, recordingCoordinator.isInputRecording() || recordingCoordinator.isOutputRecording() {
            AppLogger.shared.log("🔄 [ContentView] Kanata paused during recording - resuming before save")
            await MainActor.run {
                recordingCoordinator.stopAllRecording()
            }

            // Wait briefly for Kanata to resume
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        // Pre-flight check: Ensure kanata is running before attempting save
        guard kanataManager.isRunning else {
            AppLogger.shared.log("⚠️ [ContentView] Cannot save - kanata service is not running")
            await MainActor.run {
                showingKanataNotRunningAlert = true
            }
            return
        }

        await recordingCoordinator.saveMapping(
            kanataManager: kanataManager.underlyingManager, // Phase 4: Business logic needs underlying manager
            onSuccess: { message in handleSaveSuccess(message) },
            onError: { error in handleSaveError(error) }
        )
    }

    private func handleSaveSuccess(_ message: String) {
        showStatusMessage(message: message)
    }

    private func handleSaveError(_ error: Error) {
        // Handle coordination errors
        if case KeyPathError.coordination(.invalidState) = error {
            showStatusMessage(message: "❌ Please capture both input and output keys first")
            return
        }

        // Handle TCP connectivity errors (before config validation to avoid false positives)
        if case let KeyPathError.configuration(.loadFailed(reason)) = error {
            let reasonLower = reason.lowercased()
            if reasonLower.contains("tcp"), reasonLower.contains("required") || reasonLower.contains("unresponsive") || reasonLower.contains("failed") || reasonLower.contains("reload") {
                // Use enhanced error handler for TCP connectivity issues
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    enhancedErrorInfo = ErrorInfo.from(error)
                }
                return
            }
        }

        // Handle configuration validation errors with detailed feedback
        if case let KeyPathError.configuration(.validationFailed(errors)) = error {
            configCorruptionDetails = """
            Configuration validation failed:

            \(errors.joined(separator: "\n"))
            """
            showingConfigCorruptionAlert = true
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
        // Use enhanced error handler for proper error classification
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            enhancedErrorInfo = ErrorInfo.from(error)
        }
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

struct ContentViewHeader: View {
    @ObservedObject var validator: MainAppStateController // 🎯 Phase 3: New controller
    @Binding var showingInstallationWizard: Bool
    let onWizardRequest: () -> Void
    let layerIndicatorVisible: Bool
    let currentLayerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: {
                    AppLogger.shared.log(
                        "🔧 [ContentViewHeader] Keyboard icon tapped - launching installation wizard")
                    showingInstallationWizard = true
                }, label: {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.blue)
                })
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("launch-installation-wizard-button")
                .accessibilityLabel("Launch Installation Wizard")
                .accessibilityHint("Click to open the KeyPath installation and setup wizard")

                Text("KeyPath")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize()

                Spacer()

                // System Status Indicator in top-right
                SystemStatusIndicator(
                    validator: validator,
                    showingWizard: $showingInstallationWizard,
                    onClick: onWizardRequest
                )
                .frame(height: 28, alignment: .bottom) // lock indicator height to keep row baseline stable
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 36, alignment: .bottom) // Lock header row height to prevent spacing shifts

            Text("Record keyboard shortcuts and create custom key mappings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: 2)

            if layerIndicatorVisible {
                LayerStatusIndicator(currentLayerName: currentLayerName)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Transparent background - no glass header
    }
}

struct LayerStatusIndicator: View {
    let currentLayerName: String

    private var isBaseLayer: Bool {
        currentLayerName.caseInsensitiveCompare("base") == .orderedSame
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isBaseLayer ? Color.secondary.opacity(0.4) : Color.accentColor)
                .frame(width: 8, height: 8)
            Text(isBaseLayer ? "Base Layer" : "\(currentLayerName) Layer")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current layer")
        .accessibilityValue(isBaseLayer ? "Base" : currentLayerName)
    }
}

struct RecordingSection: View {
    @ObservedObject var coordinator: RecordingCoordinator
    let onInputRecord: () -> Void
    let onOutputRecord: () -> Void
    let onShowMessage: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            inputSection
            outputSection
        }
        .onAppear { coordinator.requestPlaceholders() }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input Key")
                .font(.headline)
                .accessibilityIdentifier("input-key-label")

            HStack {
                Text(coordinator.inputDisplayText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .appFieldGlass(radius: 8, opacity: coordinator.isInputRecording() ? 0.16 : 0.06)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(coordinator.isInputRecording() ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .accessibilityIdentifier("input-key-display")
                    .accessibilityLabel("Input key")
                    .accessibilityValue(
                        coordinator.inputDisplayText().isEmpty
                            ? "No key recorded"
                            : "Key: \(coordinator.inputDisplayText())"
                    )
                    .id("\(coordinator.isInputRecording())-\(coordinator.inputDisplayText())")

                Button(action: {
                    AppLogger.shared.log("🖱️ [UI] Input record button tapped (isRecording=\(coordinator.isInputRecording()))")
                    onInputRecord()
                }, label: {
                    Image(systemName: coordinator.inputButtonIcon())
                        .font(.title2)
                })
                .buttonStyle(.plain)
                .frame(height: 44)
                .frame(minWidth: 44)
                .appSolidGlassButton(tint: .accentColor, radius: 8)
                .foregroundColor(.white)
                .cornerRadius(8)
                .accessibilityIdentifier("input-key-record-button")
                .accessibilityLabel(coordinator.isInputRecording() ? "Stop recording input key" : "Record input key")
                .id(coordinator.isInputRecording())
                .accessibilityHint(
                    coordinator.isInputRecording()
                        ? "Stop recording the input key"
                        : "Start recording a key to remap"
                )
            }
        }
        .padding()
        // Transparent background for input section
        .accessibilityIdentifier("input-recording-section")
        .accessibilityLabel("Input key recording section")
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Key")
                .font(.headline)
                .accessibilityIdentifier("output-key-label")

            HStack {
                Text(coordinator.outputDisplayText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .appFieldGlass(radius: 8, opacity: coordinator.isOutputRecording() ? 0.16 : 0.06)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(coordinator.isOutputRecording() ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .accessibilityIdentifier("output-key-display")
                    .accessibilityLabel("Output key")
                    .accessibilityValue(
                        coordinator.outputDisplayText().isEmpty
                            ? "No key recorded"
                            : "Key: \(coordinator.outputDisplayText())"
                    )

                Button(action: {
                    AppLogger.shared.log("🖱️ [UI] Output record button tapped (isRecording=\(coordinator.isOutputRecording()))")
                    onOutputRecord()
                }, label: {
                    Image(systemName: coordinator.outputButtonIcon())
                        .font(.title2)
                })
                .buttonStyle(.plain)
                .frame(height: 44)
                .frame(minWidth: 44)
                .appSolidGlassButton(tint: .accentColor, radius: 8)
                .foregroundColor(.white)
                .cornerRadius(8)
                .accessibilityIdentifier("output-key-record-button")
                .accessibilityLabel(coordinator.isOutputRecording() ? "Stop recording output key" : "Record output key")
                .accessibilityHint(
                    coordinator.isOutputRecording()
                        ? "Stop recording the output key"
                        : "Start recording the replacement key"
                )
            }
        }
        .padding()
        // Transparent background for output section
        .accessibilityIdentifier("output-recording-section")
        .accessibilityLabel("Output key recording section")
    }
}

struct ErrorSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @Binding var showingInstallationWizard: Bool
    let error: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.headline)

                Text("KeyPath Error")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("Fix Issues") {
                    Task {
                        AppLogger.shared.log(
                            "🔄 [UI] Fix Issues button clicked - attempting to fix configuration and restart")

                        // Create a default user config if missing
                        let created = await kanataManager.createDefaultUserConfigIfMissing()

                        if created {
                            await MainActor.run {
                                kanataManager.lastError = nil
                            }
                            AppLogger.shared.log(
                                "✅ [UI] Created default config at ~/Library/Application Support/KeyPath/keypath.kbd"
                            )
                        } else {
                            // Still not fixed – open wizard to guide the user
                            showingInstallationWizard = true
                        }

                        // Try starting after config creation
                        await kanataManager.startKanata()
                        await kanataManager.updateStatus()
                        AppLogger.shared.log(
                            "🔄 [UI] Fix Issues completed - service status: \(kanataManager.isRunning)")
                    }
                    // Only open wizard above if needed
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

struct DiagnosticSummarySection: View {
    let criticalIssues: [KanataDiagnostic]
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    let onViewDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.red)
                    .font(.headline)

                Text("System Issues Detected")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("View Details") {
                    onViewDetails()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(criticalIssues.prefix(3).indices, id: \.self) { index in
                    let issue = criticalIssues[index]
                    HStack {
                        Text(issue.severity.emoji)
                        Text(issue.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if issue.canAutoFix {
                            Button("Fix") {
                                Task {
                                    await kanataManager.autoFixDiagnostic(issue)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }

                if criticalIssues.count > 3 {
                    Text("... and \(criticalIssues.count - 3) more issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

struct StatusMessageView: View {
    let message: String
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon with white circle background
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)

                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(messageTitle)
                    .font(.headline)
                    .foregroundColor(.white)

                if let subtitle = messageSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .transition(.opacity)
    }

    private var messageTitle: String {
        message.components(separatedBy: "\n").first ?? message
    }

    private var messageSubtitle: String? {
        let lines = message.components(separatedBy: "\n")
        return lines.count > 1 ? lines[1] : nil
    }

    private var iconName: String {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            "xmark.circle.fill"
        } else if message.contains("paused") {
            "pause.circle.fill"
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") {
            "exclamationmark.triangle.fill"
        } else {
            "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            .red
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") || message.contains("paused") {
            .orange
        } else {
            .green
        }
    }

    private var backgroundColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            Color.red.opacity(0.85)
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") || message.contains("paused") {
            Color.orange.opacity(0.85)
        } else {
            Color.green.opacity(0.85)
        }
    }

    private var borderColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            Color.red.opacity(0.5)
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") || message.contains("paused") {
            Color.orange.opacity(0.5)
        } else {
            Color.green.opacity(0.5)
        }
    }
}

struct DiagnosticSummaryView: View {
    let criticalIssues: [KanataDiagnostic]
    let onViewDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Issues Detected")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(criticalIssues.count) critical issue\(criticalIssues.count == 1 ? "" : "s") need attention")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onViewDiagnostics, label: {
                    Text("View Details")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                })
                .buttonStyle(.plain)
            }

            // Show first 2 critical issues as preview
            ForEach(Array(criticalIssues.prefix(2).enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.severity == .critical ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(issue.severity == .critical ? .red : .orange)
                        .font(.caption)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if !issue.description.isEmpty {
                            Text(issue.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if criticalIssues.count > 2 {
                Text("... and \(criticalIssues.count - 2) more issue\(criticalIssues.count - 2 == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

#Preview {
    let manager = KanataManager()
    let viewModel = KanataViewModel(manager: manager)
    ContentView()
        .environmentObject(viewModel)
}
