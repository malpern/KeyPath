import KeyPathCore
import SwiftUI

struct DiagnosticSummarySection: View {
  let criticalIssues: [KanataDiagnostic]
  @ObservedObject var kanataManager: KanataViewModel  // Phase 4: MVVM
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
        .controlSize(.small)
      }

      VStack(alignment: .leading, spacing: 4) {
        ForEach(criticalIssues.prefix(3).indices, id: \.self) { index in
          let issue = criticalIssues[index]
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
            }
          }
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
