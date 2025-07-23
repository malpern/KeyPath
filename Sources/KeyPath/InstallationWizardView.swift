import SwiftUI

struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    @StateObject private var installer = KeyPathInstaller()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Welcome to KeyPath")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Let's set up your keyboard remapping system")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Installation Progress
                VStack(spacing: 20) {
                    InstallationStepView(
                        step: 1,
                        title: "Install Kanata Engine",
                        description: "Installs the keyboard remapping engine with CMD key support",
                        status: installer.binaryInstallStatus,
                        isActive: installer.currentStep >= 1
                    )
                    
                    InstallationStepView(
                        step: 2,
                        title: "Setup System Service",
                        description: "Configures automatic startup and permissions",
                        status: installer.serviceInstallStatus,
                        isActive: installer.currentStep >= 2
                    )
                    
                    InstallationStepView(
                        step: 3,
                        title: "Install Karabiner Driver",
                        description: "Installs required system driver for macOS compatibility",
                        status: installer.driverInstallStatus,
                        isActive: installer.currentStep >= 3
                    )
                }
                
                // Installation Messages
                if !installer.statusMessage.isEmpty {
                    Text(installer.statusMessage)
                        .font(.caption)
                        .foregroundColor(installer.isError ? .red : .blue)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 16) {
                    if installer.installationComplete {
                        Button("🎉 Start Using KeyPath") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else if installer.isInstalling {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Installing...")
                                .font(.headline)
                        }
                        .padding()
                    } else {
                        Button("Install KeyPath") {
                            Task {
                                await installer.performTransparentInstallation(kanataManager: kanataManager)
                                await kanataManager.updateStatus()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding(40)
            .navigationTitle("KeyPath Setup")
            .toolbar(.hidden, for: .windowToolbar)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            installer.checkInitialState()
        }
    }
}

struct InstallationStepView: View {
    let step: Int
    let title: String
    let description: String
    let status: InstallationStatus
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Step indicator
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 40, height: 40)
                
                Group {
                    switch status {
                    case .notStarted:
                        Text("\(step)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(isActive ? .white : .secondary)
                    case .inProgress:
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.white)
                    case .completed:
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    case .failed:
                        Image(systemName: "xmark")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Step content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isActive ? .primary : .secondary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private var circleColor: Color {
        switch status {
        case .notStarted:
            return isActive ? .blue : .gray.opacity(0.3)
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

enum InstallationStatus {
    case notStarted
    case inProgress
    case completed
    case failed
}

@MainActor
class KeyPathInstaller: ObservableObject {
    @Published var currentStep = 0
    @Published var isInstalling = false
    @Published var installationComplete = false
    @Published var statusMessage = ""
    @Published var isError = false
    
    @Published var binaryInstallStatus: InstallationStatus = .notStarted
    @Published var serviceInstallStatus: InstallationStatus = .notStarted
    @Published var driverInstallStatus: InstallationStatus = .notStarted
    
    func checkInitialState() {
        // Check what's already installed
        let manager = KanataManager()
        
        if manager.isInstalled() {
            binaryInstallStatus = .completed
            currentStep = max(currentStep, 1)
        }
        
        if manager.isServiceInstalled() {
            serviceInstallStatus = .completed
            currentStep = max(currentStep, 2)
        }
        
        // Check if Karabiner driver is installed
        if manager.isKarabinerDriverInstalled() {
            driverInstallStatus = .completed
            currentStep = max(currentStep, 3)
        }
        
        if binaryInstallStatus == .completed && 
           serviceInstallStatus == .completed && 
           driverInstallStatus == .completed {
            installationComplete = true
            statusMessage = "KeyPath is ready to use!"
        }
    }
    
    func performTransparentInstallation(kanataManager: KanataManager) async {
        isInstalling = true
        isError = false
        
        // Show all steps as in progress
        currentStep = 1
        binaryInstallStatus = .inProgress
        serviceInstallStatus = .inProgress
        driverInstallStatus = .inProgress
        statusMessage = "Installing KeyPath components..."
        
        // Perform the transparent installation
        let success = await kanataManager.performTransparentInstallation()
        
        if success {
            // Mark all as completed
            binaryInstallStatus = .completed
            serviceInstallStatus = .completed
            driverInstallStatus = .completed
            currentStep = 3
            installationComplete = true
            statusMessage = "🎉 Installation complete! KeyPath is ready to use."
        } else {
            // Mark as failed
            binaryInstallStatus = .failed
            serviceInstallStatus = .failed
            driverInstallStatus = .failed
            statusMessage = "❌ Installation was cancelled or failed. Please try again."
            isError = true
        }
        
        isInstalling = false
    }
    
    // Legacy method - kept for potential future use
    func performInstallation() async {
        await performTransparentInstallation(kanataManager: KanataManager())
    }
    
    private func getCurrentDirectory() -> String {
        return FileManager.default.currentDirectoryPath
    }
}

#Preview {
    InstallationWizardView()
        .environmentObject(KanataManager())
}