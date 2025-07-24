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
    @State private var saveMessage = ""
    @State private var saveMessageColor = Color.green
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
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
            
            // Error Section (only show if there's an error)
            if let error = kanataManager.lastError, !kanataManager.isRunning {
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
                                print("🔄 [UI] Fix Issues button clicked - attempting to restart Kanata service")
                                await kanataManager.autoStartKanata()
                                await kanataManager.updateStatus()
                                print("🔄 [UI] Fix Issues completed - service status: \(kanataManager.isRunning)")
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
        .padding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
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
    
    private func checkRequirementsAndShowWizard() {
        Task {
            await kanataManager.updateStatus()
            
            await MainActor.run {
                // Show installation wizard for new users or when permissions are missing
                let completelyInstalled = kanataManager.isCompletelyInstalled()
                let hasPermissions = kanataManager.hasInputMonitoringPermission()
                let isRunning = kanataManager.isRunning
                
                print("🔍 [ContentView] Completely installed: \(completelyInstalled), Has permissions: \(hasPermissions), Is running: \(isRunning)")
                
                // Show wizard if not completely installed, missing permissions, or setup required
                let hasSetupError = kanataManager.lastError?.contains("Setup Required") == true
                // Only show wizard for missing components/permissions, not just service not running
                let shouldShowWizard = !completelyInstalled || !hasPermissions || hasSetupError
                
                print("🔍 [ContentView] Should show wizard: \(shouldShowWizard)")
                print("🔍 [ContentView] Has setup error: \(hasSetupError)")
                print("🔍 [ContentView] Last error: \(kanataManager.lastError ?? "none")")
                print("🔍 [ContentView] Reasons: !completelyInstalled=\(!completelyInstalled), !hasPermissions=\(!hasPermissions), hasSetupError=\(hasSetupError)")
                
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