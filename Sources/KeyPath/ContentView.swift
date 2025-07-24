import SwiftUI

struct ContentView: View {
    @StateObject private var keyboardCapture = KeyboardCapture()
    @EnvironmentObject var kanataManager: KanataManager
    @State private var isRecording = false
    @State private var isRecordingOutput = false
    @State private var recordedInput = ""
    @State private var recordedOutput = ""
    @State private var showingInstallationWizard = false
    @State private var showingHelperInstallation = false
    @State private var hasCheckedRequirements = false
    @State private var saveMessage = ""
    @State private var saveMessageColor = Color.green
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            ContentViewHeader()
            
            // Recording Section
            RecordingSection(recordedInput: $recordedInput, recordedOutput: $recordedOutput,
                             isRecording: $isRecording, isRecordingOutput: $isRecordingOutput,
                             kanataManager: kanataManager, keyboardCapture: keyboardCapture,
                             saveMessage: $saveMessage, saveMessageColor: $saveMessageColor,
                             showingHelperInstallation: $showingHelperInstallation)
            
            // Error Section (only show if there's an error)
            if let error = kanataManager.lastError, !kanataManager.isRunning {
                ErrorSection(kanataManager: kanataManager, showingInstallationWizard: $showingInstallationWizard, error: error)
            }
        }
        .padding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showingInstallationWizard) {
            InstallationWizardView()
                .onAppear {
                    AppLogger.shared.log("🔍 [ContentView] Installation wizard sheet is being presented")
                }
        }
        .sheet(isPresented: $showingHelperInstallation) {
            HelperInstallationView()
        }
        .onAppear {
            AppLogger.shared.log("🔍 [ContentView] onAppear called")
            
            if !hasCheckedRequirements {
                AppLogger.shared.log("🔍 [ContentView] First time checking requirements")
                checkRequirementsAndShowWizard()
                hasCheckedRequirements = true
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
    }
    
    private func checkRequirementsAndShowWizard() {
        Task {
            await kanataManager.updateStatus()
            
            await MainActor.run {
                let completelyInstalled = kanataManager.isCompletelyInstalled()
                let hasPermissions = kanataManager.hasAllRequiredPermissions()
                let isRunning = kanataManager.isRunning
                
                AppLogger.shared.log("🔍 [ContentView] DETAILED CHECK:")
                AppLogger.shared.log("🔍 [ContentView] - Completely installed: \(completelyInstalled)")
                AppLogger.shared.log("🔍 [ContentView] - Has ALL permissions: \(hasPermissions)")
                AppLogger.shared.log("🔍 [ContentView] - Is running: \(isRunning)")
                
                let inputMonitoringDirect = kanataManager.hasInputMonitoringPermission()
                let accessibilityDirect = kanataManager.hasAccessibilityPermission()
                AppLogger.shared.log("🔍 [ContentView] - Input Monitoring (direct): \(inputMonitoringDirect)")
                AppLogger.shared.log("🔍 [ContentView] - Accessibility (direct): \(accessibilityDirect)")
                
                let shouldShowWizard = !completelyInstalled || !hasPermissions
                
                AppLogger.shared.log("🔍 [ContentView] Should show wizard: \(shouldShowWizard)")
                
                if shouldShowWizard {
                    AppLogger.shared.log("🔍 [ContentView] Showing installation wizard")
                    AppLogger.shared.log("🔍 [ContentView] Current showingInstallationWizard state: \(showingInstallationWizard)")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingInstallationWizard = true
                        AppLogger.shared.log("🔍 [ContentView] Set showingInstallationWizard to: \(showingInstallationWizard)")
                    }
                } else {
                    AppLogger.shared.log("🔍 [ContentView] Not showing installation wizard")
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
    @Binding var saveMessage: String
    @Binding var saveMessageColor: Color
    @Binding var showingHelperInstallation: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Input Recording
            VStack(alignment: .leading, spacing: 8) {
                Text("Input Key:")
                    .font(.headline)
                
                HStack {
                    Text(recordedInput.isEmpty ? "Press a key..." : recordedInput)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
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
                    Text(recordedOutput.isEmpty ? "Press keys..." : recordedOutput)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
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
                Button("Save") {
                    saveKeyPath()
                }
                .buttonStyle(.borderedProminent)
                .disabled(recordedInput.isEmpty || recordedOutput.isEmpty)
            }
            
            // Save Message
            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .foregroundColor(saveMessageColor)
                    .font(.caption)
                    .animation(.easeInOut(duration: 0.3), value: saveMessage)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
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
        }
    }
    
    private func stopOutputRecording() {
        isRecordingOutput = false
        keyboardCapture.stopCapture()
    }
    
    private func saveKeyPath() {
        Task {
            do {
                let inputKey = recordedInput
                let outputKey = recordedOutput
                
                try await kanataManager.saveConfiguration(input: inputKey, output: outputKey)
                
                // Show success message
                saveMessage = "✅ Saved: \(inputKey) → \(outputKey)"
                saveMessageColor = Color.green
                
                // Clear the form
                recordedInput = ""
                recordedOutput = ""
                
                // Update status
                await kanataManager.updateStatus()
                
                // Check if we should offer helper installation for passwordless reloading
                await MainActor.run {
                    let helperManager = PrivilegedHelperManager.shared
                    if !helperManager.isHelperInstalled() {
                        // Show helper installation offer after successful save
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            showingHelperInstallation = true
                        }
                    }
                }
                
                // Clear message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    saveMessage = ""
                }
            } catch {
                // Show error message
                saveMessage = "❌ Error saving: \(error.localizedDescription)"
                saveMessageColor = Color.red
                
                // Clear error message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    saveMessage = ""
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

#Preview {
    ContentView()
        .environmentObject(KanataManager())
}