import SwiftUI

struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onStartService: () -> Void
    let onDismiss: () -> Void
    
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
            SummaryItemView(
                icon: item.icon,
                title: item.title,
                status: item.status
            )
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
    
    private func createStatusItems() -> [StatusItem] {
        var items: [StatusItem] = []
        
        // Binary Installation
        items.append(StatusItem(
            icon: "keyboard",
            title: "Binary Installation",
            status: hasIssueOfType(.installation) ? .failed : .completed
        ))
        
        // Service Configuration
        items.append(StatusItem(
            icon: "gear",
            title: "Kanata Service",
            status: .completed // Always available with direct execution
        ))
        
        // Driver Installation
        items.append(StatusItem(
            icon: "cpu",
            title: "Karabiner Driver",
            status: hasDriverIssues() ? .failed : .completed
        ))
        
        // Daemon Status
        items.append(StatusItem(
            icon: "gear.circle",
            title: "Karabiner Daemon",
            status: hasIssueOfType(.daemon) ? .failed : .completed
        ))
        
        // Conflicts
        items.append(StatusItem(
            icon: "exclamationmark.triangle",
            title: "No Conflicts",
            status: hasIssueOfType(.conflicts) ? .failed : .completed
        ))
        
        // Permissions
        items.append(StatusItem(
            icon: "lock.shield",
            title: "System Permissions",
            status: hasIssueOfType(.permissions) ? .failed : .completed
        ))
        
        return items
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
        // Check for driver-related installation issues
        issues.contains { issue in
            issue.category == .installation && 
            (issue.title.contains("Driver") || issue.title.contains("Karabiner"))
        }
    }
}

// MARK: - Supporting Types

private struct StatusItem {
    let icon: String
    let title: String
    let status: InstallationStatus
}