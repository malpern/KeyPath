import AppKit
import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataViewModel

    // Local state tracking
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var didSucceed = false

    private enum Field { case uninstall }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 20) {
            // Icon and title
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Uninstall KeyPath?")
                .font(.title2.bold())

            Text("This will remove all services, helpers, and the app.\nYour configuration file will be preserved.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Status
            if isRunning {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let error = lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.caption)
            } else if didSucceed {
                Label("Uninstall complete", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button(role: .destructive) {
                    Task { await performUninstall() }
                } label: {
                    Text(isRunning ? "Working…" : "Uninstall")
                        .frame(minWidth: 80)
                }
                .focused($focusedField, equals: .uninstall)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isRunning)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(32)
        .frame(width: 320)
        .onAppear { focusedField = .uninstall }
    }

    // MARK: - Actions

    private func performUninstall() async {
        guard !isRunning else { return }

        await MainActor.run {
            isRunning = true
            didSucceed = false
            lastError = nil
        }

        let report = await kanataManager.uninstall(deleteConfig: false)

        await MainActor.run {
            isRunning = false
            didSucceed = report.success
            lastError = report.failureReason

            if report.success {
                // Show success alert, then quit app when user clicks OK
                let alert = NSAlert()
                alert.messageText = "Uninstall Complete"
                alert.informativeText = "KeyPath has been successfully uninstalled.\n\nYour configuration file has been preserved for future reinstalls.\n\nThe app will now quit."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()

                // Quit the app
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
