import SwiftUI

struct ContentView: View {
    @StateObject private var keyboardCapture = KeyboardCapture()
    @EnvironmentObject var kanataManager: KanataManager
    @State private var isRecording = false
    @State private var recordedInput = ""
    @State private var recordedOutput = ""
    @State private var showingSettings = false
    @State private var showingInstallationWizard = false
    @State private var hasCheckedRequirements = false
    @State private var saveMessage = ""
    @State private var saveMessageColor = Color.green
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("KeyPath Recorder")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Record keyboard shortcuts and create custom key mappings")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Recording Section
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
                        
                        Button(isRecording ? "Stop Recording" : "Record Input") {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!kanataManager.isCompletelyInstalled() && !isRecording)
                    }
                }
                
                // Output Mapping
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Key:")
                        .font(.headline)
                    
                    TextField("Enter output key (e.g., 'escape', 'a', 'space')", text: $recordedOutput)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Save Button
                Button("Save KeyPath") {
                    saveKeyPath()
                }
                .buttonStyle(.borderedProminent)
                .disabled(recordedInput.isEmpty || recordedOutput.isEmpty)
                
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
            
            // Status Section
            VStack(alignment: .leading, spacing: 8) {
                Text("KeyPath Status:")
                    .font(.headline)
                
                HStack {
                    Circle()
                        .fill(kanataManager.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    
                    Text(kanataManager.isRunning ? "Ready" : "Not Ready")
                        .font(.body)
                    
                    Spacer()
                    
                    if let error = kanataManager.lastError {
                        VStack(alignment: .trailing, spacing: 4) {
                            Button("⚠️ Setup Required") {
                                showingInstallationWizard = true
                            }
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                            .buttonStyle(.plain)
                            
                            if error.contains("sudo ./install-system.sh") {
                                Text("Tap to run installer")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Action Buttons
            Button("Settings") {
                showingSettings = true
            }
            .buttonStyle(.bordered)
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingInstallationWizard) {
            InstallationWizardView()
                .onAppear {
                    print("🔍 [ContentView] Installation wizard sheet is being presented")
                }
        }
        .onAppear {
            print("🔍 [ContentView] onAppear called")
            if !hasCheckedRequirements {
                print("🔍 [ContentView] First time checking requirements")
                checkRequirementsAndShowWizard()
                hasCheckedRequirements = true
            }
        }
        .onChange(of: kanataManager.isRunning) { _ in
            print("🔍 [ContentView] isRunning changed to: \(kanataManager.isRunning)")
            if hasCheckedRequirements {
                checkRequirementsAndShowWizard()
            }
        }
        .onChange(of: kanataManager.lastError) { _ in
            print("🔍 [ContentView] lastError changed to: \(kanataManager.lastError ?? "nil")")
            checkRequirementsAndShowWizard()
        }
    }
    
    private func checkRequirementsAndShowWizard() {
        Task {
            await kanataManager.updateStatus()
            
            await MainActor.run {
                // Show installation wizard for new users or when permissions are missing
                let completelyInstalled = kanataManager.isCompletelyInstalled()
                let hasPermissions = kanataManager.hasInputMonitoringPermission()
                let isRunning = kanataManager.isRunning
                
                print("🔍 [ContentView] Completely installed: \(completelyInstalled), Has permissions: \(hasPermissions), Is running: \(isRunning)")
                
                // Show wizard if not completely installed, missing permissions, or service failing to run
                let hasSetupError = kanataManager.lastError?.contains("Setup Required") == true
                let serviceNotWorking = !isRunning // If Kanata isn't running, we need to fix something
                let shouldShowWizard = !completelyInstalled || !hasPermissions || serviceNotWorking || hasSetupError
                
                print("🔍 [ContentView] Should show wizard: \(shouldShowWizard)")
                print("🔍 [ContentView] Has setup error: \(hasSetupError)")
                print("🔍 [ContentView] Last error: \(kanataManager.lastError ?? "none")")
                
                if shouldShowWizard {
                    print("🔍 [ContentView] Showing installation wizard")
                    print("🔍 [ContentView] Current showingInstallationWizard state: \(showingInstallationWizard)")
                    
                    // Use a small delay to ensure SwiftUI processes the state change
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingInstallationWizard = true
                        print("🔍 [ContentView] Set showingInstallationWizard to: \(showingInstallationWizard)")
                    }
                } else {
                    print("🔍 [ContentView] Not showing installation wizard")
                    showingInstallationWizard = false
                }
            }
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

#Preview {
    ContentView()
        .environmentObject(KanataManager())
}