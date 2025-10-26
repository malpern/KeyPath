import SwiftUI

struct ErrorSection: View {
    @ObservedObject var kanataManager: KanataViewModel
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
                        AppLogger.shared.log("🔄 [UI] Fix Issues button clicked - attempting to fix configuration and restart")

                        // Create a default user config if missing
                        let created = await kanataManager.createDefaultUserConfigIfMissing()

                        if created {
                            await MainActor.run { kanataManager.lastError = nil }
                            AppLogger.shared.log("✅ [UI] Created default config at ~/Library/Application Support/KeyPath/keypath.kbd")
                        } else {
                            // Still not fixed – open wizard to guide the user
                            showingInstallationWizard = true
                        }

                        // Try starting after config creation
                        await kanataManager.startKanata()
                        await kanataManager.updateStatus()
                        AppLogger.shared.log("🔄 [UI] Fix Issues completed - service status: \(kanataManager.isRunning)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

