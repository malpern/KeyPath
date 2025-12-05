import AppKit
import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataViewModel

    // Local state tracking
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var didSucceed = false
    @State private var hasScheduledQuit = false
    @State private var autoQuitWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 20) {
            if didSucceed {
                // Success state
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Uninstall Complete")
                    .font(.title2.bold())
            } else {
                // Confirmation/working state
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("Uninstall KeyPath?")
                    .font(.title2.bold())

                Text("This will remove all services, helpers, and the app. Your configuration file will be preserved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Status
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let error = lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
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
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(32)
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.3), value: didSucceed)
        .onChange(of: didSucceed) { _, newValue in
            if newValue { scheduleQuit() }
        }
        .onAppear {
            if didSucceed { scheduleQuit() }
        }
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

    private func scheduleQuit() {
        guard !hasScheduledQuit else { return }
        hasScheduledQuit = true
        let work = DispatchWorkItem {
            // Must dismiss the modal sheet first, then terminate to avoid the NSBeep.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        }
        autoQuitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
