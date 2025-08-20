import SwiftUI

struct ContentView: View {
    @State private var keyboardCapture: KeyboardCapture?
    @EnvironmentObject var kanataManager: KanataManager
    @EnvironmentObject var simpleKanataManager: SimpleKanataManager
    @State private var isRecording = false
    @State private var isRecordingOutput = false
    @State private var recordedInput = ""
    @State private var recordedOutput = ""
    @State private var showingInstallationWizard = false {
        didSet {
            AppLogger.shared.log(
                "🎭 [ContentView] showingInstallationWizard changed from \(oldValue) to \(showingInstallationWizard)"
            )
        }
    }

    @State private var hasCheckedRequirements = false
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var showingEmergencyAlert = false

    // Enhanced error handling
    @State private var enhancedErrorInfo: ErrorInfo?

    // Timer removed - now handled by SimpleKanataManager centrally

    var body: some View {
        VStack(spacing: 20) {
            // Header
            ContentViewHeader(showingInstallationWizard: $showingInstallationWizard)

            // Recording Section
            RecordingSection(
                recordedInput: $recordedInput, recordedOutput: $recordedOutput,
                isRecording: $isRecording, isRecordingOutput: $isRecordingOutput,
                kanataManager: kanataManager, keyboardCapture: $keyboardCapture,
                showStatusMessage: showStatusMessage, simpleKanataManager: simpleKanataManager
            )

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

            // TODO: Diagnostic Summary (show critical issues) - commented out to revert to previous behavior
            // if !kanataManager.diagnostics.isEmpty {
            //     let criticalIssues = kanataManager.diagnostics.filter { $0.severity == .critical || $0.severity == .error }
            //     if !criticalIssues.isEmpty {
            //         DiagnosticSummarySection(criticalIssues: criticalIssues, kanataManager: kanataManager)
            //     }
            // }
        }
        .padding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(
            isPresented: Binding(
                get: {
                    let shouldShow = simpleKanataManager.showWizard
                    if shouldShow != showingInstallationWizard {
                        AppLogger.shared.log(
                            "🎭 [ContentView] Wizard state change: \(showingInstallationWizard) -> \(shouldShow)")
                    }
                    showingInstallationWizard = shouldShow
                    return shouldShow
                },
                set: { newValue in
                    AppLogger.shared.log("🎭 [ContentView] Sheet binding set to: \(newValue)")
                    showingInstallationWizard = newValue
                }
            )
        ) {
            InstallationWizardView()
                .onAppear {
                    AppLogger.shared.log("🔍 [ContentView] Installation wizard sheet is being presented")
                }
                .onDisappear {
                    // When wizard closes, call SimpleKanataManager to handle the closure
                    AppLogger.shared.log("🎭 [ContentView] ========== WIZARD CLOSED ==========")
                    AppLogger.shared.log("🎭 [ContentView] Installation wizard sheet dismissed by user")
                    AppLogger.shared.log("🎭 [ContentView] Calling simpleKanataManager.onWizardClosed()")

                    Task {
                        await simpleKanataManager.onWizardClosed()
                    }
                }
                .environmentObject(kanataManager)
        }
        .onAppear {
            AppLogger.shared.log("🔍 [ContentView] onAppear called")
            AppLogger.shared.log(
                "🏗️ [ContentView] Using shared SimpleKanataManager, initial showWizard: \(simpleKanataManager.showWizard)"
            )

            // Set up notification handlers for recovery actions
            setupRecoveryActionHandlers()

            // Start the auto-launch sequence
            Task {
                AppLogger.shared.log("🚀 [ContentView] Starting auto-launch sequence")
                await simpleKanataManager.startAutoLaunch()
                AppLogger.shared.log("✅ [ContentView] Auto-launch sequence completed")
                AppLogger.shared.log(
                    "✅ [ContentView] Post auto-launch - showWizard: \(simpleKanataManager.showWizard)")
                AppLogger.shared.log(
                    "✅ [ContentView] Post auto-launch - currentState: \(simpleKanataManager.currentState.rawValue)"
                )
            }

            if !hasCheckedRequirements {
                AppLogger.shared.log("🔍 [ContentView] First time setup")
                hasCheckedRequirements = true
            }

            // Try to start monitoring for emergency stop sequence
            // This will silently fail if permissions aren't granted yet
            startEmergencyMonitoringIfPossible()

            // Status monitoring now handled centrally by SimpleKanataManager
        }
        .onChange(of: simpleKanataManager.showWizard) { shouldShow in
            AppLogger.shared.log("🔍 [ContentView] showWizard changed to: \(shouldShow)")
            AppLogger.shared.log(
                "🔍 [ContentView] Current simpleKanataManager state: \(simpleKanataManager.currentState.rawValue)"
            )
            AppLogger.shared.log(
                "🔍 [ContentView] Current errorReason: \(simpleKanataManager.errorReason ?? "nil")")
            AppLogger.shared.log("🔍 [ContentView] Setting showingInstallationWizard = \(shouldShow)")
            showingInstallationWizard = shouldShow
            AppLogger.shared.log(
                "🔍 [ContentView] showingInstallationWizard is now: \(showingInstallationWizard)")
        }
        .onChange(of: kanataManager.lastConfigUpdate) { _ in
            // Show status message when config is updated externally
            showStatusMessage(message: "Key mappings updated")
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
        .onChange(of: showingInstallationWizard) { showing in
            // When wizard closes, try to start emergency monitoring if we now have permissions
            if !showing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startEmergencyMonitoringIfPossible()
                }
            }
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
            if PermissionService.shared.hasAccessibilityPermission() {
                keyboardCapture = KeyboardCapture()
                AppLogger.shared.log("🎹 [ContentView] KeyboardCapture initialized for emergency monitoring")
            } else {
                // Don't have permissions yet - we'll try again later
                return
            }
        }

        guard let capture = keyboardCapture else { return }

        // We have permissions, start monitoring
        capture.startEmergencyMonitoring {
            showStatusMessage(message: "🚨 Emergency stop activated - Kanata stopped")
            showingEmergencyAlert = true
        }
    }

    // Status monitoring functions removed - now handled centrally by SimpleKanataManager

    /// Set up notification handlers for recovery actions
    private func setupRecoveryActionHandlers() {
        // Handle opening installation wizard
        NotificationCenter.default.addObserver(forName: .openInstallationWizard, object: nil, queue: .main) { _ in
            showingInstallationWizard = true
        }

        // Handle resetting to safe config
        NotificationCenter.default.addObserver(forName: .resetToSafeConfig, object: nil, queue: .main) { _ in
            Task {
                do {
                    _ = try await kanataManager.createDefaultUserConfigIfMissing()
                    await kanataManager.updateStatus()
                    showStatusMessage(message: "✅ Configuration reset to safe defaults")
                } catch {
                    showStatusMessage(message: "❌ Failed to reset configuration: \(error.localizedDescription)")
                }
            }
        }

        // Handle opening diagnostics
        NotificationCenter.default.addObserver(forName: .openDiagnostics, object: nil, queue: .main) { _ in
            // This would open a diagnostics window - implementation depends on app structure
            showStatusMessage(message: "ℹ️ Opening diagnostics view...")
        }
    }
}

struct ContentViewHeader: View {
    @Binding var showingInstallationWizard: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: {
                    AppLogger.shared.log(
                        "🔧 [ContentViewHeader] Keyboard icon tapped - launching installation wizard")
                    showingInstallationWizard = true
                }) {
                    Image(systemName: "keyboard")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("launch-installation-wizard-button")
                .accessibilityLabel("Launch Installation Wizard")
                .accessibilityHint("Click to open the KeyPath installation and setup wizard")

                Text("KeyPath")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            Text("Record keyboard shortcuts and create custom key mappings")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordingSection: View {
    @Binding var recordedInput: String
    @Binding var recordedOutput: String
    @Binding var isRecording: Bool
    @Binding var isRecordingOutput: Bool
    @ObservedObject var kanataManager: KanataManager
    @Binding var keyboardCapture: KeyboardCapture?
    let showStatusMessage: (String) -> Void

    // Simple Kanata Manager Integration
    let simpleKanataManager: SimpleKanataManager?
    @State private var outputInactivityTimer: Timer?
    @State private var showingConfigCorruptionAlert = false
    @State private var configCorruptionDetails = ""
    @State private var configRepairSuccessful = false
    @State private var showingRepairFailedAlert = false
    @State private var repairFailedDetails = ""
    @State private var failedConfigBackupPath = ""

    // MARK: - Phase 1: Save Operation Debouncing

    @State private var saveDebounceTimer: Timer?
    private let saveDebounceDelay: TimeInterval = 0.5

    var body: some View {
        VStack(spacing: 16) {
            // Input Recording
            VStack(alignment: .leading, spacing: 8) {
                // Accessibility container for input recording section
                Text("Input Key:")
                    .font(.headline)
                    .accessibilityIdentifier("input-key-label")

                HStack {
                    Text(getInputDisplayText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isRecording ? Color.blue : Color.clear, lineWidth: 2)
                        )
                        .accessibilityIdentifier("input-key-display")
                        .accessibilityLabel("Input key")
                        .accessibilityValue(recordedInput.isEmpty ? "No key recorded" : "Key: \(recordedInput)")

                    Button(action: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }) {
                        Image(systemName: getInputButtonIcon())
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 44)
                    .frame(minWidth: 44)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(!kanataManager.isCompletelyInstalled() && !isRecording)
                    .accessibilityIdentifier("input-key-record-button")
                    .accessibilityLabel(isRecording ? "Stop recording input key" : "Record input key")
                    .accessibilityHint(
                        isRecording ? "Stop recording the input key" : "Start recording a key to remap")
                }
            }
            .accessibilityIdentifier("input-recording-section")
            .accessibilityLabel("Input key recording section")

            // Output Recording
            VStack(alignment: .leading, spacing: 8) {
                // Accessibility container for output recording section
                Text("Output Key:")
                    .font(.headline)
                    .accessibilityIdentifier("output-key-label")

                HStack {
                    Text(getOutputDisplayText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isRecordingOutput ? Color.blue : Color.clear, lineWidth: 2)
                        )
                        .accessibilityIdentifier("output-key-display")
                        .accessibilityLabel("Output key")
                        .accessibilityValue(
                            recordedOutput.isEmpty ? "No key recorded" : "Key: \(recordedOutput)")

                    Button(action: {
                        if isRecordingOutput {
                            stopOutputRecording()
                        } else {
                            startOutputRecording()
                        }
                    }) {
                        Image(systemName: getOutputButtonIcon())
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 44)
                    .frame(minWidth: 44)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(!kanataManager.isCompletelyInstalled() && !isRecordingOutput)
                    .accessibilityIdentifier("output-key-record-button")
                    .accessibilityLabel(isRecordingOutput ? "Stop recording output key" : "Record output key")
                    .accessibilityHint(
                        isRecordingOutput
                            ? "Stop recording the output key" : "Start recording the replacement key")
                }
            }
            .accessibilityIdentifier("output-recording-section")
            .accessibilityLabel("Output key recording section")

            // Save Button
            HStack {
                Spacer()
                Button(action: {
                    debouncedSave()
                }) {
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
                .disabled(recordedInput.isEmpty || recordedOutput.isEmpty || kanataManager.saveStatus.isActive)
                .accessibilityIdentifier("save-mapping-button")
                .accessibilityLabel(kanataManager.saveStatus.message.isEmpty ? "Save key mapping" : kanataManager.saveStatus.message)
                .accessibilityHint("Save the input and output key mapping to your configuration")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .alert("Configuration Issue Detected", isPresented: $showingConfigCorruptionAlert) {
            Button("OK") {
                showingConfigCorruptionAlert = false
            }
            Button("View Diagnostics") {
                showingConfigCorruptionAlert = false
                // TODO: Open diagnostics view
            }
        } message: {
            Text(configCorruptionDetails)
        }
        .alert("Configuration Repair Failed", isPresented: $showingRepairFailedAlert) {
            Button("OK") {
                showingRepairFailedAlert = false
            }
            Button("Open Failed Config in Zed") {
                showingRepairFailedAlert = false
                kanataManager.openFileInZed(failedConfigBackupPath)
            }
            Button("View Diagnostics") {
                showingRepairFailedAlert = false
                // TODO: Open diagnostics view
            }
        } message: {
            Text(repairFailedDetails)
        }
        .alert(kanataManager.validationAlertTitle, isPresented: $kanataManager.showingValidationAlert) {
            ForEach(kanataManager.validationAlertActions.indices, id: \.self) { index in
                let action = kanataManager.validationAlertActions[index]
                switch action.style {
                case .default:
                    Button(action.title) {
                        action.action()
                    }
                case .cancel:
                    Button(action.title, role: .cancel) {
                        action.action()
                    }
                case .destructive:
                    Button(action.title, role: .destructive) {
                        action.action()
                    }
                }
            }
        } message: {
            Text(kanataManager.validationAlertMessage)
        }
    }

    private func getInputButtonIcon() -> String {
        if isRecording {
            "xmark.circle.fill"
        } else if recordedInput.isEmpty {
            "play.circle.fill"
        } else {
            "arrow.clockwise.circle.fill"
        }
    }

    private func getOutputButtonIcon() -> String {
        if isRecordingOutput {
            "xmark.circle.fill"
        } else if recordedOutput.isEmpty {
            "play.circle.fill"
        } else {
            "arrow.clockwise.circle.fill"
        }
    }

    private func startRecording() {
        isRecording = true
        recordedInput = ""

        // Initialize KeyboardCapture lazily only when actually needed and if we have permissions
        if keyboardCapture == nil {
            if PermissionService.shared.hasAccessibilityPermission() {
                keyboardCapture = KeyboardCapture()
                AppLogger.shared.log("🎹 [RecordingSection] KeyboardCapture initialized lazily for recording")
            } else {
                recordedInput = "⚠️ Accessibility permission required for recording"
                isRecording = false
                return
            }
        }

        guard let capture = keyboardCapture else {
            recordedInput = "⚠️ Failed to initialize keyboard capture"
            isRecording = false
            return
        }

        capture.startCapture { keyName in
            recordedInput = keyName
            isRecording = false
        }
    }

    private func stopRecording() {
        isRecording = false
        keyboardCapture?.stopCapture()
    }

    private func startOutputRecording() {
        isRecordingOutput = true
        recordedOutput = ""

        // Initialize KeyboardCapture lazily if needed and we have permissions
        if keyboardCapture == nil {
            if PermissionService.shared.hasAccessibilityPermission() {
                keyboardCapture = KeyboardCapture()
                AppLogger.shared.log("🎹 [RecordingSection] KeyboardCapture initialized for output recording")
            } else {
                recordedOutput = "⚠️ Accessibility permission required for recording"
                isRecordingOutput = false
                return
            }
        }

        guard let capture = keyboardCapture else {
            recordedOutput = "⚠️ Failed to initialize keyboard capture"
            isRecordingOutput = false
            return
        }

        capture.startContinuousCapture { keyName in
            if !recordedOutput.isEmpty {
                recordedOutput += " "
            }
            recordedOutput += keyName

            // Reset the inactivity timer each time a key is pressed
            resetOutputInactivityTimer()
        }

        // Start the initial inactivity timer
        resetOutputInactivityTimer()
    }

    private func stopOutputRecording() {
        isRecordingOutput = false
        keyboardCapture?.stopCapture()
        cancelOutputInactivityTimer()
    }

    private func resetOutputInactivityTimer() {
        // Cancel existing timer
        outputInactivityTimer?.invalidate()

        // Start new 5-second timer
        outputInactivityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if isRecordingOutput {
                stopOutputRecording()
            }
        }
    }

    private func cancelOutputInactivityTimer() {
        outputInactivityTimer?.invalidate()
        outputInactivityTimer = nil
    }

    private func getInputDisplayText() -> String {
        if !recordedInput.isEmpty {
            recordedInput
        } else if isRecording {
            "Press a key..."
        } else {
            ""
        }
    }

    private func getOutputDisplayText() -> String {
        if !recordedOutput.isEmpty {
            recordedOutput
        } else if isRecordingOutput {
            "Press keys..."
        } else {
            ""
        }
    }

    // MARK: - Phase 1: Debounced Save Implementation

    private func debouncedSave() {
        // Cancel any existing timer
        saveDebounceTimer?.invalidate()

        // Show saving state immediately for user feedback via KanataManager.saveStatus
        AppLogger.shared.log("💾 [Save] Debounced save initiated - starting timer")

        // Create new timer
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) {
            _ in
            AppLogger.shared.log("💾 [Save] Debounce timer fired - executing save")
            Task {
                await saveKeyPath()
            }
        }
    }

    private func saveKeyPath() async {
        AppLogger.shared.log("💾 [Save] ========== SAVE OPERATION START ==========")

        do {
            let inputKey = recordedInput
            let outputKey = recordedOutput

            AppLogger.shared.log("💾 [Save] Saving mapping: \(inputKey) → \(outputKey)")

            // Use direct KanataManager for save operation (SimpleKanataManager handles service management)
            AppLogger.shared.log("💾 [Save] Using direct KanataManager for save operation")
            try await kanataManager.saveConfiguration(input: inputKey, output: outputKey)

            AppLogger.shared.log("💾 [Save] Configuration saved successfully")

            // Show status message and clear the form
            await MainActor.run {
                showStatusMessage("Key mapping saved: \(inputKey) → \(outputKey)")

                // Clear the form
                recordedInput = ""
                recordedOutput = ""
            }

            // Update status
            AppLogger.shared.log("💾 [Save] Updating manager status...")
            await kanataManager.updateStatus()

            AppLogger.shared.log("💾 [Save] ========== SAVE OPERATION COMPLETE ==========")
        } catch {
            AppLogger.shared.log("❌ [Save] Error during save operation: \(error)")

            // Error handling will be managed by KanataManager's saveStatus

            // Handle specific config errors
            if let configError = error as? ConfigError {
                switch configError {
                case let .corruptedConfigDetected(errors):
                    configCorruptionDetails = """
                    Configuration corruption detected:

                    \(errors.joined(separator: "\n"))

                    KeyPath attempted automatic repair. If the repair was successful, your mapping has been saved with a corrected configuration. " +
                    "If repair failed, a safe fallback configuration was applied.
                    """
                    await MainActor.run {
                        configRepairSuccessful = false
                        showingConfigCorruptionAlert = true
                        showStatusMessage("⚠️ Config repaired automatically")
                    }

                case let .claudeRepairFailed(reason):
                    configCorruptionDetails = """
                    Configuration repair failed:

                    \(reason)

                    A safe fallback configuration has been applied. Your system should continue working with basic functionality.
                    """
                    await MainActor.run {
                        configRepairSuccessful = false
                        showingConfigCorruptionAlert = true
                        showStatusMessage("❌ Config repair failed - using safe fallback")
                    }

                case let .repairFailedNeedsUserAction(
                    originalConfig, _, originalErrors, repairErrors, mappings
                ):
                    // Handle user action required case
                    Task {
                        do {
                            // Backup the failed config and apply safe default
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
                                showStatusMessage("⚠️ Config backed up, safe default applied")
                            }
                        } catch {
                            await MainActor.run {
                                showStatusMessage("❌ Failed to backup config: \(error.localizedDescription)")
                            }
                        }
                    }

                case let .preSaveValidationFailed(errors, _),
                     let .postSaveValidationFailed(errors):
                    // These are handled by KanataManager's validation dialogs
                    AppLogger.shared.log("⚠️ [Save] Validation error handled by KanataManager dialogs")

                case let .startupValidationFailed(errors, backupPath):
                    await MainActor.run {
                        showStatusMessage("⚠️ Config validation failed at startup - using default")
                    }

                default:
                    await MainActor.run {
                        showStatusMessage("❌ Config error: \(error.localizedDescription)")
                    }
                }
            } else {
                // Show generic error message
                await MainActor.run {
                    showStatusMessage("❌ Error saving: \(error.localizedDescription)")
                }
            }
        }
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

#Preview {
    ContentView()
        .environmentObject(KanataManager())
}
