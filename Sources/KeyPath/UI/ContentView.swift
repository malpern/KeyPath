import SwiftUI
import AppKit
import Combine

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

    // Diagnostics view state
    @State private var showingDiagnostics = false
    @State private var showingConfigCorruptionAlert = false
    @State private var configCorruptionDetails = ""
    @State private var configRepairSuccessful = false
    @State private var showingRepairFailedAlert = false
    @State private var repairFailedDetails = ""
    @State private var failedConfigBackupPath = ""
    @State private var showingInstallAlert = false
    @State private var showingKanataNotRunningAlert = false

    @State private var saveDebounceTimer: Timer?
    private let saveDebounceDelay: TimeInterval = 0.5

    @State private var lastInputDisabledReason: String = ""
    @State private var lastOutputDisabledReason: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            ContentViewHeader(
                validator: stateController, // 🎯 Phase 3: New controller
                showingInstallationWizard: $showingInstallationWizard
            )

            // Recording Section (no solid wrapper; let glass show through)
            RecordingSection(
                coordinator: recordingCoordinator,
                onInputRecord: { handleInputRecordTap() },
                onOutputRecord: { handleOutputRecordTap() }
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            SaveRow(
                isActive: kanataManager.saveStatus.isActive,
                label: kanataManager.saveStatus.message.isEmpty ? "Save" : kanataManager.saveStatus.message,
                isDisabled: (recordingCoordinator.capturedInputSequence() == nil ||
                             recordingCoordinator.capturedOutputSequence() == nil ||
                             kanataManager.saveStatus.isActive),
                onSave: { debouncedSave() }
            )

            // Debug row removed in production UI

            // Enhanced Error Display - persistent and actionable
            EnhancedErrorHandler(errorInfo: $enhancedErrorInfo)

            // Legacy Error Section (only show if there's an error and no enhanced error)
            if let error = kanataManager.lastError, !kanataManager.isRunning, enhancedErrorInfo == nil {
                ErrorSection(
                    kanataManager: kanataManager, showingInstallationWizard: $showingInstallationWizard,
                    error: error
                )
            }

            // Push status message and diagnostics to bottom - keeps top content stable
            Spacer(minLength: 0)

            // Status Message - Only show for success messages, errors use enhanced handler
            StatusMessageView(message: statusMessage, isVisible: showStatusMessage && !statusMessage.contains("❌"))
                .frame(height: (showStatusMessage && !statusMessage.contains("❌")) ? nil : 0)
                .clipped()

            // Diagnostic Summary (show critical issues)
            if !kanataManager.diagnostics.isEmpty {
                let criticalIssues = kanataManager.diagnostics.filter { $0.severity == .critical || $0.severity == .error }
                if !criticalIssues.isEmpty {
                    DiagnosticSummaryView(criticalIssues: criticalIssues) {
                        showingDiagnostics = true
                    }
                }
            }
        }
        .padding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showingInstallationWizard) {
            // Determine initial page if we're returning from permission granting
            let initialPage: WizardPage? = {
                if UserDefaults.standard.bool(forKey: "wizard_return_to_input_monitoring") {
                    UserDefaults.standard.removeObject(forKey: "wizard_return_to_input_monitoring")
                    return .inputMonitoring
                } else if UserDefaults.standard.bool(forKey: "wizard_return_to_accessibility") {
                    UserDefaults.standard.removeObject(forKey: "wizard_return_to_accessibility")
                    return .accessibility
                }
                return nil
            }()

            InstallationWizardView(initialPage: initialPage)
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

            if shouldShow && !canPresentModals {
                pendingShowWizardRequest = true
                AppLogger.shared.log("🔍 [ContentView] Deferring wizard presentation until modals are allowed")
                return
            }

            showingInstallationWizard = shouldShow
            AppLogger.shared.log("🔍 [ContentView] showingInstallationWizard set to: \(showingInstallationWizard)")
        }
        .onChange(of: kanataManager.lastConfigUpdate) { _, _ in
            // Show status message when config is updated externally
            showStatusMessage(message: "Key mappings updated")
            // Also raise a system notification when not frontmost
            UserNotificationService.shared.notifyConfigEvent(
                "Key mappings updated",
                body: "Configuration reloaded",
                key: "config.updated"
            )
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
                showingDiagnostics = true
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
                showingDiagnostics = true
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
            // Use traditional status message for success/info messages
            statusMessage = message
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showStatusMessage = true
            }
            // Hide after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showStatusMessage = false
                }
            }
        }
    }

    private func startEmergencyMonitoringIfPossible() {
        // Initialize KeyboardCapture lazily if needed and we have permissions
        if keyboardCapture == nil {
            Task {
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                await MainActor.run {
                    if snapshot.keyPath.accessibility.isReady {
                        keyboardCapture = KeyboardCapture()
                        AppLogger.shared.log("🎹 [ContentView] KeyboardCapture initialized for emergency monitoring")
                    } else {
                        // Don't have permissions yet - we'll try again later
                        return
                    }
                }
            }
        }

        guard let capture = keyboardCapture else { return }

        // We have permissions, start monitoring
        capture.startEmergencyMonitoring {
            showStatusMessage(message: "🚨 Emergency stop activated - Kanata stopped")
            // Surface a system notification if app is not frontmost
            UserNotificationService.shared.notifyLaunchFailure(.serviceFailure("Emergency stop activated"))
            showingEmergencyAlert = true
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
                kanataManager: kanataManager.underlyingManager  // Phase 4: Business logic needs underlying manager
            ) { _ in
                // Show wizard after service restart completes to display results
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Reopen wizard to the appropriate permission page
                    PermissionGrantCoordinator.shared.reopenWizard(
                        for: permissionType,
                        kanataManager: kanataManager.underlyingManager  // Phase 4: Business logic needs underlying manager
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
        AppLogger.shared.log("🔵 [ContentView] debouncedSave() called")
        saveDebounceTimer?.invalidate()
        AppLogger.shared.log("🔵 [ContentView] Creating debounce timer with delay: \(saveDebounceDelay)s")
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) { _ in
            AppLogger.shared.log("🔵 [ContentView] Debounce timer fired, calling performSave()")
            Task { await performSave() }
        }
    }

    private func performSave() async {
        AppLogger.shared.log("🟢 [ContentView] performSave() started")
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil

        // Pre-flight check: Ensure kanata is running before attempting save
        AppLogger.shared.log("🟢 [ContentView] Checking if kanata is running: \(kanataManager.isRunning)")
        guard kanataManager.isRunning else {
            AppLogger.shared.log("⚠️ [ContentView] Cannot save - kanata service is not running")
            await MainActor.run {
                showingKanataNotRunningAlert = true
            }
            return
        }

        AppLogger.shared.log("🟢 [ContentView] Calling recordingCoordinator.saveMapping()")
        await recordingCoordinator.saveMapping(
            kanataManager: kanataManager.underlyingManager,  // Phase 4: Business logic needs underlying manager
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
            UserNotificationService.shared.notifyConfigEvent(
                "Configuration Repaired",
                body: "Automatic repair applied to your config",
                key: "config.repaired"
            )
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
            UserNotificationService.shared.notifyFailureEvent(
                "Configuration Repair Failed",
                body: "Using a safe fallback configuration",
                key: "config.repair.failed"
            )
            return
        }

        // Handle communication errors with user-friendly messages
        if case let KeyPathError.communication(commError) = error {
            let message: String
            switch commError {
            case .timeout:
                message = "❌ Save timed out - Kanata took too long to respond. Try again."
            case .connectionFailed(let reason):
                if reason.contains("Connection refused") || reason.contains("61") {
                    message = "❌ Cannot connect to Kanata. Please restart the app."
                } else {
                    message = "❌ Connection failed: \(reason)"
                }
            case .noResponse:
                message = "❌ Kanata didn't respond. The service may be stuck - try restarting the app."
            case .notAuthenticated:
                message = "❌ Authentication failed. Please restart the app to reconnect."
            case .invalidResponse:
                message = "❌ Kanata sent an unexpected response. Check the logs for details."
            case .deserializationFailed:
                message = "❌ Could not parse Kanata's response. The config may have syntax errors."
            case .serializationFailed:
                message = "❌ Could not send request to Kanata. Internal error - check logs."
            case .invalidPort:
                message = "❌ Invalid port configuration. Please restart the app."
            case .payloadTooLarge(let size):
                message = "❌ Request too large (\(size) bytes). Simplify your configuration."
            }
            showStatusMessage(message: message)
            AppLogger.shared.log("❌ [Save Error] \(commError)")
            return
        }

        // Generic error handling for all other cases
        showStatusMessage(message: "❌ Error saving: \(error.localizedDescription)")
        AppLogger.shared.log("❌ [Save Error] Unhandled: \(error)")
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

        recordingCoordinator.toggleOutputRecording()
    }

    private func inputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled() && !recordingCoordinator.isInputRecording() {
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
        if !kanataManager.isCompletelyInstalled() && !recordingCoordinator.isOutputRecording() {
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

// ContentViewHeader moved to UI/Components/ContentViewHeader.swift

// RecordingSection moved to UI/Components/RecordingSection.swift

// ErrorSection moved to UI/Components/ErrorSection.swift

struct DiagnosticSummarySection: View {
    let criticalIssues: [KanataDiagnostic]
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @State private var showingDiagnostics = false

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
                    showingDiagnostics = true
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
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(kanataManager: kanataManager)
        }
    }
}

// StatusMessageView moved to UI/Components/StatusMessageView.swift

// DiagnosticSummaryView moved to UI/Components/DiagnosticSummaryView.swift

#Preview {
    let manager = KanataManager()
    let viewModel = KanataViewModel(manager: manager)
    ContentView()
        .environmentObject(viewModel)
}
