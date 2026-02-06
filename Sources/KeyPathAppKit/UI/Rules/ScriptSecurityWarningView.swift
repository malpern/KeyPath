import SwiftUI

/// Warning dialog shown when user first attempts to run a script.
/// Explains the security risks and allows user to proceed or cancel.
struct ScriptSecurityWarningView: View {
    let scriptPath: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var dontShowAgain = false

    var body: some View {
        VStack(spacing: 20) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Script Execution Warning")
                .font(.title2.weight(.bold))

            // Script path
            VStack(spacing: 4) {
                Text("You are about to run:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(scriptPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
            }

            // Risk warnings
            VStack(alignment: .leading, spacing: 10) {
                warningPoint(
                    icon: "terminal.fill",
                    text: "Scripts can execute any command on your system"
                )
                warningPoint(
                    icon: "folder.fill",
                    text: "Scripts can read, modify, or delete your files"
                )
                warningPoint(
                    icon: "network",
                    text: "Scripts can make network connections"
                )
                warningPoint(
                    icon: "lock.open.fill",
                    text: "Malicious scripts could harm your system"
                )
            }
            .padding(.horizontal, 8)

            Text("Only run scripts from sources you trust.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Don't show again checkbox
            Toggle(isOn: $dontShowAgain) {
                Text("Don't show this warning again")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("script-warning-dont-show-toggle")

            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("script-warning-cancel-button")

                Button("I Understand, Run Script") {
                    if dontShowAgain {
                        ScriptSecurityService.shared.bypassFirstRunDialog = true
                    }
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("script-warning-confirm-button")
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func warningPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

/// View shown when script execution is disabled and user tries to run a script
struct ScriptExecutionDisabledView: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Script Execution Disabled")
                .font(.title2.weight(.bold))

            Text("Script execution is currently disabled for security.\n\nTo run scripts from Quick Launcher, enable it in Settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("script-disabled-cancel-button")

                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("script-disabled-settings-button")
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

#Preview("Warning Dialog") {
    ScriptSecurityWarningView(
        scriptPath: "~/Scripts/backup.sh",
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Disabled Dialog") {
    ScriptExecutionDisabledView(
        onOpenSettings: {},
        onCancel: {}
    )
}
