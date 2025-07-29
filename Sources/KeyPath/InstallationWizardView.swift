import SwiftUI
import IOKit.hid
import ApplicationServices

enum WizardPage: String, CaseIterable {
    case summary = "Summary"
    case conflicts = "Resolve Conflicts"
    case daemon = "Karabiner Daemon"
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
        AppLogger.shared.log("🔍 [Wizard] UI Render - hasConflicts: \(installer.hasConflicts), conflictDescription: '\(installer.conflictDescription)'")
        
        return VStack(spacing: 0) {
            // Header with page dots
            wizardHeader()
            
            // Page Content - Custom implementation without TabView indicators
            ZStack {
                Group {
                    if currentPage == .summary {
                        SummaryPageView(installer: installer, kanataManager: kanataManager)
                    } else if currentPage == .conflicts {
                        ConflictsPageView(installer: installer, kanataManager: kanataManager)
                    } else if currentPage == .daemon {
                        DaemonPageView(installer: installer, kanataManager: kanataManager)
                    } else if currentPage == .inputMonitoring {
                        InputMonitoringPageView(installer: installer, kanataManager: kanataManager)
                    } else if currentPage == .accessibility {
                        AccessibilityPageView(installer: installer, kanataManager: kanataManager)
                    } else if currentPage == .installation {
                        InstallationPageView(installer: installer, kanataManager: kanataManager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
            .animation(.easeInOut(duration: 0.3), value: currentPage)
        }
        .frame(width: 700, height: 850)
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
                    .foregroundColor(installer.hasConflicts ? .gray : .secondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(installer.hasConflicts)
            }
            
            // Page dots moved to header
            pageDotsIndicator()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func pageDotsIndicator() -> some View {
        HStack(spacing: 8) {
            ForEach(WizardPage.allCases, id: \.self) { page in
                Circle()
                    .fill(currentPage == page ? Color.accentColor : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .scaleEffect(currentPage == page ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage = page
                        }
                        AppLogger.shared.log("User navigated to page \(page.rawValue) via page dot")
                    }
            }
        }
        .padding(.vertical, 8)
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
            } else if installer.daemonStatus != .completed {
                // Show daemon page if daemon is not running
                currentPage = .daemon
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
    @Published var daemonStatus: InstallationStatus = .notStarted
    
    // Conflict detection - Always start fresh
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
               daemonStatus == .completed &&
               permissionStatus == .completed &&
               !installationComplete // This means service is not running
    }
    
    func checkInitialState(kanataManager: KanataManager) {
        let manager = kanataManager
        
        AppLogger.shared.log("🔍 [Wizard] ========== STARTING checkInitialState ==========")
        AppLogger.shared.log("🔍 [Wizard] Checking initial state...")
        AppLogger.shared.log("🔍 [Wizard] Manager state: isRunning=\(manager.isRunning), lastError=\(manager.lastError ?? "none")")
        
        // FORCE RESET CONFLICT STATE - Always start fresh each session
        AppLogger.shared.log("🔍 [Wizard] 🔄 FORCE RESETTING conflict state")
        hasConflicts = false
        conflictDescription = ""
        AppLogger.shared.log("🔍 [Wizard] 🔄 Reset complete: hasConflicts=\(hasConflicts)")
        
        // ALWAYS check for conflicting processes first
        AppLogger.shared.log("🔍 [Wizard] ========== CONFLICT DETECTION START ==========")
        AppLogger.shared.log("🔍 [Wizard] Step 0: Checking for conflicting Kanata processes...")
        
        // Check for real conflicts using pgrep
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "kanata"]
        
        AppLogger.shared.log("🔍 [Wizard] 🔧 COMMAND: \(task.executableURL!.path) \(task.arguments!.joined(separator: " "))")
        AppLogger.shared.log("🔍 [Wizard] 🔧 Current process PID: \(ProcessInfo.processInfo.processIdentifier)")
        AppLogger.shared.log("🔍 [Wizard] 🔧 Current process name: \(ProcessInfo.processInfo.processName)")
        
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
            
            AppLogger.shared.log("🔍 [Wizard] 📤 PGREP RESULT:")
            AppLogger.shared.log("🔍 [Wizard] 📤   Exit Status: \(task.terminationStatus)")
            AppLogger.shared.log("🔍 [Wizard] 📤   Raw Output: '\(output)'")
            AppLogger.shared.log("🔍 [Wizard] 📤   Output Length: \(output.count) chars")
            
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.shared.log("🔍 [Wizard] 📤   Trimmed Output: '\(trimmedOutput)'")
            AppLogger.shared.log("🔍 [Wizard] 📤   Trimmed Length: \(trimmedOutput.count) chars")
            AppLogger.shared.log("🔍 [Wizard] 📤   Is Empty: \(trimmedOutput.isEmpty)")
            
            if task.terminationStatus == 0 && !trimmedOutput.isEmpty {
                AppLogger.shared.log("🔍 [Wizard] ⚠️ POTENTIAL CONFLICTS - Processing output...")
                
                // Split into lines
                let lines = trimmedOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
                AppLogger.shared.log("🔍 [Wizard] 📋 Found \(lines.count) non-empty lines")
                
                // Analyze each line
                var validProcesses: [String] = []
                for (index, line) in lines.enumerated() {
                    AppLogger.shared.log("🔍 [Wizard] 📋 Line[\(index)]: '\(line)'")
                    
                    let components = line.components(separatedBy: " ")
                    AppLogger.shared.log("🔍 [Wizard] 🔧   Components: \(components)")
                    
                    guard let pidString = components.first,
                          let pid = Int(pidString),
                          components.count > 1 else {
                        AppLogger.shared.log("🔍 [Wizard] ❌   SKIP: Invalid format")
                        continue
                    }
                    
                    let command = components.dropFirst().joined(separator: " ")
                    AppLogger.shared.log("🔍 [Wizard] 🔧   PID: \(pid)")
                    AppLogger.shared.log("🔍 [Wizard] 🔧   Command: '\(command)'")
                    
                    // Apply exclusion filters
                    if command.contains("pgrep") {
                        AppLogger.shared.log("🔍 [Wizard] 🚫   EXCLUDED: Contains 'pgrep'")
                        continue
                    }
                    if command.contains("/bin/zsh") {
                        AppLogger.shared.log("🔍 [Wizard] 🚫   EXCLUDED: Contains '/bin/zsh'")
                        continue
                    }
                    if command.contains("/bin/sh") {
                        AppLogger.shared.log("🔍 [Wizard] 🚫   EXCLUDED: Contains '/bin/sh'")
                        continue
                    }
                    
                    // Check if it's a valid kanata process
                    if command.contains("/usr/local/bin/kanata") || command.starts(with: "kanata") {
                        AppLogger.shared.log("🔍 [Wizard] ✅   VALID KANATA PROCESS: \(line)")
                        validProcesses.append(line)
                    } else {
                        AppLogger.shared.log("🔍 [Wizard] 🚫   EXCLUDED: Not a kanata binary")
                    }
                }
                
                AppLogger.shared.log("🔍 [Wizard] 📊 ANALYSIS RESULT: Found \(validProcesses.count) valid processes")
                
                if !validProcesses.isEmpty {
                    hasConflictingProcesses = true
                    conflictDesc = "Found \(validProcesses.count) Kanata process\(validProcesses.count == 1 ? "" : "es"):\n"
                    for line in validProcesses {
                        let components = line.components(separatedBy: " ")
                        let pid = components.first!
                        let command = components.dropFirst().joined(separator: " ")
                        conflictDesc += "• Process ID: \(pid) - \(command)\n"
                    }
                    AppLogger.shared.log("🔍 [Wizard] ⚠️ SETTING CONFLICTS=TRUE: \(validProcesses)")
                } else {
                    hasConflictingProcesses = false
                    conflictDesc = ""
                    AppLogger.shared.log("🔍 [Wizard] ✅ NO VALID CONFLICTS: All processes filtered out")
                }
            } else {
                hasConflictingProcesses = false
                conflictDesc = ""
                AppLogger.shared.log("🔍 [Wizard] ✅ NO PGREP MATCHES: exit=\(task.terminationStatus), empty=\(trimmedOutput.isEmpty)")
            }
        } catch {
            AppLogger.shared.log("🔍 [Wizard] ❌ PGREP ERROR: \(error)")
            hasConflictingProcesses = false
            conflictDesc = ""
        }
        
        AppLogger.shared.log("🔍 [Wizard] ✅ Karabiner-Elements conflict check removed")
        
        // Set published properties
        AppLogger.shared.log("🔍 [Wizard] 🔧 SETTING PROPERTIES: hasConflicts=\(hasConflictingProcesses)")
        AppLogger.shared.log("🔍 [Wizard] 🔧 SETTING DESCRIPTION: '\(conflictDesc)'")
        hasConflicts = hasConflictingProcesses
        conflictDescription = conflictDesc
        
        // Apply fail-safe
        if hasConflicts && conflictDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogger.shared.log("🔍 [Wizard] 🛡️ FAIL-SAFE TRIGGERED: Empty description")
            hasConflicts = false
            conflictDescription = ""
        }
        
        AppLogger.shared.log("🔍 [Wizard] 📊 FINAL STATE:")
        AppLogger.shared.log("🔍 [Wizard] 📊   hasConflicts: \(hasConflicts)")
        AppLogger.shared.log("🔍 [Wizard] 📊   conflictDescription: '\(conflictDescription)'")
        AppLogger.shared.log("🔍 [Wizard] ========== CONFLICT DETECTION END ==========")
        
        if hasConflicts {
            AppLogger.shared.log("🔍 [Wizard] ❌ CONFLICTS DETECTED - NOT checking permissions")
            statusMessage = "⚠️ Conflicting keyboard remapping processes must be terminated before proceeding."
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
        
        // Step 2: Service is always available (no privileged helper needed)
        AppLogger.shared.log("🔍 [Wizard] Step 2: Checking service availability...")
        serviceInstallStatus = .completed
        AppLogger.shared.log("🔍 [Wizard] ✅ Service always available with direct kanata execution")
        
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
        
        // Step 4: Check Karabiner daemon status
        AppLogger.shared.log("🔍 [Wizard] Step 4: Checking Karabiner daemon status...")
        let daemonRunning = manager.isKarabinerDaemonRunning()
        AppLogger.shared.log("🔍 [Wizard] Daemon running: \(daemonRunning)")
        if daemonRunning {
            daemonStatus = .completed
            AppLogger.shared.log("🔍 [Wizard] ✅ Karabiner daemon: RUNNING")
        } else {
            daemonStatus = .notStarted
            AppLogger.shared.log("🔍 [Wizard] ❌ Karabiner daemon: NOT RUNNING")
        }
        
        // Step 5: Check granular permissions
        AppLogger.shared.log("🔍 [Wizard] Step 5: Checking granular permissions...")
        
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
        AppLogger.shared.log("🔍 [Wizard] TCC Permission check: KeyPath=\(keyPathHasPermission), kanata=\(kanataHasPermission)")
        AppLogger.shared.log("🔍 [Wizard] TCC Details:\n\(permissionDetails)")
        
        // kanata Input Monitoring (via TCC database check)
        kanataCmdInputMonitoringPermissionStatus = kanataHasPermission ? .completed : .notStarted
        
        // Check kanata Accessibility permissions using TCC database
        // For now, we'll check if kanata has accessibility using file access test
        let kanataCmdPath = "/usr/local/bin/kanata"
        let kanataCmdAccessibility = manager.checkAccessibilityForPath(kanataCmdPath)
        AppLogger.shared.log("🔍 [Wizard] kanata Accessibility: \(kanataCmdAccessibility)")
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
                                   daemonStatus == .completed &&
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
                    title: "Kanata Service",
                    status: installer.serviceInstallStatus
                )
                
                SummaryItemView(
                    icon: "cpu",
                    title: "Karabiner Driver",
                    status: installer.driverInstallStatus
                )
                
                SummaryItemView(
                    icon: "gear.circle",
                    title: "Karabiner Daemon",
                    status: installer.daemonStatus
                )
                
                SummaryItemView(
                    icon: "lock.shield",
                    title: "System Permissions",
                    status: installer.permissionStatus
                )
            }
            .padding(.horizontal, 60)
            
            Spacer()
            
            // Show completion state if all components are ready
            let allComponentsReady = installer.binaryInstallStatus == .completed &&
                                   installer.serviceInstallStatus == .completed &&
                                   installer.driverInstallStatus == .completed &&
                                   installer.daemonStatus == .completed &&
                                   installer.permissionStatus == .completed
            
            if allComponentsReady {
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
                
                Text("Conflicting keyboard remapping processes must be stopped before continuing")
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
                    Label("Karabiner-Elements (conflicts with Kanata)", systemImage: "keyboard")
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
                .disabled(isTerminating || installer.conflictDescription.isEmpty)
                
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
    @State private var showingHelp = false
    
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
                    appName: "kanata",
                    appPath: "/usr/local/bin/kanata",
                    status: installer.kanataCmdInputMonitoringPermissionStatus,
                    permissionType: "Input Monitoring"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Status message and help button
            VStack(spacing: 12) {
                if installer.keyPathInputMonitoringStatus == .completed && 
                   installer.kanataCmdInputMonitoringPermissionStatus == .completed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Permissions granted")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                } else {
                    Button("Open Input Monitoring Settings") {
                        // Press Escape to close wizard
                        let escapeEvent = NSEvent.keyEvent(
                            with: .keyDown,
                            location: NSPoint.zero,
                            modifierFlags: [],
                            timestamp: 0,
                            windowNumber: 0,
                            context: nil,
                            characters: "\u{1b}",
                            charactersIgnoringModifiers: "\u{1b}",
                            isARepeat: false,
                            keyCode: 53
                        )
                        
                        if let event = escapeEvent {
                            NSApplication.shared.postEvent(event, atStart: false)
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            kanataManager.openInputMonitoringSettings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                
                HStack(spacing: 16) {
                    Button("Show Details") {
                        showingDetails.toggle()
                    }
                    .buttonStyle(.link)
                    
                    Button("Help") {
                        showingHelp = true
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingDetails) {
            PermissionDetailsSheet(kanataManager: kanataManager)
        }
        .sheet(isPresented: $showingHelp) {
            InputMonitoringHelpSheet(kanataManager: kanataManager)
        }
    }
}

struct AccessibilityPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    @State private var showingDetails = false
    @State private var showingHelp = false
    
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
                    appName: "kanata",
                    appPath: "/usr/local/bin/kanata",
                    status: installer.kanataCmdAccessibilityStatus,
                    permissionType: "Accessibility"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Status message and help button
            VStack(spacing: 12) {
                if installer.keyPathAccessibilityStatus == .completed && 
                   installer.kanataCmdAccessibilityStatus == .completed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Permissions granted")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                } else {
                    Button("Open Accessibility Settings") {
                        // For Accessibility, open settings immediately without closing wizard
                        kanataManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                
                HStack(spacing: 16) {
                    Button("Show Details") {
                        showingDetails.toggle()
                    }
                    .buttonStyle(.link)
                    
                    Button("Help") {
                        showingHelp = true
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingDetails) {
            PermissionDetailsSheet(kanataManager: kanataManager)
        }
        .sheet(isPresented: $showingHelp) {
            AccessibilityHelpSheet(kanataManager: kanataManager)
        }
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
                    title: "Kanata Service",
                    description: "Direct kanata execution with --watch support",
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
            
            HStack(spacing: 8) {
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)
                
                if status == .notStarted {
                    Button("Add") {
                        openSystemPreferences()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Click to open System Settings")
                }
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onTapGesture {
            if status == .notStarted {
                openSystemPreferences()
            }
        }
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
    
    private func openSystemPreferences() {
        if permissionType == "Input Monitoring" {
            // Press Escape to close the wizard for Input Monitoring
            let escapeEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: NSPoint.zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
            
            if let event = escapeEvent {
                NSApplication.shared.postEvent(event, atStart: false)
            }
            
            // Small delay to ensure wizard closes before opening settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else if permissionType == "Accessibility" {
            // For Accessibility, open settings immediately without closing wizard
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Fallback to general Privacy & Security (without closing wizard)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
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
                            Text("3. Add both KeyPath.app and /usr/local/bin/kanata")
                            Text("4. Navigate to Accessibility")
                            Text("5. Add both KeyPath.app and /usr/local/bin/kanata")
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
                
                report += "kanata (/usr/local/bin/kanata):\n"
                report += "• Input Monitoring (TCC): \(kanataHas ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• Accessibility: \(kanataManager.checkAccessibilityForPath("/usr/local/bin/kanata") ? "✅ Granted" : "❌ Not Granted")\n\n"
                
                report += "=== TCC Database Details ===\n"
                report += details
                
                permissionDetails = report
                isLoading = false
            }
        }
    }
}

struct DaemonPageView: View {
    @ObservedObject var installer: KeyPathInstaller
    let kanataManager: KanataManager
    @State private var isStartingDaemon = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "gear.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Karabiner Daemon")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("The Karabiner Virtual HID Device Daemon is required for keyboard remapping to work properly.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: installer.daemonStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(installer.daemonStatus == .completed ? .green : .red)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Karabiner Virtual HID Device Daemon")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Text(installer.daemonStatus == .completed ? "Daemon is running" : "Daemon is not running")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .frame(maxWidth: 400)
            
            if installer.daemonStatus != .completed {
                VStack(spacing: 16) {
                    Text("The daemon needs to be running for Kanata to communicate with the keyboard hardware.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.body)
                    
                    Button(action: startDaemon) {
                        HStack {
                            if isStartingDaemon {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Starting Daemon...")
                            } else {
                                Image(systemName: "play.circle.fill")
                                Text("Start Karabiner Daemon")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isStartingDaemon)
                }
                .frame(maxWidth: 300)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Daemon is running successfully!")
                            .fontWeight(.medium)
                    }
                    
                    Text("You can proceed to the next step.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func startDaemon() {
        Task {
            isStartingDaemon = true
            
            let success = await kanataManager.startKarabinerDaemon()
            
            // Refresh the installer state
            installer.checkInitialState(kanataManager: kanataManager)
            
            isStartingDaemon = false
            
            if success {
                AppLogger.shared.log("✅ [Daemon] Successfully started daemon from wizard")
            } else {
                AppLogger.shared.log("❌ [Daemon] Failed to start daemon from wizard")
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

struct InputMonitoringHelpSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Input Monitoring Permission Help")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                                Text("Enable the toggle for both KeyPath and kanata")
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
                    
                    VStack(spacing: 12) {
                        Button("Check Permission Status") {
                            Task {
                                // Refresh permission status
                                await MainActor.run {
                                    kanataManager.objectWillChange.send()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

struct AccessibilityHelpSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Accessibility Permission Help")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                                Text("Enable the toggle for both KeyPath and kanata")
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
                    
                    VStack(spacing: 12) {
                        Button("Check Permission Status") {
                            Task {
                                // Refresh permission status
                                await MainActor.run {
                                    kanataManager.objectWillChange.send()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 500, height: 450)
        .padding()
    }
}

#Preview {
    InstallationWizardView()
        .environmentObject(KanataManager())
}
