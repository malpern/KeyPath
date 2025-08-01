import SwiftUI

struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
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
            
            // System Status Overview
            VStack(alignment: .leading, spacing: 16) {
                systemStatusItems()
            }
            .padding(.horizontal, 60)
            
            Spacer()
            
            // Action Section
            actionSection()
        }
        .padding()
    }
    
    @ViewBuilder
    private func systemStatusItems() -> some View {
        let statusItems = createStatusItems()
        
        ForEach(statusItems, id: \.title) { item in
            if item.isNavigable {
                Button(action: {
                    onNavigateToPage?(item.targetPage!)
                }) {
                    SummaryItemView(
                        icon: item.icon,
                        title: item.title,
                        status: item.status
                    )
                }
                .buttonStyle(.plain)
            } else {
                SummaryItemView(
                    icon: item.icon,
                    title: item.title,
                    status: item.status
                )
            }
        }
        
        // Show permissions breakdown if there are issues
        if hasAnyPermissionIssues() {
            VStack(spacing: 8) {
                let permissionItems = createPermissionStatusItems()
                ForEach(permissionItems, id: \.title) { item in
                    Button(action: {
                        onNavigateToPage?(item.targetPage!)
                    }) {
                        HStack(spacing: 12) {
                            // Indent permission sub-items
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 16)
                            
                            SummaryItemView(
                                icon: item.icon,
                                title: item.title,
                                status: item.status
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        
        // Show service status separately with visual separation
        if shouldShowServiceStatus {
            Divider()
                .padding(.vertical, 8)
            
            SummaryItemView(
                icon: "play.circle.fill",
                title: "Kanata Service Running",
                status: serviceStatus
            )
        }
    }
    
    @ViewBuilder
    private func actionSection() -> some View {
        switch systemState {
        case .active:
            // Everything is ready and running
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("KeyPath is Active")
                        .fontWeight(.medium)
                }
                .font(.body)
                .foregroundColor(.green)
                
                Button("Close Setup") {
                    onDismiss()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 32)
            
        case .serviceNotRunning, .ready:
            // Components ready but service not running
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Service Not Running")
                        .fontWeight(.medium)
                }
                .font(.body)
                .foregroundColor(.orange)
                
                Text("All components are installed but the Kanata service is not active.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Start Kanata Service") {
                    onStartService()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 32)
            
        case .conflictsDetected:
            // Conflicts detected
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Conflicts Detected")
                        .fontWeight(.medium)
                }
                .font(.body)
                .foregroundColor(.red)
                
                Text("Please resolve conflicts to continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
            
        default:
            // Components not ready
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "gear.badge.xmark")
                        .foregroundColor(.gray)
                    Text("Setup Incomplete")
                        .fontWeight(.medium)
                }
                .font(.body)
                .foregroundColor(.secondary)
                
                Text("Complete the setup process to start using KeyPath")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Helper Methods
    
    private func openSystemPermissions() {
        // Open the main Privacy & Security settings - users can navigate to Input Monitoring/Accessibility from there
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func createStatusItems() -> [StatusItem] {
        var items: [StatusItem] = []
        
        // Follow the same order as wizard pages: conflicts → permissions → installation → daemon
        
        // 1. Conflicts (first thing to resolve)
        items.append(StatusItem(
            icon: "exclamationmark.triangle",
            title: "No Conflicts",
            status: hasIssueOfType(.conflicts) ? .failed : .completed,
            isNavigable: true,
            targetPage: .conflicts
        ))
        
        // 2. System Permissions (collapsed/expanded based on issues)
        let hasPermissionIssues = hasAnyPermissionIssues()
        items.append(StatusItem(
            icon: "lock.shield",
            title: "System Permissions",
            status: hasPermissionIssues ? .failed : .completed,
            isNavigable: false // Don't navigate on collapsed permissions - sub-items will handle navigation
        ))
        
        // 3. Binary Installation
        items.append(StatusItem(
            icon: "keyboard",
            title: "Binary Installation",
            status: hasIssueOfType(.installation) ? .failed : .completed,
            isNavigable: true,
            targetPage: .installation
        ))
        
        // 4. Karabiner Driver
        items.append(StatusItem(
            icon: "cpu",
            title: "Karabiner Driver",
            status: hasDriverIssues() ? .failed : .completed,
            isNavigable: true,
            targetPage: .installation
        ))
        
        // 5. Daemon Status
        items.append(StatusItem(
            icon: "gear.circle",
            title: "Karabiner Daemon",
            status: hasIssueOfType(.daemon) ? .failed : .completed,
            isNavigable: true,
            targetPage: .daemon
        ))
        
        return items
    }
    
    private func createPermissionStatusItems() -> [StatusItem] {
        var items: [StatusItem] = []
        
        // Input Monitoring Permission
        items.append(StatusItem(
            icon: "eye",
            title: WizardConstants.Titles.inputMonitoring,
            status: stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues),
            isNavigable: true,
            targetPage: .inputMonitoring
        ))
        
        // Accessibility Permission  
        items.append(StatusItem(
            icon: "accessibility",
            title: WizardConstants.Titles.accessibility,
            status: stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues),
            isNavigable: true,
            targetPage: .accessibility
        ))
        
        // Background Services
        items.append(StatusItem(
            icon: "gear.badge",
            title: "Background Services",
            status: stateInterpreter.areBackgroundServicesEnabled(in: issues) ? .completed : .failed,
            isNavigable: true,
            targetPage: .backgroundServices
        ))
        
        return items
    }
    
    private func hasAnyPermissionIssues() -> Bool {
        return stateInterpreter.hasAnyPermissionIssues(in: issues) || 
               !stateInterpreter.areBackgroundServicesEnabled(in: issues)
    }
    
    private var shouldShowServiceStatus: Bool {
        // Show service status when components are ready
        switch systemState {
        case .serviceNotRunning, .ready, .active:
            return true
        default:
            return false
        }
    }
    
    private var serviceStatus: InstallationStatus {
        switch systemState {
        case .active:
            return .completed
        case .serviceNotRunning, .ready:
            return .failed
        default:
            return .notStarted
        }
    }
    
    private func hasIssueOfType(_ category: WizardIssue.IssueCategory) -> Bool {
        issues.contains { $0.category == category }
    }
    
    private func hasDriverIssues() -> Bool {
        // Check for both driver extension permission issues AND driver component issues
        issues.contains { issue in
            // Driver extension permission issue (category: .permissions)
            (issue.category == .permissions && issue.title == "Driver Extension Disabled") ||
            // Karabiner driver component issue (category: .installation)  
            (issue.category == .installation && issue.title == "Karabiner Driver Missing")
        }
    }
}

// MARK: - Supporting Types

private struct StatusItem {
    let icon: String
    let title: String
    let status: InstallationStatus
    let isNavigable: Bool
    let targetPage: WizardPage?
    
    init(icon: String, title: String, status: InstallationStatus, isNavigable: Bool = false, targetPage: WizardPage? = nil) {
        self.icon = icon
        self.title = title
        self.status = status
        self.isNavigable = isNavigable
        self.targetPage = targetPage
    }
}