import SwiftUI

struct HelperInstallationView: View {
    @Environment(\.dismiss) private var dismiss
    private let helperManager = PrivilegedHelperManager.shared
    @State private var isInstalling = false
    @State private var installationSuccess = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Install Privileged Helper")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Enable passwordless configuration reloading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Benefits Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Benefits:")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No more password prompts when saving configurations")
                        .font(.body)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Instant config reloading without interruption")
                        .font(.body)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Professional user experience similar to Karabiner-Elements")
                        .font(.body)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Security Note
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Security Information")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                Text("The privileged helper is a secure, sandboxed system service that can only reload Kanata configurations. It cannot access other system resources or personal data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
            
            Spacer()
            
            // Status and Action Buttons
            VStack(spacing: 16) {
                if isInstalling {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Installing helper...")
                            .font(.headline)
                    }
                    .padding()
                } else if installationSuccess {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            Text("Installation Successful!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        
                        Text("Privileged helper is now installed and ready to use.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Continue") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    VStack(spacing: 16) {
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        HStack(spacing: 16) {
                            Button("Skip for Now") {
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Install Helper") {
                                Task {
                                    await installHelper()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 600)
        .onAppear {
            checkHelperStatus()
        }
    }
    
    private func checkHelperStatus() {
        if helperManager.isHelperInstalled() {
            installationSuccess = true
        }
    }
    
    private func installHelper() async {
        isInstalling = true
        errorMessage = ""
        
        let success = await helperManager.installHelper()
        
        await MainActor.run {
            isInstalling = false
            if success {
                installationSuccess = true
            } else {
                errorMessage = "Failed to install privileged helper. Please check the console for more details and try again."
            }
        }
    }
}

#Preview {
    HelperInstallationView()
}