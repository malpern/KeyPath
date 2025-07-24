import SwiftUI
import IOKit.hid
import ApplicationServices

enum WizardPage: String, CaseIterable {
    case summary = "Summary"
    case conflicts = "Resolve Conflicts"
    case inputMonitoring = "Input Monitoring Permission"
    case accessibility = "Accessibility Permission"
    case installation = "Install Components"
}

struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    @StateObject private var installer = KeyPathInstaller()
    @State private var currentPage: WizardPage = .summary
    @State private var isInitializing = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            wizardHeader()
            
            // Page Content
            TabView(selection: $currentPage) {
                SummaryPageView(installer: installer, kanataManager: kanataManager)
                    .tag(WizardPage.summary)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                
                ConflictsPageView(installer: installer, kanataManager: kanataManager)
                    .tag(WizardPage.conflicts)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                
                InputMonitoringPageView(installer: installer, kanataManager: kanataManager)
                    .tag(WizardPage.inputMonitoring)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                
                AccessibilityPageView(installer: installer, kanataManager: kanataManager)
                    .tag(WizardPage.accessibility)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                
                InstallationPageView(installer: installer, kanataManager: kanataManager)
                    .tag(WizardPage.installation)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
            .tabViewStyle(DefaultTabViewStyle())
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            
            
            // Navigation Controls
            wizardNavigation()
        }
        .frame(width: 700, height: 800)
        .background(VisualEffectBackground())
        .onAppear {
            AppLogger.shared.log("🔍 [Wizard] ========== WIZARD LAUNCHED ==========")
            Task {
                // Small delay to ensure UI is ready
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                installer.checkInitialState(kanataManager: kanataManager)
                updateCurrentPage()
                withAnimation {
                    isInitializing = false
                }
            }
        }
        .overlay {
            if isInitializing {
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                        .opacity(0.9)
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Checking system status...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: installer.hasConflicts) { _ in updateCurrentPage() }
        .onChange(of: installer.binaryInstallStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.serviceInstallStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.driverInstallStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.keyPathInputMonitoringStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.keyPathAccessibilityStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.kanataCmdInputMonitoringPermissionStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.kanataCmdAccessibilityStatus) { _ in updateCurrentPage() }
        .onChange(of: installer.installationComplete) { _ in updateCurrentPage() }
    }
    
    @ViewBuilder
    private func wizardHeader() -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                Text("KeyPath Setup")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("✕") { 
                    AppLogger.shared.log("User clicked close button on wizard.")
                    dismiss() 
                }
                    .buttonStyle(.plain)
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func wizardNavigation() -> some View {
        HStack {
            Button(action: {
                AppLogger.shared.log("User clicked 'Previous' button from page \(currentPage.rawValue)")
                navigateToPage(direction: -1)
            }) {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(!canNavigateBackward())
            .keyboardShortcut(.leftArrow, modifiers: [])
            
            Spacer()
            
            Text(currentPage.rawValue)
                .font(.headline)
            
            Spacer()
            
            Button(action: {
                AppLogger.shared.log("User clicked 'Next' button from page \(currentPage.rawValue)")
                navigateToPage(direction: 1)
            }) {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .disabled(!canNavigateForward())
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func updateCurrentPage() {
        DispatchQueue.main.async {
            let oldPage = currentPage
            
            // Only show pages when there's work to do!
            if installer.hasConflicts {
                // Show conflicts page ONLY if there are conflicts
                currentPage = .conflicts
            } else if installer.keyPathInputMonitoringStatus != .completed || 
                      installer.kanataCmdInputMonitoringPermissionStatus != .completed {
                // Show Input Monitoring page FIRST if those permissions are missing
                currentPage = .inputMonitoring
            } else if installer.keyPathAccessibilityStatus != .completed ||
                      installer.kanataCmdAccessibilityStatus != .completed {
                // Show Accessibility page SECOND if those permissions are missing
                currentPage = .accessibility
            } else if installer.binaryInstallStatus != .completed ||
                      installer.serviceInstallStatus != .completed ||
                      installer.driverInstallStatus != .completed {
                // Show installation page AFTER permissions are granted
                currentPage = .installation  
            } else {
                // Everything is complete - show summary
                currentPage = .summary
            }
            
            if oldPage != currentPage {
                AppLogger.shared.log("Wizard page automatically updated from \(oldPage.rawValue) to \(currentPage.rawValue)")
            }
        }
    }
    
    private func navigateToPage(direction: Int) {
        let pages = WizardPage.allCases
        guard let currentIndex = pages.firstIndex(of: currentPage) else { return }
        
        let newIndex = currentIndex + direction
        if newIndex >= 0 && newIndex < pages.count {
            let oldPage = currentPage
            currentPage = pages[newIndex]
            AppLogger.shared.log("Navigated from page \(oldPage.rawValue) to \(currentPage.rawValue)")
        }
    }
    
    private func canNavigateBackward() -> Bool {
        return WizardPage.allCases.firstIndex(of: currentPage) ?? 0 > 0
    }
    
    private func canNavigateForward() -> Bool {
        // Don't allow manual navigation if we're on a required page
        switch currentPage {
        case .conflicts:
            return !installer.hasConflicts // Can only proceed if conflicts resolved
        case .inputMonitoring:
            return installer.keyPathInputMonitoringStatus == .completed && 
                   installer.kanataCmdInputMonitoringPermissionStatus == .completed
        case .accessibility:
            return installer.keyPathAccessibilityStatus == .completed && 
                   installer.kanataCmdAccessibilityStatus == .completed
        case .installation:
            return installer.binaryInstallStatus == .completed &&
                   installer.serviceInstallStatus == .completed &&
                   installer.driverInstallStatus == .completed
        default:
            let currentIndex = WizardPage.allCases.firstIndex(of: currentPage) ?? 0
            return currentIndex < WizardPage.allCases.count - 1
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
    
    // Conflict detection
    @Published var hasConflicts = false
    @Published var conflictDescription = ""
    
    // Granular permission statuses
    @Published var keyPathInputMonitoringStatus: InstallationStatus = .notStarted
    @Published var keyPathAccessibilityStatus: InstallationStatus = .notStarted
    @Published var kanataCmdInputMonitoringPermissionStatus: InstallationStatus = .notStarted
    @Published var kanataCmdAccessibilityStatus: InstallationStatus = .notStarted
    
    // Derived overall permission status
    var permissionStatus: InstallationStatus {
        if keyPathInputMonitoringStatus == .completed &&
           keyPathAccessibilityStatus == .completed &&
           kanataCmdInputMonitoringPermissionStatus == .completed &&
           kanataCmdAccessibilityStatus == .completed {
            return .completed
        } else if keyPathInputMonitoringStatus == .failed ||
                  keyPathAccessibilityStatus == .failed ||
                  kanataCmdInputMonitoringPermissionStatus == .failed ||
                  kanataCmdAccessibilityStatus == .failed {
            return .failed
        } else if keyPathInputMonitoringStatus == .inProgress ||
                  keyPathAccessibilityStatus == .inProgress ||
                  kanataCmdInputMonitoringPermissionStatus == .inProgress ||
                  kanataCmdAccessibilityStatus == .inProgress {
            return .inProgress
        }
        return .notStarted
    }
    
    var needsPermissionGrant: Bool {
        return permissionStatus != .completed
    }
    
    var allComponentsInstalledButServiceNotRunning: Bool {
        return binaryInstallStatus == .completed &&
               serviceInstallStatus == .completed &&
               driverInstallStatus == .completed &&
               permissionStatus == .completed &&
               !installationComplete // This means service is not running
    }
    
    func checkInitialState(kanataManager: KanataManager) {
        let manager = kanataManager
        
        AppLogger.shared.log("🔍 [Wizard] ========== STARTING checkInitialState ==========")
        AppLogger.shared.log("🔍 [Wizard] Checking initial state...")
        AppLogger.shared.log("🔍 [Wizard] Manager state: isRunning=\(manager.isRunning), lastError=\(manager.lastError ?? "none")")
        
        // ALWAYS check for conflicting processes first
        AppLogger.shared.log("🔍 [Wizard] Step 0: Checking for conflicting Kanata processes...")
        // Check for real conflicts using pgrep
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "kanata-cmd"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        var hasConflictingProcesses = false
        var conflictDesc = ""
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            AppLogger.shared.log("🔍 [Wizard] pgrep exit status: \(task.terminationStatus), output: '\(output)'")
            
            if task.terminationStatus == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasConflictingProcesses = true
                // Parse the output - pgrep -fl returns "PID command"
                let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
                conflictDesc = "Found \(lines.count) Kanata process\(lines.count == 1 ? "" : "es"):\n"
                for line in lines {
                    // Extract PID and command from "PID command" format
                    let components = line.components(separatedBy: " ")
                    if let pid = components.first {
                        let command = components.dropFirst().joined(separator: " ")
                        conflictDesc += "• Process ID: \(pid) - \(command)\n"
                    }
                }
            } else {
                // Make sure we clear the conflict state
                hasConflictingProcesses = false
                conflictDesc = ""
            }
        } catch {
            AppLogger.shared.log("🔍 [Wizard] Error checking for conflicts: \(error)")
        }
        hasConflicts = hasConflictingProcesses
        conflictDescription = conflictDesc
        
        AppLogger.shared.log("🔍 [Wizard] Conflict check result: hasConflicts=\(hasConflicts), description='\(conflictDescription)'")
        
        if hasConflicts {
            AppLogger.shared.log("🔍 [Wizard] ❌ CONFLICTS DETECTED: \(conflictDescription)")
            statusMessage = "⚠️ Conflicting Kanata processes must be terminated before proceeding."
            isError = true
            
            // Reset all other statuses - don't check anything else while conflicts exist
            binaryInstallStatus = .notStarted
            serviceInstallStatus = .notStarted
            driverInstallStatus = .notStarted
            keyPathInputMonitoringStatus = .notStarted
            keyPathAccessibilityStatus = .notStarted
            kanataCmdInputMonitoringPermissionStatus = .notStarted
            kanataCmdAccessibilityStatus = .notStarted
            installationComplete = false
            
            AppLogger.shared.log("🔍 [Wizard] 🛑 STOPPING ALL OTHER CHECKS DUE TO CONFLICTS")
            return  // ABSOLUTELY NO OTHER CHECKS WHILE CONFLICTS EXIST
        }
        
        AppLogger.shared.log("🔍 [Wizard] ✅ No conflicts detected, proceeding with installation checks...")
        statusMessage = "Checking installation status..."
        isError = false
        
        // Step 1: Check binary installation
        AppLogger.shared.log("🔍 [Wizard] Step 1: Checking binary installation...")
        let binaryInstalled = manager.isInstalled()
        AppLogger.shared.log("🔍 [Wizard] Binary installed: \(binaryInstalled)")
        if binaryInstalled {
            binaryInstallStatus = .completed
            AppLogger.shared.log("🔍 [Wizard] ✅ Binary installation: COMPLETED")
        } else {
            binaryInstallStatus = .notStarted
            AppLogger.shared.log("🔍 [Wizard] ❌ Binary installation: NOT STARTED")
        }
        
        // Step 2: Check service installation (Privileged Helper)
        AppLogger.shared.log("🔍 [Wizard] Step 2: Checking service installation (Privileged Helper)...")
        let helperInstalled = manager.isHelperInstalled()
        AppLogger.shared.log("🔍 [Wizard] Helper installed: \(helperInstalled)")
        if helperInstalled {
            serviceInstallStatus = .completed
            AppLogger.shared.log("🔍 [Wizard] ✅ Service installation: COMPLETED")
        } else {
            serviceInstallStatus = .notStarted
            AppLogger.shared.log("🔍 [Wizard] ❌ Service installation: NOT STARTED")
        }
        
        // Step 3: Check Karabiner driver installation
        AppLogger.shared.log("🔍 [Wizard] Step 3: Checking Karabiner driver installation...")
        let driverInstalled = manager.isKarabinerDriverInstalled()
        AppLogger.shared.log("🔍 [Wizard] Driver installed: \(driverInstalled)")
        if driverInstalled {
            driverInstallStatus = .completed
            AppLogger.shared.log("🔍 [Wizard] ✅ Driver installation: COMPLETED")
        } else {
            driverInstallStatus = .notStarted
            AppLogger.shared.log("🔍 [Wizard] ❌ Driver installation: NOT STARTED")
        }
        
        // Step 4: Check granular permissions
        AppLogger.shared.log("🔍 [Wizard] Step 4: Checking granular permissions...")
        
        // KeyPath.app Input Monitoring
        let kpInputMonitoring = manager.hasInputMonitoringPermission()
        AppLogger.shared.log("🔍 [Wizard] KeyPath Input Monitoring: \(kpInputMonitoring)")
        keyPathInputMonitoringStatus = kpInputMonitoring ? .completed : .notStarted
        
        // KeyPath.app Accessibility
        let kpAccessibility = manager.hasAccessibilityPermission()
        AppLogger.shared.log("🔍 [Wizard] KeyPath Accessibility: \(kpAccessibility)")
        keyPathAccessibilityStatus = kpAccessibility ? .completed : .notStarted
        
        // TCC database check for both apps
        let (keyPathHasPermission, kanataHasPermission, permissionDetails) = manager.checkBothAppsHavePermissions()
        AppLogger.shared.log("🔍 [Wizard] TCC Permission check: KeyPath=\(keyPathHasPermission), kanata-cmd=\(kanataHasPermission)")
        AppLogger.shared.log("🔍 [Wizard] TCC Details:\n\(permissionDetails)")
        
        // kanata-cmd Input Monitoring (via TCC database check)
        kanataCmdInputMonitoringPermissionStatus = kanataHasPermission ? .completed : .notStarted
        
        // Check kanata-cmd Accessibility permissions using TCC database
        // For now, we'll check if kanata-cmd has accessibility using file access test
        let kanataCmdPath = "/usr/local/bin/kanata-cmd"
        let kanataCmdAccessibility = manager.checkAccessibilityForPath(kanataCmdPath)
        AppLogger.shared.log("🔍 [Wizard] kanata-cmd Accessibility: \(kanataCmdAccessibility)")
        kanataCmdAccessibilityStatus = kanataCmdAccessibility ? .completed : .notStarted
        
        // Determine overall permission status (derived property)
        AppLogger.shared.log("🔍 [Wizard] Individual permission statuses:")
        AppLogger.shared.log("🔍 [Wizard] - keyPathInputMonitoringStatus: \(keyPathInputMonitoringStatus)")
        AppLogger.shared.log("🔍 [Wizard] - keyPathAccessibilityStatus: \(keyPathAccessibilityStatus)")
        AppLogger.shared.log("🔍 [Wizard] - kanataCmdInputMonitoringPermissionStatus: \(kanataCmdInputMonitoringPermissionStatus)")
        AppLogger.shared.log("🔍 [Wizard] - kanataCmdAccessibilityStatus: \(kanataCmdAccessibilityStatus)")
        AppLogger.shared.log("🔍 [Wizard] Overall permission status: \(permissionStatus)")
        
        // Final status determination
        AppLogger.shared.log("🔍 [Wizard] ========== FINAL STATUS CHECK ==========")
        AppLogger.shared.log("🔍 [Wizard] Binary: \(binaryInstallStatus)")
        AppLogger.shared.log("🔍 [Wizard] Service: \(serviceInstallStatus)")
        AppLogger.shared.log("🔍 [Wizard] Driver: \(driverInstallStatus)")
        AppLogger.shared.log("🔍 [Wizard] Permissions: \(permissionStatus)")
        AppLogger.shared.log("🔍 [Wizard] Service running: \(manager.isRunning)")
        
        let allComponentsComplete = binaryInstallStatus == .completed &&
                                   serviceInstallStatus == .completed &&
                                   driverInstallStatus == .completed &&
                                   permissionStatus == .completed
        
        AppLogger.shared.log("🔍 [Wizard] All components complete: \(allComponentsComplete)")
        
        if allComponentsComplete && manager.isRunning {
            installationComplete = true
            statusMessage = "KeyPath is ready to use!"
            AppLogger.shared.log("🔍 [Wizard] 🎉 INSTALLATION COMPLETE - all components installed and service running")
        } else if allComponentsComplete && !manager.isRunning {
            installationComplete = false
            statusMessage = "⚠️ All components installed but Kanata service is not running. Click 'Start Using KeyPath' to start the service."
            AppLogger.shared.log("🔍 [Wizard] ⚠️ Components complete but service not running - need to start service")
        } else {
            installationComplete = false
            statusMessage = "Please complete the installation steps."
            AppLogger.shared.log("🔍 [Wizard] ❌ Some components not complete - continuing wizard")
        }
        
        AppLogger.shared.log("🔍 [Wizard] Final UI state: installationComplete=\(installationComplete), statusMessage='\(statusMessage)'")
        AppLogger.shared.log("🔍 [Wizard] ========== checkInitialState COMPLETE ==========")
    }
    
    func performTransparentInstallation(kanataManager: KanataManager) async {
        AppLogger.shared.log("🚀 [Install] Starting transparent installation.")
        AppLogger.shared.log("🚀 [Install] Setting UI to installing state...")
        isInstalling = true
        isError = false
        
        // Show all steps as in progress
        binaryInstallStatus = .inProgress
        serviceInstallStatus = .inProgress
        driverInstallStatus = .inProgress
        statusMessage = "Installing KeyPath components..."
        AppLogger.shared.log("🚀 [Install] UI updated, calling kanataManager.performTransparentInstallation()...")
        
        // Perform the transparent installation
        let success = await kanataManager.performTransparentInstallation()
        AppLogger.shared.log("🚀 [Install] kanataManager.performTransparentInstallation() returned: \(success)")
        
        if success {
            AppLogger.shared.log("✅ [Install] Transparent installation script succeeded.")
            // Mark all as completed
            binaryInstallStatus = .completed
            serviceInstallStatus = .completed
            driverInstallStatus = .completed
            
            // Re-check permissions after installation
            checkInitialState(kanataManager: kanataManager)
            
            if permissionStatus == .completed {
                installationComplete = true
                statusMessage = "🎉 Installation complete! KeyPath is ready to use!"
                AppLogger.shared.log("✅ [Install] Permissions already granted. Installation complete.")
            } else {
                installationComplete = false
                statusMessage = "✅ Installation complete! Please grant permissions to finish setup."
                AppLogger.shared.log("⚠️ [Install] Installation complete, but permissions are needed.")
            }
        } else {
            AppLogger.shared.log("❌ [Install] Transparent installation script failed or was cancelled.")
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
        AppLogger.shared.log("🔘 [UI Action] User requested permission status update.")
        // Re-run the full initial state check to update all statuses
        checkInitialState(kanataManager: kanataManager)
    }
}

// MARK: - Page View Implementations

struct SummaryPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Welcome to KeyPath")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Set up your keyboard customization tool")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 32)
            
            VStack(alignment: .leading, spacing: 16) {
                SummaryItemView(
                    icon: "keyboard",
                    title: "Binary Installation",
                    status: installer.binaryInstallStatus
                )
                
                SummaryItemView(
                    icon: "gear",
                    title: "Helper Service",
                    status: installer.serviceInstallStatus
                )
                
                SummaryItemView(
                    icon: "cpu",
                    title: "Karabiner Driver",
                    status: installer.driverInstallStatus
                )
                
                SummaryItemView(
                    icon: "lock.shield",
                    title: "System Permissions",
                    status: installer.permissionStatus
                )
            }
            .padding(.horizontal, 60)
            
            Spacer()
            
            if installer.installationComplete {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Setup Complete")
                            .fontWeight(.medium)
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    
                    Button("Start Using KeyPath") {
                        if let window = NSApplication.shared.windows.first {
                            window.close()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if installer.hasConflicts {
                Text("⚠️ Conflicts detected. Please resolve them to continue.")
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text("Complete the setup process to start using KeyPath")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct SummaryItemView: View {
    let icon: String
    let title: String
    let status: InstallationStatus
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            statusIcon
        }
    }
    
    var iconColor: Color {
        switch status {
        case .completed: return .green
        case .inProgress: return .blue
        case .failed: return .red
        case .notStarted: return .gray
        }
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.title3)
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(.gray.opacity(0.5))
                .font(.title3)
        }
    }
}

struct ConflictsPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    @State private var isTerminating = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                        .symbolRenderingMode(.multicolor)
                }
                
                Text("Conflicting Processes")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Other Kanata processes must be stopped before continuing")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(.top, 32)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("The following conflicting processes were found:")
                    .font(.headline)
                
                ScrollView {
                    Text(installer.conflictDescription)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
                
                Text("These processes may be:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Other Kanata instances running with root privileges", systemImage: "terminal")
                    Label("Previous KeyPath processes that didn't shut down properly", systemImage: "xmark.app")
                    Label("Manual Kanata installations running in the background", systemImage: "gearshape.2")
                }
                .font(.caption)
                .padding(.leading)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: terminateConflicts) {
                    if isTerminating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Text("Terminate Conflicting Processes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isTerminating)
                
                Button("Check Again") {
                    installer.checkInitialState(kanataManager: kanataManager)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isTerminating)
            }
        }
        .padding()
    }
    
    private func terminateConflicts() {
        Task {
            isTerminating = true
            AppLogger.shared.log("🔧 [Conflicts] Terminating conflicting processes...")
            
            // Extract PIDs from the conflict description
            let lines = installer.conflictDescription.components(separatedBy: "\n")
            for line in lines {
                if line.contains("Process ID:") {
                    let components = line.components(separatedBy: "Process ID:").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let pid = components {
                        AppLogger.shared.log("🔧 [Conflicts] Attempting to terminate PID: \(pid)")
                        
                        // Try to kill the process
                        let killTask = Process()
                        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                        killTask.arguments = ["-9", pid]
                        
                        do {
                            try killTask.run()
                            killTask.waitUntilExit()
                            if killTask.terminationStatus == 0 {
                                AppLogger.shared.log("✅ [Conflicts] Successfully terminated PID: \(pid)")
                            } else {
                                AppLogger.shared.log("❌ [Conflicts] Failed to terminate PID: \(pid) - may require sudo")
                                // Try with sudo
                                let sudoKillTask = Process()
                                sudoKillTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                                sudoKillTask.arguments = ["-e", "do shell script \"kill -9 \(pid)\" with administrator privileges"]
                                
                                try sudoKillTask.run()
                                sudoKillTask.waitUntilExit()
                                if sudoKillTask.terminationStatus == 0 {
                                    AppLogger.shared.log("✅ [Conflicts] Successfully terminated PID with sudo: \(pid)")
                                }
                            }
                        } catch {
                            AppLogger.shared.log("❌ [Conflicts] Error terminating PID \(pid): \(error)")
                        }
                    }
                }
            }
            
            // Wait a moment for processes to fully terminate
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Re-check for conflicts
            installer.checkInitialState(kanataManager: kanataManager)
            isTerminating = false
        }
    }
}

struct InputMonitoringPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "keyboard")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
                
                Text("Input Monitoring")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Allow KeyPath to monitor keyboard input")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            
            // Permission Status Cards
            VStack(spacing: 16) {
                PermissionCard(
                    appName: "KeyPath.app",
                    appPath: Bundle.main.bundlePath,
                    status: installer.keyPathInputMonitoringStatus,
                    permissionType: "Input Monitoring"
                )
                
                PermissionCard(
                    appName: "kanata-cmd",
                    appPath: "/usr/local/bin/kanata-cmd",
                    status: installer.kanataCmdInputMonitoringPermissionStatus,
                    permissionType: "Input Monitoring"
                )
            }
            .padding(.horizontal, 40)
            
            // Instructions
            if installer.keyPathInputMonitoringStatus != .completed || 
               installer.kanataCmdInputMonitoringPermissionStatus != .completed {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to grant permission:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("1.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Click 'Open System Settings' below")
                        }
                        HStack(alignment: .top) {
                            Text("2.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Navigate to Privacy & Security → Input Monitoring")
                        }
                        HStack(alignment: .top) {
                            Text("3.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Enable the toggle for both KeyPath and kanata-cmd")
                        }
                        HStack(alignment: .top) {
                            Text("4.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Click 'Check Permission Status' to verify")
                        }
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                if installer.keyPathInputMonitoringStatus != .completed || 
                   installer.kanataCmdInputMonitoringPermissionStatus != .completed {
                    Button("Open System Settings") {
                        kanataManager.openInputMonitoringSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Check Permission Status") {
                        Task {
                            await installer.updatePermissionStatus(kanataManager: kanataManager)
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Permissions granted")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
                
                Button("Show Details") {
                    showingDetails.toggle()
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .sheet(isPresented: $showingDetails) {
            PermissionDetailsSheet(kanataManager: kanataManager)
        }
    }
}

struct AccessibilityPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
                
                Text("Accessibility")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Allow KeyPath to control your computer")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            
            // Permission Status Cards
            VStack(spacing: 16) {
                PermissionCard(
                    appName: "KeyPath.app",
                    appPath: Bundle.main.bundlePath,
                    status: installer.keyPathAccessibilityStatus,
                    permissionType: "Accessibility"
                )
                
                PermissionCard(
                    appName: "kanata-cmd",
                    appPath: "/usr/local/bin/kanata-cmd",
                    status: installer.kanataCmdAccessibilityStatus,
                    permissionType: "Accessibility"
                )
            }
            .padding(.horizontal, 40)
            
            // Instructions
            if installer.keyPathAccessibilityStatus != .completed || 
               installer.kanataCmdAccessibilityStatus != .completed {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to grant permission:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("1.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Click 'Open System Settings' below")
                        }
                        HStack(alignment: .top) {
                            Text("2.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Navigate to Privacy & Security → Accessibility")
                        }
                        HStack(alignment: .top) {
                            Text("3.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Enable the toggle for both KeyPath and kanata-cmd")
                        }
                        HStack(alignment: .top) {
                            Text("4.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("You may need to unlock with your password")
                        }
                        HStack(alignment: .top) {
                            Text("5.")
                                .fontWeight(.medium)
                                .frame(width: 20)
                            Text("Click 'Check Permission Status' to verify")
                        }
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                if installer.keyPathAccessibilityStatus != .completed || 
                   installer.kanataCmdAccessibilityStatus != .completed {
                    Button("Open System Settings") {
                        kanataManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Check Permission Status") {
                        Task {
                            await installer.updatePermissionStatus(kanataManager: kanataManager)
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Permissions granted")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

struct InstallationPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
                
                Text("Install Components")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Set up required system components")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            
            // Installation Status
            VStack(spacing: 16) {
                InstallationItemView(
                    title: "Kanata Binary",
                    description: "Core keyboard remapping engine",
                    status: installer.binaryInstallStatus
                )
                
                InstallationItemView(
                    title: "Privileged Helper",
                    description: "Manages Kanata process with required permissions",
                    status: installer.serviceInstallStatus
                )
                
                InstallationItemView(
                    title: "Karabiner Driver",
                    description: "Virtual keyboard driver for input capture",
                    status: installer.driverInstallStatus
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Action Buttons
            if installer.isInstalling {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Installing components...")
                        .foregroundColor(.secondary)
                }
            } else if installer.binaryInstallStatus == .completed &&
                      installer.serviceInstallStatus == .completed &&
                      installer.driverInstallStatus == .completed {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Components installed")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                    
                    if installer.allComponentsInstalledButServiceNotRunning {
                        Button("Start KeyPath Service") {
                            Task {
                                await kanataManager.startKanata()
                                installer.checkInitialState(kanataManager: kanataManager)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Button("Install Components") {
                        Task {
                            await installer.performTransparentInstallation(kanataManager: kanataManager)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("Administrator password required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if installer.isError {
                Text(installer.statusMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct InstallationItemView: View {
    let title: String
    let description: String
    let status: InstallationStatus
    
    var body: some View {
        HStack(spacing: 16) {
            statusIcon
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
        case .inProgress:
            ProgressView()
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.title2)
        case .notStarted:
            Image(systemName: "circle.dashed")
                .foregroundColor(.gray.opacity(0.5))
                .font(.title2)
        }
    }
}

struct PermissionCard: View {
    let appName: String
    let appPath: String
    let status: InstallationStatus
    let permissionType: String
    
    var body: some View {
        HStack(spacing: 16) {
            statusIcon
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(appName)
                    .font(.headline)
                Text(appPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    var statusIcon: some View {
        Group {
            switch status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            case .inProgress:
                ProgressView()
                    .scaleEffect(0.7)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            case .notStarted:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
    }
    
    var statusText: String {
        switch status {
        case .completed: return "Granted"
        case .inProgress: return "Checking..."
        case .failed: return "Error"
        case .notStarted: return "Not Granted"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .completed: return .green
        case .inProgress: return .blue
        case .failed: return .red
        case .notStarted: return .orange
        }
    }
    
    var backgroundColor: Color {
        switch status {
        case .completed: return Color.green.opacity(0.1)
        case .failed: return Color.red.opacity(0.1)
        default: return Color(NSColor.controlBackgroundColor)
        }
    }
    
    var borderColor: Color {
        switch status {
        case .completed: return Color.green.opacity(0.3)
        case .failed: return Color.red.opacity(0.3)
        case .notStarted: return Color.orange.opacity(0.3)
        default: return Color.clear
        }
    }
}

struct PermissionDetailsSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDetails = ""
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Permission Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            if isLoading {
                ProgressView("Checking permissions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TCC Database Check Results:")
                            .font(.headline)
                        
                        Text(permissionDetails)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What to do if permissions are missing:")
                                .font(.headline)
                            
                            Text("1. Open System Settings → Privacy & Security")
                            Text("2. Navigate to Input Monitoring")
                            Text("3. Add both KeyPath.app and /usr/local/bin/kanata-cmd")
                            Text("4. Navigate to Accessibility")
                            Text("5. Add both KeyPath.app and /usr/local/bin/kanata-cmd")
                            Text("6. You may need to restart KeyPath after granting permissions")
                        }
                        .font(.subheadline)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
        .padding()
        .onAppear {
            loadPermissionDetails()
        }
    }
    
    private func loadPermissionDetails() {
        Task {
            let (keyPathHas, kanataHas, details) = kanataManager.checkBothAppsHavePermissions()
            
            await MainActor.run {
                var report = "=== Permission Status Report ===\n\n"
                report += "KeyPath.app:\n"
                report += "• Input Monitoring: \(kanataManager.hasInputMonitoringPermission() ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• Accessibility: \(kanataManager.hasAccessibilityPermission() ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• TCC Database: \(keyPathHas ? "✅ Found" : "❌ Not Found")\n\n"
                
                report += "kanata-cmd (/usr/local/bin/kanata-cmd):\n"
                report += "• Input Monitoring (TCC): \(kanataHas ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• Accessibility: \(kanataManager.checkAccessibilityForPath("/usr/local/bin/kanata-cmd") ? "✅ Granted" : "❌ Not Granted")\n\n"
                
                report += "=== TCC Database Details ===\n"
                report += details
                
                permissionDetails = report
                isLoading = false
            }
        }
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .contentBackground
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
    InstallationWizardView()
        .environmentObject(KanataManager())
}
