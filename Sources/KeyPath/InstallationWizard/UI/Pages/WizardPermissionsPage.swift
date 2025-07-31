import SwiftUI

struct WizardPermissionsPage: View {
    enum PermissionType {
        case inputMonitoring
        case accessibility
        
        var title: String {
            switch self {
            case .inputMonitoring: return "Input Monitoring"
            case .accessibility: return "Accessibility"
            }
        }
        
        var description: String {
            switch self {
            case .inputMonitoring: return "Allow KeyPath to monitor keyboard input"
            case .accessibility: return "Allow KeyPath to control your computer"
            }
        }
        
        var icon: String {
            switch self {
            case .inputMonitoring: return "keyboard"
            case .accessibility: return "hand.raised.fill"
            }
        }
    }
    
    let permissionType: PermissionType
    let issues: [WizardIssue]
    let kanataManager: KanataManager
    
    @State private var showingDetails = false
    @State private var showingHelp = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: permissionType.icon)
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
                
                Text(permissionType.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(permissionType.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            
            // Permission Status Cards
            VStack(spacing: 16) {
                permissionCards()
            }
            .padding(.horizontal, 40)
            
            // Issues (if any)
            if !issues.isEmpty {
                VStack(spacing: 12) {
                    ForEach(issues) { issue in
                        IssueCardView(
                            issue: issue,
                            onAutoFix: nil, // Permissions require manual action
                            isFixing: false,
                            kanataManager: kanataManager
                        )
                    }
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Section
            VStack(spacing: 12) {
                if allPermissionsGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Permissions granted")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                } else {
                    Button("Open \(permissionType.title) Settings") {
                        openSettings()
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
            switch permissionType {
            case .inputMonitoring:
                InputMonitoringHelpSheet(kanataManager: kanataManager)
            case .accessibility:
                AccessibilityHelpSheet(kanataManager: kanataManager)
            }
        }
    }
    
    @ViewBuilder
    private func permissionCards() -> some View {
        switch permissionType {
        case .inputMonitoring:
            PermissionCard(
                appName: "KeyPath.app",
                appPath: Bundle.main.bundlePath,
                status: keyPathInputMonitoringStatus,
                permissionType: "Input Monitoring"
            )
            
            PermissionCard(
                appName: "kanata",
                appPath: "/usr/local/bin/kanata",
                status: kanataInputMonitoringStatus,
                permissionType: "Input Monitoring"
            )
            
        case .accessibility:
            PermissionCard(
                appName: "KeyPath.app",
                appPath: Bundle.main.bundlePath,
                status: keyPathAccessibilityStatus,
                permissionType: "Accessibility"
            )
            
            PermissionCard(
                appName: "kanata",
                appPath: "/usr/local/bin/kanata",
                status: kanataAccessibilityStatus,
                permissionType: "Accessibility"
            )
        }
    }
    
    // MARK: - Permission Status Computation
    
    private var keyPathInputMonitoringStatus: InstallationStatus {
        kanataManager.hasInputMonitoringPermission() ? .completed : .notStarted
    }
    
    private var kanataInputMonitoringStatus: InstallationStatus {
        let (_, kanataHasPermission, _) = kanataManager.checkBothAppsHavePermissions()
        return kanataHasPermission ? .completed : .notStarted
    }
    
    private var keyPathAccessibilityStatus: InstallationStatus {
        kanataManager.hasAccessibilityPermission() ? .completed : .notStarted
    }
    
    private var kanataAccessibilityStatus: InstallationStatus {
        let kanataAccessibility = kanataManager.checkAccessibilityForPath("/usr/local/bin/kanata")
        return kanataAccessibility ? .completed : .notStarted
    }
    
    private var allPermissionsGranted: Bool {
        // Use the issues array to determine status - this ensures consistency with SystemStateDetector
        let relevantIssues = issues.filter { issue in
            switch permissionType {
            case .inputMonitoring:
                return issue.category == .permissions && issue.title == "Kanata Input Monitoring" 
            case .accessibility:
                return issue.category == .permissions && issue.title == "Kanata Accessibility"
            }
        }
        return relevantIssues.isEmpty
    }
    
    private func openSettings() {
        switch permissionType {
        case .inputMonitoring:
            // Press Escape to close wizard for Input Monitoring
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
            
        case .accessibility:
            // For Accessibility, open settings immediately without closing wizard
            kanataManager.openAccessibilitySettings()
        }
    }
}