import SwiftUI

struct WizardConflictsPage: View {
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
            
            // Issues List
            if !issues.isEmpty {
                VStack(spacing: 16) {
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
            
            // Explanation
            VStack(alignment: .leading, spacing: 16) {
                Text("Common conflicting processes:")
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
            
            // Action Buttons
            VStack(spacing: 12) {
                if !issues.isEmpty && issues.first?.autoFixAction != nil {
                    Button("Terminate Conflicting Processes") {
                        onAutoFix()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isFixing)
                }
                
                Button("Check Again") {
                    Task {
                        await onRefresh()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isFixing)
            }
        }
        .padding()
    }
}