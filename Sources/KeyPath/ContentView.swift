import SwiftUI

struct ContentView: View {
    @StateObject private var keyboardCapture = KeyboardCapture()
    @EnvironmentObject var kanataManager: KanataManager
    @State private var isRecording = false
    @State private var isRecordingOutput = false
    @State private var recordedInput = ""
    @State private var recordedOutput = ""
    @State private var showingInstallationWizard = false
    @State private var hasCheckedRequirements = false
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var showingEmergencyAlert = false
    
    // Phase 2: Lifecycle Manager (will be initialized in onAppear to use injected kanataManager)
    @State private var lifecycleManager: KanataLifecycleManager?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            ContentViewHeader()
            
            // Recording Section
            RecordingSection(recordedInput: $recordedInput, recordedOutput: $recordedOutput,
                             isRecording: $isRecording, isRecordingOutput: $isRecordingOutput,
                             kanataManager: kanataManager, keyboardCapture: keyboardCapture,
                             showStatusMessage: showStatusMessage, lifecycleManager: lifecycleManager)
            
            // Error Section (only show if there's an error)
            if let error = kanataManager.lastError, !kanataManager.isRunning {
                ErrorSection(kanataManager: kanataManager, showingInstallationWizard: $showingInstallationWizard, error: error)
            }
            
            // Status Message - Fixed at bottom with stable layout
            StatusMessageView(message: statusMessage, isVisible: showStatusMessage)
                .frame(height: showStatusMessage ? nil : 0)
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
        .sheet(isPresented: $showingInstallationWizard) {
            InstallationWizardView()
                .onAppear {
                    AppLogger.shared.log("🔍 [ContentView] Installation wizard sheet is being presented")
                }
                .environmentObject(kanataManager)
        }
        .onAppear {
            AppLogger.shared.log("🔍 [ContentView] onAppear called")
            
            // Phase 2: Initialize lifecycle manager
            if lifecycleManager == nil {
                AppLogger.shared.log("🏗️ [ContentView] Initializing KanataLifecycleManager")
                lifecycleManager = KanataLifecycleManager(kanataManager: kanataManager)
                
                // Start the lifecycle management
                Task {
                    await lifecycleManager?.initialize()
                }
            }
            
            if !hasCheckedRequirements {
                AppLogger.shared.log("🔍 [ContentView] First time checking requirements")
                checkRequirementsAndShowWizard()
                hasCheckedRequirements = true
            }
            
            // Start monitoring for emergency stop sequence
            keyboardCapture.startEmergencyMonitoring {
                showStatusMessage(message: "🚨 Emergency stop activated - Kanata stopped")
                showingEmergencyAlert = true
            }
        }
        .onChange(of: kanataManager.isRunning) { value in
            AppLogger.shared.log("🔍 [ContentView] isRunning changed to: \(value)")
            if hasCheckedRequirements {
                checkRequirementsAndShowWizard()
            }
        }
        .onChange(of: kanataManager.lastError) { value in
            AppLogger.shared.log("🔍 [ContentView] lastError changed to: \(value ?? "nil")")
            checkRequirementsAndShowWizard()
        }
        .onChange(of: kanataManager.lastConfigUpdate) { _ in
            // Show status message when config is updated externally
            showStatusMessage(message: "Key mappings updated")
        }
        .onDisappear {
            // Stop emergency monitoring when view disappears
            keyboardCapture.stopEmergencyMonitoring()
        }
        .alert("Emergency Stop Activated", isPresented: $showingEmergencyAlert) {
            Button("OK") {
                showingEmergencyAlert = false
            }
        } message: {
            Text("The Kanata emergency stop sequence (Ctrl+Space+Esc) was detected. Kanata has been stopped for safety.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWizard"))) { _ in
            showingInstallationWizard = true
        }
    }
    
    private func showStatusMessage(message: String) {
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
    
    private func checkRequirementsAndShowWizard() {
        Task {
            await kanataManager.updateStatus()
            
            await MainActor.run {
                let status = kanataManager.getSystemRequirementsStatus()
                let isRunning = kanataManager.isRunning
                
                AppLogger.shared.log("🔍 [ContentView] SYSTEM REQUIREMENTS CHECK:")
                AppLogger.shared.log("🔍 [ContentView] - Kanata installed: \(status.installed)")
                AppLogger.shared.log("🔍 [ContentView] - Permissions granted: \(status.permissions)")
                AppLogger.shared.log("🔍 [ContentView] - Karabiner driver: \(status.driver)")
                AppLogger.shared.log("🔍 [ContentView] - Karabiner daemon: \(status.daemon)")
                AppLogger.shared.log("🔍 [ContentView] - Kanata running: \(isRunning)")
                
                let inputMonitoringDirect = kanataManager.hasInputMonitoringPermission()
                let accessibilityDirect = kanataManager.hasAccessibilityPermission()
                AppLogger.shared.log("🔍 [ContentView] - Input Monitoring (direct): \(inputMonitoringDirect)")
                AppLogger.shared.log("🔍 [ContentView] - Accessibility (direct): \(accessibilityDirect)")
                
                let shouldShowWizard = !status.installed || !status.permissions || !status.driver || !status.daemon || !isRunning
                
                AppLogger.shared.log("🔍 [ContentView] Should show wizard: \(shouldShowWizard)")
                
                if shouldShowWizard {
                    AppLogger.shared.log("🔍 [ContentView] Showing installation wizard - missing requirements")
                    AppLogger.shared.log("🔍 [ContentView] Current showingInstallationWizard state: \(showingInstallationWizard)")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingInstallationWizard = true
                        AppLogger.shared.log("🔍 [ContentView] Set showingInstallationWizard to: \(showingInstallationWizard)")
                    }
                } else {
                    AppLogger.shared.log("🔍 [ContentView] All requirements met - no wizard needed")
                    showingInstallationWizard = false
                }
            }
        }
    }
}

struct ContentViewHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
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
    @ObservedObject var keyboardCapture: KeyboardCapture
    let showStatusMessage: (String) -> Void
    
    // Phase 2: Lifecycle Manager Integration
    let lifecycleManager: KanataLifecycleManager?
    @State private var outputInactivityTimer: Timer?
    @State private var showingConfigCorruptionAlert = false
    @State private var configCorruptionDetails = ""
    @State private var configRepairSuccessful = false
    @State private var showingRepairFailedAlert = false
    @State private var repairFailedDetails = ""
    @State private var failedConfigBackupPath = ""
    
    // MARK: - Phase 1: Save Operation Debouncing
    @State private var isSaving = false
    @State private var saveDebounceTimer: Timer?
    private let saveDebounceDelay: TimeInterval = 0.5

    var body: some View {
        VStack(spacing: 16) {
            // Input Recording
            VStack(alignment: .leading, spacing: 8) {
                Text("Input Key:")
                    .font(.headline)
                
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
                }
            }
            
            // Output Recording
            VStack(alignment: .leading, spacing: 8) {
                Text("Output Key:")
                    .font(.headline)
                
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
                }
            }
            
            // Save Button
            HStack {
                Spacer()
                Button(action: {
                    debouncedSave()
                }) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                        Text(isSaving ? "Saving..." : "Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recordedInput.isEmpty || recordedOutput.isEmpty || isSaving)
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
    }

    private func getInputButtonIcon() -> String {
        if isRecording {
            return "xmark.circle.fill"
        } else if recordedInput.isEmpty {
            return "play.circle.fill"
        } else {
            return "arrow.clockwise.circle.fill"
        }
    }
    
    private func getOutputButtonIcon() -> String {
        if isRecordingOutput {
            return "xmark.circle.fill"
        } else if recordedOutput.isEmpty {
            return "play.circle.fill"
        } else {
            return "arrow.clockwise.circle.fill"
        }
    }
    
    private func startRecording() {
        isRecording = true
        recordedInput = ""
        
        keyboardCapture.startCapture { keyName in
            recordedInput = keyName
            isRecording = false
        }
    }
    
    private func stopRecording() {
        isRecording = false
        keyboardCapture.stopCapture()
    }
    
    private func startOutputRecording() {
        isRecordingOutput = true
        recordedOutput = ""
        
        keyboardCapture.startContinuousCapture { keyName in
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
        keyboardCapture.stopCapture()
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
            return recordedInput
        } else if isRecording {
            return "Press a key..."
        } else {
            return ""
        }
    }
    
    private func getOutputDisplayText() -> String {
        if !recordedOutput.isEmpty {
            return recordedOutput
        } else if isRecordingOutput {
            return "Press keys..."
        } else {
            return ""
        }
    }
    
    // MARK: - Phase 1: Debounced Save Implementation
    private func debouncedSave() {
        // Cancel any existing timer
        saveDebounceTimer?.invalidate()
        
        // Show saving state immediately for user feedback
        isSaving = true
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
            let inputKey = recordedInput
            let outputKey = recordedOutput
            
            AppLogger.shared.log("💾 [Save] Saving mapping: \(inputKey) → \(outputKey)")
            
            // Phase 2: Use lifecycle manager if available, otherwise fall back to direct KanataManager
            if let lifecycleManager = lifecycleManager {
                AppLogger.shared.log("💾 [Save] Using KanataLifecycleManager for save operation")
                await lifecycleManager.applyConfiguration(input: inputKey, output: outputKey)
            } else {
                AppLogger.shared.log("💾 [Save] Using direct KanataManager for save operation")
                try await kanataManager.saveConfiguration(input: inputKey, output: outputKey)
            }
            
            AppLogger.shared.log("💾 [Save] Configuration saved successfully")
            
            // Show status message
            await MainActor.run {
                showStatusMessage("Key mapping saved: \(inputKey) → \(outputKey)")
                
                // Clear the form
                recordedInput = ""
                recordedOutput = ""
                isSaving = false
            }
            
            // Update status
            AppLogger.shared.log("💾 [Save] Updating manager status...")
            await kanataManager.updateStatus()
            
            AppLogger.shared.log("💾 [Save] ========== SAVE OPERATION COMPLETE ==========")
        } catch {
            AppLogger.shared.log("❌ [Save] Error during save operation: \(error)")
            
            // Reset saving state
            await MainActor.run {
                isSaving = false
            }
            
                // Handle specific config errors
                if let configError = error as? ConfigError {
                    switch configError {
                    case .corruptedConfigDetected(let errors):
                        configCorruptionDetails = """
                        Configuration corruption detected:
                        
                        \(errors.joined(separator: "\n"))
                        
                        KeyPath attempted automatic repair. If the repair was successful, your mapping has been saved with a corrected configuration. If repair failed, a safe fallback configuration was applied.
                        """
                        await MainActor.run {
                            configRepairSuccessful = false
                            showingConfigCorruptionAlert = true
                            showStatusMessage("⚠️ Config repaired automatically")
                        }
                        
                    case .claudeRepairFailed(let reason):
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
                    
                    case .repairFailedNeedsUserAction(let originalConfig, _, let originalErrors, let repairErrors, let mappings):
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
                        AppLogger.shared.log("🔄 [UI] Fix Issues button clicked - attempting to restart Kanata service")
                        await kanataManager.startKanata()
                        await kanataManager.updateStatus()
                        AppLogger.shared.log("🔄 [UI] Fix Issues completed - service status: \(kanataManager.isRunning)")
                    }
                    showingInstallationWizard = true
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
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isVisible)
    }
    
    private var iconName: String {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            return "xmark.circle.fill"
        } else if message.contains("⚠️") || message.contains("Config repaired") || message.contains("backed up") {
            return "exclamationmark.triangle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            return .red
        } else if message.contains("⚠️") || message.contains("Config repaired") || message.contains("backed up") {
            return .orange
        } else {
            return .green
        }
    }
    
    private var backgroundColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            return Color.red.opacity(0.1)
        } else if message.contains("⚠️") || message.contains("Config repaired") || message.contains("backed up") {
            return Color.orange.opacity(0.1)
        } else {
            return Color.green.opacity(0.1)
        }
    }
    
    private var borderColor: Color {
        if message.contains("❌") || message.contains("Error") || message.contains("Failed") {
            return Color.red.opacity(0.3)
        } else if message.contains("⚠️") || message.contains("Config repaired") || message.contains("backed up") {
            return Color.orange.opacity(0.3)
        } else {
            return Color.green.opacity(0.3)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(KanataManager())
}