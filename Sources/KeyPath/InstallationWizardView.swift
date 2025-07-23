import SwiftUI

struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    @StateObject private var installer = KeyPathInstaller()
    
    var body: some View {
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
                
                Text("KeyPath automatically handles root privileges for low-level keyboard access")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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
                    description: "Configures automatic startup with root privileges",
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
                
                InstallationStepView(
                    step: 4,
                    title: "Grant Input Monitoring Permission",
                    description: "Required for keyboard event monitoring",
                    status: installer.permissionStatus,
                    isActive: installer.currentStep >= 4
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
                } else if installer.needsPermissionGrant {
                    VStack(spacing: 12) {
                        Text("Grant Input Monitoring Permission")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            Text("Add this file to Input Monitoring in System Settings:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("/usr/local/bin/kanata-cmd")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("/usr/local/bin/kanata-cmd", forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Copy to clipboard")
                            }
                        }
                        
                        HStack(spacing: 16) {
                            Button("Request Permission") {
                                Task {
                                    _ = kanataManager.requestInputMonitoringPermission()
                                    await installer.updatePermissionStatus(kanataManager: kanataManager)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Open System Settings") {
                                kanataManager.openInputMonitoringSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
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
        .frame(width: 600, height: 580)
        .onAppear {
            installer.checkInitialState(kanataManager: kanataManager)
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
    @Published var permissionStatus: InstallationStatus = .notStarted
    
    var needsPermissionGrant: Bool {
        return binaryInstallStatus == .completed && 
               serviceInstallStatus == .completed && 
               driverInstallStatus == .completed &&
               permissionStatus != .completed
    }
    
    func checkInitialState(kanataManager: KanataManager) {
        // Use the shared KanataManager instance that has current service state
        let manager = kanataManager
        
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
        
        // Check if Input Monitoring permission is granted (using current service state)
        if manager.hasInputMonitoringPermission() {
            permissionStatus = .completed
            currentStep = max(currentStep, 4)
        }
        
        if binaryInstallStatus == .completed && 
           serviceInstallStatus == .completed && 
           driverInstallStatus == .completed &&
           permissionStatus == .completed {
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
            currentStep = 4
            
            // Check if permissions are already granted
            if kanataManager.hasInputMonitoringPermission() {
                permissionStatus = .completed
                installationComplete = true
                statusMessage = "🎉 Installation complete! KeyPath is ready to use."
            } else {
                permissionStatus = .notStarted
                statusMessage = "✅ Installation complete! Please grant Input Monitoring permission to finish setup."
            }
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
    
    func updatePermissionStatus(kanataManager: KanataManager) async {
        await kanataManager.updateStatus()
        
        if kanataManager.hasInputMonitoringPermission() {
            permissionStatus = .completed
            installationComplete = true
            statusMessage = "🎉 Permission granted! KeyPath is now ready to use."
        } else {
            permissionStatus = .failed
            statusMessage = "⚠️ Permission not granted. Please open System Settings to enable Input Monitoring."
            isError = true
        }
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