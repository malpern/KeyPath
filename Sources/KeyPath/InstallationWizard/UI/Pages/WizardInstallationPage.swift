import SwiftUI

struct WizardInstallationPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () async -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
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
                    status: componentStatus(for: "Kanata Binary")
                )
                
                InstallationItemView(
                    title: "Kanata Service",
                    description: "Direct kanata execution with --watch support",
                    status: .completed // Always available
                )
                
                InstallationItemView(
                    title: "Karabiner Driver",
                    description: "Virtual keyboard driver for input capture",
                    status: componentStatus(for: "Karabiner Driver")
                )
            }
            .padding(.horizontal, 40)
            
            // Issues (if any)
            if !issues.isEmpty {
                VStack(spacing: 12) {
                    ForEach(issues) { issue in
                        IssueCardView(
                            issue: issue,
                            onAutoFix: issue.autoFixAction != nil ? onAutoFix : nil,
                            isFixing: isFixing
                        )
                    }
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Buttons
            if isFixing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Installing components...")
                        .foregroundColor(.secondary)
                }
            } else if allComponentsInstalled {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        Text("Components installed")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Button("Install Components") {
                        onAutoFix()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("Administrator password required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    
    private func componentStatus(for componentName: String) -> InstallationStatus {
        // Check if there's an issue for this component
        let hasIssue = issues.contains { issue in
            issue.category == .installation && issue.title.contains(componentName)
        }
        
        return hasIssue ? .failed : .completed
    }
    
    private var allComponentsInstalled: Bool {
        // No installation issues means all components are installed
        !issues.contains { $0.category == .installation }
    }
}