import SwiftUI

struct ContentView: View {
    @StateObject private var keyboardCapture = KeyboardCapture()
    @StateObject private var kanataManager = KanataManager()
    @State private var isRecording = false
    @State private var recordedInput = ""
    @State private var recordedOutput = ""
    @State private var showingInstaller = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("KeyPath Recorder")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Record keyboard shortcuts and remap them with Kanata")
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
                        .disabled(kanataManager.isRunning && !isRecording)
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
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Status Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Kanata Status:")
                    .font(.headline)
                
                HStack {
                    Circle()
                        .fill(kanataManager.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    
                    Text(kanataManager.isRunning ? "Running" : "Stopped")
                        .font(.body)
                    
                    Spacer()
                    
                    if let error = kanataManager.lastError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Action Buttons
            HStack(spacing: 16) {
                Button("Settings") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
                
                Button("Installer") {
                    showingInstaller = true
                }
                .buttonStyle(.bordered)
                
                Button("Restart Kanata") {
                    restartKanata()
                }
                .buttonStyle(.bordered)
                .disabled(!kanataManager.isRunning)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showingInstaller) {
            InstallerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            Task {
                await kanataManager.updateStatus()
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
                try await kanataManager.saveConfiguration(input: recordedInput, output: recordedOutput)
                
                // Clear the form
                recordedInput = ""
                recordedOutput = ""
                
                // Update status
                await kanataManager.updateStatus()
            } catch {
                print("Error saving configuration: \(error)")
            }
        }
    }
    
    private func restartKanata() {
        Task {
            await kanataManager.restartKanata()
        }
    }
}

#Preview {
    ContentView()
}