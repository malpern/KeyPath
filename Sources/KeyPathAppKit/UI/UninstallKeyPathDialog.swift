import AppKit
import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataViewModel

    // Local state tracking
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var didSucceed = false

    private enum Field { case primary }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 20) {
            if didSucceed {
                // Success state
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Uninstall Complete")
                    .font(.title2.bold())

                Text("KeyPath has been successfully uninstalled. Your configuration file has been preserved.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .frame(minWidth: 80)
                }
                .focused($focusedField, equals: .primary)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else {
                // Confirmation/working state
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)

                Text("Uninstall KeyPath?")
                    .font(.title2.bold())

                Text("This will remove all services, helpers, and the app. Your configuration file will be preserved.")
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
                    .focused($focusedField, equals: .primary)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(isRunning)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(32)
        .frame(width: 320)
        .onAppear { focusedField = .primary }
        .animation(.easeInOut(duration: 0.3), value: didSucceed)
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
        }
    }
}
