import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Installation Status")
                        .font(.headline)
                    
                    Text(kanataManager.getInstallationStatus())
                        .font(.body)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manual Controls")
                        .font(.headline)
                    
                    Text("Kanata starts automatically when KeyPath launches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button(kanataManager.isRunning ? "Stop Kanata" : "Start Kanata") {
                                Task {
                                    if kanataManager.isRunning {
                                        await kanataManager.stopKanata()
                                    } else {
                                        await kanataManager.startKanata()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Restart Kanata") {
                                Task {
                                    await kanataManager.restartKanata()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!kanataManager.isRunning)
                        }
                        
                        HStack(spacing: 12) {
                            Button("🚨 Emergency Stop") {
                                Task {
                                    await kanataManager.emergencyStop()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(!kanataManager.isRunning)
                            
                            Button("Refresh Status") {
                                Task {
                                    await kanataManager.updateStatus()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                if let error = kanataManager.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            Task {
                await kanataManager.updateStatus()
            }
        }
    }
}