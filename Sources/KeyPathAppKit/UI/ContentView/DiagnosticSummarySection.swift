import KeyPathCore
import SwiftUI

/// Helper view for individual diagnostic issue rows
private struct DiagnosticIssueRow: View {
    let issue: KanataDiagnostic
    @ObservedObject var kanataManager: KanataViewModel

    var body: some View {
        HStack {
            Text(issue.severity.emoji)
            Text(issue.title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if issue.canAutoFix {
                Button("Fix") {
                    Task {
                        await kanataManager.autoFixDiagnostic(issue)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityIdentifier("diagnostic-fix-button-\(issue.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                .accessibilityLabel("Fix \(issue.title)")
            }
        }
    }
}

struct DiagnosticSummarySection: View {
    let criticalIssues: [KanataDiagnostic]
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    let onViewDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.red)
                    .font(.headline)

                Text("System Issues Detected")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("View Details") {
                    onViewDetails()
                }
                .buttonStyle(.borderedProminent)
                .focusable(false) // Prevent keyboard activation on main page
                .controlSize(.small)
                .accessibilityIdentifier("diagnostic-view-details-button")
                .accessibilityLabel("View diagnostic details")
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(criticalIssues.prefix(3).indices, id: \.self) { index in
                    DiagnosticIssueRow(
                        issue: criticalIssues[index],
                        kanataManager: kanataManager
                    )
                }

                if criticalIssues.count > 3 {
                    Text("... and \(criticalIssues.count - 3) more issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}
