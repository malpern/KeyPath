import SwiftUI
import AppKit

struct ContentView: View {
    @State private var keyboardCapture: KeyboardCapture?
    @EnvironmentObject var kanataManager: KanataManager
    @StateObject private var startupValidator = StartupValidator()
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

    // Diagnostics view state
    @State private var showingDiagnostics = false

    // Capture mode toggle - default to combo (false = combo, true = sequence)
    @State private var isSequenceMode = false

    // Track if placeholder text should be shown (persists after toggling modes)
    @State private var showPlaceholderText = false

    // Timer removed - now handled by SimpleKanataManager centrally

    var body: some View {
        VStack(spacing: 20) {
            // Header
            ContentViewHeader(
                validator: startupValidator,
                showingInstallationWizard: $showingInstallationWizard
            )

            // Recording Section
            RecordingSection(
                recordedInput: $recordedInput, recordedOutput: $recordedOutput,
                isRecording: $isRecording, isRecordingOutput: $isRecordingOutput,
                kanataManager: kanataManager, keyboardCapture: $keyboardCapture,
                showStatusMessage: showStatusMessage, showingDiagnostics: $showingDiagnostics,
                isSequenceMode: $isSequenceMode, showPlaceholderText: $showPlaceholderText
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
                        startupValidator.refreshValidation()
                    }
                }
                .environmentObject(kanataManager)
        }
        .onAppear {
            AppLogger.shared.log("🔍 [ContentView] onAppear called")
            AppLogger.shared.log(
                "🏗️ [ContentView] Using shared SimpleKanataManager, initial showWizard: \(kanataManager.showWizard)"
            )

            // Configure startup validator with KanataManager
            startupValidator.configure(with: kanataManager)

            // Start startup validation asynchronously to avoid blocking UI
            Task {
                await Task.yield() // Let UI render first
                startupValidator.performStartupValidation()
                // Note: KEYPATH_STARTUP_MODE is cleared by StartupValidator after validation completes
            }

            // Check if we're returning from permission granting (Input Monitoring settings)
            let isReturningFromPermissionGrant = checkForPendingPermissionGrant()

            // Set up notification handlers for recovery actions
            setupRecoveryActionHandlers()

            // ContentView no longer forwards triggers directly; RecordingSection handles triggers via NotificationCenter

            // Start the auto-launch sequence ONLY if we're not returning from permission granting
            // Otherwise the auto-launch will reset showWizard to false
            if !isReturningFromPermissionGrant {
                Task {
                    AppLogger.shared.log("🚀 [ContentView] Starting auto-launch sequence")
                    await kanataManager.startAutoLaunch(presentWizardOnFailure: false)
                    AppLogger.shared.log("✅ [ContentView] Auto-launch sequence completed")
                    AppLogger.shared.log(
                        "✅ [ContentView] Post auto-launch - showWizard: \(kanataManager.showWizard)")
                    AppLogger.shared.log(
                        "✅ [ContentView] Post auto-launch - currentState: \(kanataManager.currentState.rawValue)"
                    )
                }
            } else {
                AppLogger.shared.log("🔧 [ContentView] Skipping auto-launch - returning from permission granting")

                // Log to file for debugging
                WizardLogger.shared.log("SKIPPING auto-launch (would reset wizard flag)")
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
        .onChange(of: kanataManager.showWizard) { _, shouldShow in
            AppLogger.shared.log("🔍 [ContentView] showWizard changed to: \(shouldShow)")
            AppLogger.shared.log(
                "🔍 [ContentView] Current kanataManager state: \(kanataManager.currentState.rawValue)"
            )
            AppLogger.shared.log(
                "🔍 [ContentView] Current errorReason: \(kanataManager.errorReason ?? "nil")")
            AppLogger.shared.log("🔍 [ContentView] Setting showingInstallationWizard = \(shouldShow)")
            showingInstallationWizard = shouldShow
            AppLogger.shared.log(
                "🔍 [ContentView] showingInstallationWizard is now: \(showingInstallationWizard)")
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
        .onChange(of: showingInstallationWizard) { _, showing in
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
    @Binding var recordedInput: String
    @Binding var recordedOutput: String
    @Binding var isRecording: Bool
    @Binding var isRecordingOutput: Bool
    @ObservedObject var kanataManager: KanataManager
    @Binding var keyboardCapture: KeyboardCapture?
    let showStatusMessage: (String) -> Void
    @Binding var showingDiagnostics: Bool
    @Binding var isSequenceMode: Bool
    @Binding var showPlaceholderText: Bool
    @State private var capturedInputSequence: KeySequence?
    @State private var capturedOutputSequence: KeySequence?
    @State private var showingConfigCorruptionAlert = false
    @State private var configCorruptionDetails = ""
    @State private var configRepairSuccessful = false
    @State private var showingRepairFailedAlert = false
    @State private var repairFailedDetails = ""
    @State private var failedConfigBackupPath = ""

    // Diagnostics: track last-known disabled state and reasons to avoid log spam
    @State private var lastInputDisabledReason: String = ""
    @State private var lastOutputDisabledReason: String = ""
    @State private var lastIsRecordingLogged: Bool = false

    // MARK: - Phase 1: Save Operation Debouncing

    @State private var saveDebounceTimer: Timer?
    private let saveDebounceDelay: TimeInterval = 0.5

    var body: some View {
        VStack(spacing: 16) {
            // Input + Output Containers with centered trailing overlay toggle
            ZStack(alignment: .trailing) {
                VStack(spacing: 16) {
                    // Input Recording Container
                    VStack(alignment: .leading, spacing: 8) {
                        // Input Key label with sequence toggle button
                        HStack {
                            Text("Input Key")
                                .font(.headline)
                                .accessibilityIdentifier("input-key-label")

                            Spacer()

                            Button(action: {
                                isSequenceMode.toggle()
                                showPlaceholderText = true
                            }, label: {
                                Image(systemName: "list.number")
                                    .font(.title2)
                                    .foregroundColor(isSequenceMode ? .white : .blue)
                            })
                            .buttonStyle(.plain)
                            .frame(width: 32, height: 32)
                            .background(isSequenceMode ? Color.blue : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                            .cornerRadius(6)
                            .help(isSequenceMode ? "Capture sequences of keys" : "Capture key combos")
                            .accessibilityIdentifier("sequence-mode-toggle")
                            .accessibilityLabel(isSequenceMode ? "Switch to combo mode" : "Switch to sequence mode")
                            .accessibilityHint("Toggle between combo capture and sequence capture modes")
                            .padding(.trailing, 5)
                        }

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
                                AppLogger.shared.log("🖱️ [UI] Input record button tapped (isRecording=\(isRecording))")
                                if isRecording {
                                    stopRecording()
                                } else {
                                    startRecording()
                                }
                            }, label: {
                                Image(systemName: getInputButtonIcon())
                                    .font(.title2)
                            })
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
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                    .accessibilityIdentifier("input-recording-section")
                    .accessibilityLabel("Input key recording section")

                    // Output Recording Container
                    VStack(alignment: .leading, spacing: 8) {
                        // Accessibility container for output recording section
                        Text("Output Key")
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
                            }, label: {
                                Image(systemName: getOutputButtonIcon())
                                    .font(.title2)
                            })
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
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                    .accessibilityIdentifier("output-recording-section")
                    .accessibilityLabel("Output key recording section")
                }
            }

            // Save Button - Outside containers
            HStack {
                Spacer()
                Button(action: {
                    debouncedSave()
                }, label: {
                    HStack {
                        if kanataManager.saveStatus.isActive {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                        Text(kanataManager.saveStatus.message.isEmpty ? "Save" : kanataManager.saveStatus.message)
                    }
                    .frame(minWidth: 100)
                })
                .buttonStyle(.borderedProminent)
                .disabled(capturedInputSequence == nil || capturedOutputSequence == nil || kanataManager.saveStatus.isActive)
                .accessibilityIdentifier("save-mapping-button")
                .accessibilityLabel(kanataManager.saveStatus.message.isEmpty ? "Save key mapping" : kanataManager.saveStatus.message)
                .accessibilityHint("Save the input and output key mapping to your configuration")
            }

            // Debug tools (placed below existing content, minimal styling)
            Divider().padding(.top, 4)
            HStack(spacing: 12) {
                Button("Debug: Start Input Recording") {
                    AppLogger.shared.log("🧪 [UI] Debug button: Start Input Recording")
                    NotificationCenter.default.post(name: Notification.Name("KeyPath.Local.TriggerStartRecording"), object: nil)
                }
                .buttonStyle(.bordered)

                Button("Open Logs") {
                    let logPath = NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log"
                    NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                    AppLogger.shared.log("📁 [UI] Opened debug log file")
                }
                .buttonStyle(.bordered)

                Spacer()
                Text("Debug tools").foregroundColor(.secondary).font(.caption)
            }
        }
        // Render-time diagnostics: log disabled reasons on appear and when relevant state changes
        .onAppear {
            logInputDisabledReason()
            logOutputDisabledReason()
        }
        .onChange(of: isRecording) { _ in
            AppLogger.shared.log("🔁 [UI] isRecording changed -> \(isRecording)")
            logInputDisabledReason()
        }
        .onChange(of: isRecordingOutput) { _ in
            AppLogger.shared.log("🔁 [UI] isRecordingOutput changed -> \(isRecordingOutput)")
            logOutputDisabledReason()
        }
        .onChange(of: kanataManager.isRunning) { _ in
            logInputDisabledReason(); logOutputDisabledReason()
        }
        .onChange(of: isSequenceMode) { _ in
            AppLogger.shared.log("🔁 [UI] isSequenceMode changed -> \(isSequenceMode ? "sequence" : "chord")")
        }
        // Debug: allow programmatic start of input recording
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("KeyPath.Local.TriggerStartRecording"))) { _ in
            AppLogger.shared.log("🧪 [RecordingSection] Received local trigger to start input recording")
            if !isRecording { startRecording() }
        }
        .alert("Configuration Issue Detected", isPresented: $showingConfigCorruptionAlert) {
            Button("OK") {
                showingConfigCorruptionAlert = false
            }
            Button("View Diagnostics") {
                showingConfigCorruptionAlert = false
                showingDiagnostics = true
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
                showingDiagnostics = true
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
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(kanataManager: kanataManager)
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

    private func logFocusState(prefix: String = "[UI]") {
        let isActive = NSApp.isActive
        let keyWindow = NSApp.keyWindow != nil
        let occlusion = NSApp.keyWindow?.occlusionState.rawValue ?? 0
        AppLogger.shared.log("🔍 \(prefix) Focus: appActive=\(isActive), keyWindow=\(keyWindow), occlusion=\(occlusion)")
    }

    private func inputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled() && !isRecording { reasons.append("notInstalled") }
        if NSApp.isActive == false { reasons.append("appNotActive") }
        if NSApp.keyWindow == nil { reasons.append("noKeyWindow") }
        return reasons.isEmpty ? "enabled" : reasons.joined(separator: "+")
    }

    private func outputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled() && !isRecordingOutput { reasons.append("notInstalled") }
        if NSApp.isActive == false { reasons.append("appNotActive") }
        if NSApp.keyWindow == nil { reasons.append("noKeyWindow") }
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

    private func startRecording() {
        AppLogger.shared.log("🚩 [UI] startRecording() entered")
        isRecording = true
        recordedInput = ""

        Task {
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            await MainActor.run {
                guard snapshot.keyPath.accessibility.isReady else {
                    recordedInput = "⚠️ Accessibility permission required for recording"
                    isRecording = false
                    return
                }
                if keyboardCapture == nil {
                    keyboardCapture = KeyboardCapture()
                    AppLogger.shared.log("🎹 [RecordingSection] KeyboardCapture initialized lazily for recording")
                }
                guard let capture = keyboardCapture else {
                    recordedInput = "⚠️ Failed to initialize keyboard capture"
                    isRecording = false
                    return
                }
                // Diagnostics: capture context
                let ff = FeatureFlags.captureListenOnlyEnabled
                AppLogger.shared.log("🔧 [UI] Capture context: sequenceMode=\(isSequenceMode ? "sequence" : "chord"), listenOnlyFlag=\(ff), kanataRunning=\(kanataManager.isRunning)")
                logFocusState()
                // Provide KanataManager so capture can choose listen-only vs suppress
                capture.setEventRouter(nil, kanataManager: kanataManager)

                // Use appropriate capture mode based on toggle
                let captureMode: CaptureMode = isSequenceMode ? .sequence : .chord

                // Add timeout protection to prevent UI from getting stuck
                let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        if isRecording {
                            AppLogger.shared.log("⚠️ [RecordingSection] Recording timeout - resetting state")
                            recordedInput = "⚠️ Recording timed out - try again"
                            isRecording = false
                            Task {
                                await MainActor.run {
                                    capture.stopCapture()
                                }
                            }
                        }
                    }
                }
                
                capture.startSequenceCapture(mode: captureMode) { keySequence in
                    timeoutTimer.invalidate() // Cancel timeout since we got a result
                    AppLogger.shared.log("✅ [UI] Input capture callback received: \(keySequence.displayString)")
                    capturedInputSequence = keySequence
                    recordedInput = keySequence.displayString
                    isRecording = false
                }
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        keyboardCapture?.stopCapture()
    }

    private func startOutputRecording() {
        isRecordingOutput = true
        recordedOutput = ""

        Task {
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            await MainActor.run {
                guard snapshot.keyPath.accessibility.isReady else {
                    recordedOutput = "⚠️ Accessibility permission required for recording"
                    isRecordingOutput = false
                    return
                }
                if keyboardCapture == nil {
                    keyboardCapture = KeyboardCapture()
                    AppLogger.shared.log("🎹 [RecordingSection] KeyboardCapture initialized for output recording")
                }
                guard let capture = keyboardCapture else {
                    recordedOutput = "⚠️ Failed to initialize keyboard capture"
                    isRecordingOutput = false
                    return
                }
                // Diagnostics: capture context
                let ff = FeatureFlags.captureListenOnlyEnabled
                AppLogger.shared.log("🔧 [UI] Output capture context: sequenceMode=\(isSequenceMode ? "sequence" : "chord"), listenOnlyFlag=\(ff), kanataRunning=\(kanataManager.isRunning)")
                logFocusState(prefix: "[UI:Output]")
                // Provide KanataManager so capture can choose listen-only vs suppress
                capture.setEventRouter(nil, kanataManager: kanataManager)

                // Use appropriate capture mode based on toggle
                let captureMode: CaptureMode = isSequenceMode ? .sequence : .chord

                // Add timeout protection to prevent UI from getting stuck
                let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        if isRecordingOutput {
                            AppLogger.shared.log("⚠️ [RecordingSection] Output recording timeout - resetting state")
                            recordedOutput = "⚠️ Recording timed out - try again"
                            isRecordingOutput = false
                            capture.stopCapture()
                        }
                    }
                }
                
                capture.startSequenceCapture(mode: captureMode) { keySequence in
                    timeoutTimer.invalidate() // Cancel timeout since we got a result
                    capturedOutputSequence = keySequence
                    recordedOutput = keySequence.displayString
                    isRecordingOutput = false
                }
            }
        }
    }

    private func stopOutputRecording() {
        isRecordingOutput = false
        keyboardCapture?.stopCapture()
    }

    private func getInputDisplayText() -> String {
        if !recordedInput.isEmpty {
            return recordedInput
        } else if isRecording {
            let base = isSequenceMode ? "Press keys in sequence..." : "Press key combination..."
            let effective = FeatureFlags.captureListenOnlyEnabled && kanataManager.isRunning
            return effective ? base + " – Effective (mapped)" : base + " – Raw (direct)"
        } else if showPlaceholderText {
            return isSequenceMode ? "Press keys in sequence..." : "Press key combination..."
        } else {
            return ""
        }
    }

    private func getOutputDisplayText() -> String {
        if !recordedOutput.isEmpty {
            return recordedOutput
        } else if isRecordingOutput {
            let base = isSequenceMode ? "Press keys in sequence..." : "Press key combination..."
            let effective = FeatureFlags.captureListenOnlyEnabled && kanataManager.isRunning
            return effective ? base + " – Effective (mapped)" : base + " – Raw (direct)"
        } else if showPlaceholderText {
            return isSequenceMode ? "Press keys in sequence..." : "Press key combination..."
        } else {
            return ""
        }
    }

    // MARK: - Phase 1: Debounced Save Implementation

    private func debouncedSave() {
        // Cancel any existing timer
        saveDebounceTimer?.invalidate()

        // Show saving state immediately for user feedback via KanataManager.saveStatus
        AppLogger.shared.log("💾 [Save] Debounced save initiated - starting timer")

        // Create new timer
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) { _ in
            AppLogger.shared.log("💾 [Save] Debounce timer fired - executing save")
            Task {
                await saveKeyPath()
            }
        }
    }

    private func saveKeyPath() async {
        AppLogger.shared.log("💾 [Save] ========== SAVE OPERATION START ==========")

        do {
            guard let inputSequence = capturedInputSequence,
                  let outputSequence = capturedOutputSequence
            else {
                AppLogger.shared.log("❌ [Save] Missing captured sequences")
                await MainActor.run {
                    showStatusMessage("❌ Please capture both input and output keys first")
                }
                return
            }

            AppLogger.shared.log("💾 [Save] Saving mapping: \(inputSequence.displayString) → \(outputSequence.displayString)")

            // Use KanataConfigGenerator to create proper configuration
            let configGenerator = KanataConfigGenerator(kanataManager: kanataManager)
            let generatedConfig = try await configGenerator.generateMapping(input: inputSequence, output: outputSequence)

            AppLogger.shared.log("💾 [Save] Generated config via Claude API")

            // Save the generated configuration
            try await kanataManager.saveGeneratedConfiguration(generatedConfig)

            AppLogger.shared.log("💾 [Save] Configuration saved successfully")

            // Show status message and clear the form
            await MainActor.run {
                showStatusMessage("Key mapping saved: \(inputSequence.displayString) → \(outputSequence.displayString)")

                // Clear the form
                recordedInput = ""
                recordedOutput = ""
                capturedInputSequence = nil
                capturedOutputSequence = nil
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

                case .preSaveValidationFailed(_, _),
                     .postSaveValidationFailed(_):
                    // These are handled by KanataManager's validation dialogs
                    AppLogger.shared.log("⚠️ [Save] Validation error handled by KanataManager dialogs")

                case .startupValidationFailed(_, _):
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
