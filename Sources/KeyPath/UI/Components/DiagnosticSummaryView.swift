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

                    Text("\(criticalIssues.count) critical issue\(criticalIssues.count == 1 ? "" : "s") need attention")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("View Diagnostics") { onViewDiagnostics() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(criticalIssues.enumerated()), id: \.offset) { _, issue in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 6, height: 6)
                        Text("[\(issue.category.rawValue)] \(issue.title)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.06))
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

