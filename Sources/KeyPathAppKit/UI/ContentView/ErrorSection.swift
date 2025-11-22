import KeyPathCore
import SwiftUI

struct ErrorSection: View {
  @ObservedObject var kanataManager: KanataViewModel  // Phase 4: MVVM
  @Binding var showingInstallationWizard: Bool
  let error: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
          .font(.headline)

        Text("KeyPath Error")
          .font(.headline)
          .foregroundColor(.primary)

        Spacer()

        Button("Fix Issues") {
          Task {
            AppLogger.shared.log(
              "🔄 [UI] Fix Issues button clicked - attempting to fix configuration and restart")

            // Create a default user config if missing
            let created = await kanataManager.createDefaultUserConfigIfMissing()

            if created {
              await MainActor.run {
                kanataManager.lastError = nil
              }
              AppLogger.shared.log("✅ [UI] Default config created successfully")
            } else {
              AppLogger.shared.log("⚠️ [UI] Config already exists or creation failed")
            }

            // Try to start the service
            _ = await InstallerEngine().run(intent: .repair, using: PrivilegeBroker())

            // If still failing, show wizard
            let context = await InstallerEngine().inspectSystem()
            if !context.services.kanataRunning {
              AppLogger.shared.log("⚠️ [UI] Manual start failed - showing installation wizard")
              showingInstallationWizard = true
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }

      Text(error)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
    .background(Color.orange.opacity(0.1))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
    )
  }
}
