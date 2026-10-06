import AppKit
import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(KanataViewModel.self) private var kanataManager
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var didSucceed = false
    @State private var backupMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: didSucceed ? "checkmark.circle.fill" : "trash.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(didSucceed ? .green : .red)
            Text(didSucceed ? "Uninstall Complete" : "Uninstall KeyPath?")
                .font(.title2.bold())
            if didSucceed {
                Text(backupMessage ?? "Your backup is in Downloads. KeyPath will now quit.")
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text("Your rules and settings will be backed up in Downloads. KeyPath will stop remapping, restore its keyboard mappings, clear saved settings, and move the app to Trash. Reinstalling starts fresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("macOS permission grants will remain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastError {
                    Text(lastError)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("uninstall-recovery-message")
                }
                if isRunning { ProgressView().controlSize(.small) }
                HStack {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isRunning)
                        .accessibilityIdentifier("uninstall-cancel-button")
                    Button(lastError == nil ? "Back Up and Uninstall" : "Try Again", role: .destructive) {
                        Task { await performUninstall() }
                    }
                    .disabled(isRunning)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("uninstall-confirm-button")
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width: 440)
        .interactiveDismissDisabled(isRunning || didSucceed)
    }

    private func performUninstall() async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        let report = await kanataManager.uninstall(deleteConfig: true)
        isRunning = false
        didSucceed = report.success
        lastError = report.failureReason
        if report.success {
            backupMessage = report.logs.first
            try? await Task.sleep(for: .seconds(2))
            NSApplication.shared.terminate(nil)
        }
    }
}
