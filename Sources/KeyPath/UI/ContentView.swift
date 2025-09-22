import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @State private var keyboardCapture: KeyboardCapture?
    @EnvironmentObject var kanataManager: KanataManager
    @Environment(\.permissionSnapshotProvider) private var permissionSnapshotProvider
    @StateObject private var startupValidator = StartupValidator()
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

    @State private var saveDebounceTimer: Timer?
    private let saveDebounceDelay: TimeInterval = 0.5

    @State private var lastInputDisabledReason: String = ""
    @State private var lastOutputDisabledReason: String = ""

    var body: some View {
        VStack(spacing: 20) {
            // Header
            ContentViewHeader(
                validator: startupValidator,
                showingInstallationWizard: $showingInstallationWizard
            )

            // Recording Section
            RecordingSection(
                coordinator: recordingCoordinator,
                onInputRecord: { handleInputRecordTap() },
                onOutputRecord: { handleOutputRecordTap() }
            )

            HStack {
                Spacer()
                Button(action: { debouncedSave() }) {
                    HStack {
                        if kanataManager.saveStatus.isActive {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                        Text(kanataManager.saveStatus.message.isEmpty ? "Save" : kanataManager.saveStatus.message)
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recordingCoordinator.capturedInputSequence() == nil ||
                          recordingCoordinator.capturedOutputSequence() == nil ||
                          kanataManager.saveStatus.isActive)
                .accessibilityIdentifier("save-mapping-button")
                .accessibilityLabel(kanataManager.saveStatus.message.isEmpty ? "Save key mapping" : kanataManager.saveStatus.message)
                .accessibilityHint("Save the input and output key mapping to your configuration")
            }

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
                        // Re-run validation to update the status indicator
                        startupValidator.refreshValidation(force: true)
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

            // Configure startup validator and recording coordinator with KanataManager
            startupValidator.configure(with: kanataManager)
            recordingCoordinator.configure(
                kanataManager: kanataManager,
                statusHandler: { message in showStatusMessage(message: message) },
                permissionProvider: permissionSnapshotProvider
            )

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
            // Refresh validation after config changes
            startupValidator.refreshValidation()
        }
        .onChange(of: kanataManager.currentState) { _, _ in
            // Refresh validation when lifecycle state changes
            startupValidator.refreshValidation()
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
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            // Wizard closed from anywhere (e.g., Settings) → force refresh validator and status
            Task {
                startupValidator.refreshValidation(force: true)
                await kanataManager.updateStatus()
            }
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
            showingEmergencyAlert = true
        }
    }

    // MARK: - Startup Observers

    private func setupStartupObservers() {
        NotificationCenter.default.addObserver(forName: .kp_startupWarm, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] Warm phase")
            // Lightweight warm-ups (noop for now)
        }

        NotificationCenter.default.addObserver(forName: .kp_startupValidate, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] Validate phase → StartupValidator.performStartupValidation()")
            startupValidator.performStartupValidation()
            // Allow modals from this point onward
            canPresentModals = true
            if pendingShowWizardRequest {
                AppLogger.shared.log("🎭 [Startup] Presenting deferred wizard after validation phase")
                pendingShowWizardRequest = false
                showingInstallationWizard = true
            }
        }

        NotificationCenter.default.addObserver(forName: .kp_startupAutoLaunch, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] AutoLaunch phase")
            // Respect permission-grant return to avoid resetting wizard state
            if !checkForPendingPermissionGrant() {
                Task {
                    AppLogger.shared.log("🚀 [ContentView] Starting auto-launch sequence (coordinated)")
                    await kanataManager.startAutoLaunch(presentWizardOnFailure: false)
                    AppLogger.shared.log("✅ [ContentView] Auto-launch sequence completed")
                }
            }
        }

        NotificationCenter.default.addObserver(forName: .kp_startupEmergencyMonitor, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] Emergency monitor phase")
            startEmergencyMonitoringIfPossible()
        }

        NotificationCenter.default.addObserver(forName: .kp_startupRevalidate, object: nil, queue: .main) { _ in
            AppLogger.shared.log("🚦 [Startup] Follow-up revalidate phase")
            startupValidator.performStartupValidation()
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
                kanataManager: kanataManager
            ) { _ in
                // Show wizard after service restart completes to display results
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Reopen wizard to the appropriate permission page
                    PermissionGrantCoordinator.shared.reopenWizard(
                        for: permissionType,
                        kanataManager: kanataManager
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
        await recordingCoordinator.saveMapping(
            kanataManager: kanataManager,
            onSuccess: { message in handleSaveSuccess(message) },
            onError: { error in handleSaveError(error) }
        )
    }

    private func handleSaveSuccess(_ message: String) {
        showStatusMessage(message: message)
    }

    private func handleSaveError(_ error: Error) {
        if let coordinatorError = error as? RecordingCoordinator.CoordinatorError {
            switch coordinatorError {
            case .missingSequences:
                showStatusMessage(message: "❌ Please capture both input and output keys first")
            }
            return
        }

        guard let configError = error as? ConfigError else {
            showStatusMessage(message: "❌ Error saving: \(error.localizedDescription)")
            return
        }

        switch configError {
        case let .corruptedConfigDetected(errors):
            configCorruptionDetails = """
            Configuration corruption detected:

            \(errors.joined(separator: "\n"))

            KeyPath attempted automatic repair. If the repair was successful, your mapping has been saved with a corrected configuration. If repair failed, a safe fallback configuration was applied.
            """
            configRepairSuccessful = false
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "⚠️ Config repaired automatically")

        case let .claudeRepairFailed(reason):
            configCorruptionDetails = """
            Configuration repair failed:

            \(reason)

            A safe fallback configuration has been applied. Your system should continue working with basic functionality.
            """
            configRepairSuccessful = false
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "❌ Config repair failed - using safe fallback")

        case let .repairFailedNeedsUserAction(originalConfig, _, originalErrors, repairErrors, mappings):
            Task {
                do {
                    let backupPath = try await kanataManager.backupFailedConfigAndApplySafe(
                        failedConfig: originalConfig,
                        mappings: mappings
                    )

                    await MainActor.run {
                        failedConfigBackupPath = backupPath
                        repairFailedDetails = """
                        KeyPath was unable to automatically repair your configuration file.

                        Original errors:
                        \(originalErrors.joined(separator: "\n"))

                        Repair attempt errors:
                        \(repairErrors.joined(separator: "\n"))

                        Actions taken:
                        • Your failed configuration has been backed up to: \(backupPath)
                        • A safe default configuration (Caps Lock → Escape) has been applied
                        • Your system should continue working normally

                        You can examine and manually fix the backed up configuration if needed.
                        """
                        showingRepairFailedAlert = true
                        showStatusMessage(message: "⚠️ Config backed up, safe default applied")
                    }
                } catch {
                    await MainActor.run {
                        showStatusMessage(message: "❌ Failed to backup config: \(error.localizedDescription)")
                    }
                }
            }

        case let .startupValidationFailed(errors, backupPath):
            configCorruptionDetails = """
            Configuration validation failed at startup:

            \(errors.joined(separator: "\n"))

            Last known good configuration backed up to: \(backupPath)
            """
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "⚠️ Config validation failed at startup - using default")

        case let .preSaveValidationFailed(errors, config):
            configCorruptionDetails = """
            Pre-save validation failed:

            \(errors.joined(separator: "\n"))

            Problematic configuration:
            \(config)
            """
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "❌ Config error: validation failed before save")

        case let .postSaveValidationFailed(errors):
            configCorruptionDetails = """
            Post-save validation failed:

            \(errors.joined(separator: "\n"))
            """
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "❌ Config error: validation failed after save")

        case let .validationFailed(errors):
            configCorruptionDetails = """
            Configuration validation failed:

            \(errors.joined(separator: "\n"))
            """
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "❌ Configuration validation failed")
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

struct ContentViewHeader: View {
    @ObservedObject var validator: StartupValidator
    @Binding var showingInstallationWizard: Bool
    @EnvironmentObject var kanataManager: KanataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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

                Spacer()

                // System Status Indicator in top-right
                SystemStatusIndicator(
                    validator: validator,
                    showingWizard: $showingInstallationWizard,
                    onClick: {
                        kanataManager.requestWizardPresentation()
                    }
                )
            }

            Text("Record keyboard shortcuts and create custom key mappings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordingSection: View {
    @ObservedObject var coordinator: RecordingCoordinator
    let onInputRecord: () -> Void
    let onOutputRecord: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            inputSection
            outputSection
        }
        .onAppear { coordinator.requestPlaceholders() }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Key")
                    .font(.headline)
                    .accessibilityIdentifier("input-key-label")

                Spacer()

                Button(action: {
                    PreferencesService.shared.applyMappingsDuringRecording.toggle()
                    coordinator.requestPlaceholders()
                }, label: {
                    Image(systemName: "app.background.dotted")
                        .font(.title2)
                        .foregroundColor(PreferencesService.shared.applyMappingsDuringRecording ? .white : .blue)
                })
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(PreferencesService.shared.applyMappingsDuringRecording ? Color.blue : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .cornerRadius(6)
                .help(PreferencesService.shared.applyMappingsDuringRecording
                    ? "Mappings ON: Recording shows effective (mapped) keys. Click to show raw keys."
                    : "Mappings OFF: Recording shows raw (physical) keys. Click to show mapped keys.")
                .accessibilityIdentifier("apply-mappings-toggle")
                .accessibilityLabel(PreferencesService.shared.applyMappingsDuringRecording
                    ? "Disable mappings during recording"
                    : "Enable mappings during recording")
                .padding(.trailing, 5)

                Button(action: {
                    coordinator.toggleSequenceMode()
                    coordinator.requestPlaceholders()
                }, label: {
                    Image(systemName: "list.number")
                        .font(.title2)
                        .foregroundColor(coordinator.isSequenceMode ? .white : .blue)
                })
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(coordinator.isSequenceMode ? Color.blue : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .cornerRadius(6)
                .help(coordinator.isSequenceMode ? "Capture sequences of keys" : "Capture key combos")
                .accessibilityIdentifier("sequence-mode-toggle")
                .accessibilityLabel(coordinator.isSequenceMode ? "Switch to combo mode" : "Switch to sequence mode")
                .accessibilityHint("Toggle between combo capture and sequence capture modes")
                .padding(.trailing, 5)
            }

            HStack {
                Text(coordinator.inputDisplayText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
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
                .background(Color.accentColor)
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
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
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
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
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
                .background(Color.accentColor)
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
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .accessibilityIdentifier("output-recording-section")
        .accessibilityLabel("Output key recording section")
    }
}

struct ErrorSection: View {
    @ObservedObject var kanataManager: KanataManager
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
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct DiagnosticSummarySection: View {
    let criticalIssues: [KanataDiagnostic]
    @ObservedObject var kanataManager: KanataManager
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

struct StatusMessageView: View {
    let message: String
    let isVisible: Bool

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundColor(iconColor)

                    Text(message)
                        .font(.headline)
                        .foregroundColor(.primary)

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
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isVisible)
    }

    private var iconName: String {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            "xmark.circle.fill"
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
            || message.contains("backed up") {
            .orange
        } else {
            .green
        }
    }

    private var backgroundColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            Color.red.opacity(0.1)
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") {
            Color.orange.opacity(0.1)
        } else {
            Color.green.opacity(0.1)
        }
    }

    private var borderColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            Color.red.opacity(0.3)
        } else if message.contains("⚠️") || message.contains("Config repaired")
            || message.contains("backed up") {
            Color.orange.opacity(0.3)
        } else {
            Color.green.opacity(0.3)
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
    ContentView()
        .environmentObject(KanataManager())
}
