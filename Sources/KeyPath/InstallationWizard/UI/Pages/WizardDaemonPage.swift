import SwiftUI

struct WizardDaemonPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () async -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
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
            
            // Daemon Status
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: daemonRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(daemonRunning ? .green : .red)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Karabiner Virtual HID Device Daemon")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Text(daemonRunning ? "Daemon is running" : "Daemon is not running")
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
                            isFixing: isFixing
                        )
                    }
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Section
            if !daemonRunning {
                VStack(spacing: 16) {
                    Text("The daemon needs to be running for Kanata to communicate with the keyboard hardware.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.body)
                    
                    Button(action: {
                        onAutoFix()
                    }) {
                        HStack {
                            if isFixing {
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
                    .disabled(isFixing)
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
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var daemonRunning: Bool {
        // If there are no daemon issues, assume it's running
        !issues.contains { $0.category == .daemon }
    }
}