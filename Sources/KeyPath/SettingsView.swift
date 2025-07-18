import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var kanataManager = KanataManager()
    
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
                
                VStack(spacing: 12) {
                    Button("Restart Kanata") {
                        Task {
                            await kanataManager.restartKanata()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Refresh Status") {
                        Task {
                            await kanataManager.updateStatus()
                        }
                    }
                    .buttonStyle(.bordered)
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