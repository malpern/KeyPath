import KeyPathCore
import SwiftUI

struct DiagnosticSummaryView: View {
    let criticalIssues: [KanataDiagnostic]
    let onViewDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Issues Detected")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(
                        "\(criticalIssues.count) critical issue\(criticalIssues.count == 1 ? "" : "s") need attention"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Button(
                    action: onViewDiagnostics,
                    label: {
                        Text("View Details")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityIdentifier("diagnostic-summary-view-details-button")
                .accessibilityLabel("View diagnostic details")
            }

            // Show first 2 critical issues as preview
            ForEach(Array(criticalIssues.prefix(2).enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName: issue.severity == .critical
                            ? "exclamationmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(issue.severity == .critical ? .red : .orange)
                    .font(.caption)
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if !issue.description.isEmpty {
                            Text(issue.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if criticalIssues.count > 2 {
                Text(
                    "... and \(criticalIssues.count - 2) more issue\(criticalIssues.count - 2 == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 16)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
