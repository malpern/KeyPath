import AppKit
import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(KanataViewModel.self) private var kanataManager

    @State private var isRunning = false
    @State private var lastError: String?
    @State private var didSucceed = false
    @State private var hasScheduledQuit = false
    @State private var autoQuitWorkItem: DispatchWorkItem?
    @State private var removeVirtualHID = false
    @State private var canUseEmergencyCleanup = false
    @State private var showingEmergencyCleanupConfirmation = false

    var body: some View {
        VStack(spacing: 20) {
            if didSucceed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)

                Text("Uninstall Complete")
                    .font(.title2.bold())
            } else {
                Image(systemName: "trash.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)

                Text("Uninstall KeyPath?")
                    .font(.title2.bold())

                Text("This will remove all services, helpers, and the app. Your configuration file will be preserved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Toggle(isOn: $removeVirtualHID) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also remove the virtual keyboard driver")
                            .font(.caption)
                        Text("Other tools (e.g. Karabiner-Elements) may rely on it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(isRunning)
                .accessibilityIdentifier("uninstall-remove-vhid-toggle")

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastError {
                    UninstallRecoveryMessage(
                        error: lastError,
                        canUseEmergencyCleanup: canUseEmergencyCleanup
                    )
                }

                UninstallActionButtons(
                    isRunning: isRunning,
                    hasError: lastError != nil,
                    canUseEmergencyCleanup: canUseEmergencyCleanup,
                    cancel: { dismiss() },
                    requestEmergencyCleanup: {
                        showingEmergencyCleanupConfirmation = true
                    },
                    uninstall: {
                        Task { await performUninstall() }
                    }
                )
            }
        }
        .padding(32)
        .frame(width: 400)
        .animation(.easeInOut(duration: 0.3), value: didSucceed)
        .onChange(of: didSucceed) { _, newValue in
            if newValue { scheduleQuit() }
        }
        .onAppear {
            if didSucceed { scheduleQuit() }
        }
        .alert("Use Emergency Cleanup?", isPresented: $showingEmergencyCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                Task { await performUninstall(allowAdminFallback: true) }
            }
            .accessibilityIdentifier("uninstall-emergency-confirm-button")
        } message: {
            Text(
                "Emergency Cleanup runs KeyPath's bundled cleanup tool with administrator privileges. macOS will ask for your password."
            )
        }
    }

    private func performUninstall(allowAdminFallback: Bool = false) async {
        guard !isRunning else { return }

        isRunning = true
        didSucceed = false
        lastError = nil
        canUseEmergencyCleanup = false

        let report = await kanataManager.uninstall(
            deleteConfig: false,
            removeVirtualHID: removeVirtualHID,
            allowAdminFallback: allowAdminFallback
        )

        isRunning = false
        didSucceed = report.success
        lastError = report.failureReason
        canUseEmergencyCleanup = report.recommendedRecovery == .emergencyCleanup
    }

    private func scheduleQuit() {
        guard !hasScheduledQuit else { return }
        hasScheduledQuit = true
        let work = DispatchWorkItem {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        }
        autoQuitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}

private struct UninstallRecoveryMessage: View {
    let error: String
    let canUseEmergencyCleanup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Uninstall needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)

            if canUseEmergencyCleanup {
                Text("Try again, or use Emergency Cleanup to remove the remaining system files with an administrator password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("uninstall-recovery-message")
    }
}

private struct UninstallActionButtons: View {
    let isRunning: Bool
    let hasError: Bool
    let canUseEmergencyCleanup: Bool
    let cancel: () -> Void
    let requestEmergencyCleanup: () -> Void
    let uninstall: () -> Void

    var body: some View {
        ViewThatFits {
            HStack(spacing: 12) { buttons }
            VStack(spacing: 10) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Cancel", action: cancel)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("uninstall-cancel-button")
            .accessibilityLabel("Cancel")

        if canUseEmergencyCleanup {
            Button("Emergency Cleanup…", action: requestEmergencyCleanup)
                .disabled(isRunning)
                .accessibilityIdentifier("uninstall-emergency-cleanup-button")
                .accessibilityLabel("Use Emergency Cleanup")
        }

        Button(role: .destructive, action: uninstall) {
            Text(primaryButtonTitle)
                .frame(minWidth: 80)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isRunning)
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityIdentifier("uninstall-confirm-button")
        .accessibilityLabel(primaryButtonAccessibilityLabel)
    }

    private var primaryButtonTitle: String {
        if isRunning { return "Working…" }
        return hasError ? "Try Again" : "Uninstall"
    }

    private var primaryButtonAccessibilityLabel: String {
        if isRunning { return "Uninstalling" }
        return hasError ? "Try uninstall again" : "Uninstall KeyPath"
    }
}
