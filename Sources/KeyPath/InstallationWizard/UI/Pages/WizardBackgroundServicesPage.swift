import SwiftUI

struct WizardBackgroundServicesPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () async -> Void
    let kanataManager: KanataManager
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "gear.badge")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Background Services")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Karabiner background services must be enabled for proper keyboard functionality.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            
            // Services Status
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: backgroundServicesEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(backgroundServicesEnabled ? .green : .orange)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Karabiner Background Services")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Text(backgroundServicesEnabled ? "Services are enabled" : "Services not enabled in Login Items")
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
            
            // Issues (if any)
            if !issues.isEmpty {
                VStack(spacing: 12) {
                    ForEach(issues) { issue in
                        IssueCardView(
                            issue: issue,
                            onAutoFix: issue.autoFixAction != nil ? onAutoFix : nil,
                            isFixing: isFixing,
                            kanataManager: kanataManager
                        )
                    }
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Section
            if !backgroundServicesEnabled {
                VStack(spacing: 16) {
                    Text("These services need to be manually added to Login Items for automatic startup.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.body)
                    
                    VStack(spacing: 12) {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        HStack(spacing: 12) {
                            Button("Open Karabiner Folder") {
                                openKarabinerFolderInFinder()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Show Help") {
                                // This will be handled by the parent view
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button("Check Status") {
                            Task {
                                await onRefresh()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: 350)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Background services are enabled!")
                            .fontWeight(.medium)
                    }
                    
                    Text("Karabiner services will start automatically at login.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var backgroundServicesEnabled: Bool {
        // If there are no background services issues, assume they're enabled
        !issues.contains { $0.category == .backgroundServices }
    }
    
    // MARK: - Helper Methods
    
    private func openKarabinerFolderInFinder() {
        let karabinerPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/"
        if let url = URL(string: "file://\(karabinerPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? karabinerPath)") {
            NSWorkspace.shared.open(url)
        }
    }
}