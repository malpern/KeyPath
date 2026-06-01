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
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Script Execution Warning")
                .font(.title2.weight(.bold))

            // Script path
            VStack(spacing: 4) {
                Text("You are about to run:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(scriptPath)
                    .font(.footnote.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 4))
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

/// View shown when script execution is disabled and user tries to run a script.
/// Offers to enable scripts directly rather than redirecting to Settings.
struct ScriptExecutionDisabledView: View {
    let onAllow: () -> Void
    let onCancel: () -> Void

    @State private var showEnableConfirmation = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("Scripts Are Turned Off")
                .font(.title2.weight(.bold))

            Text("This shortcut runs a script, but script execution is currently off.\n\nAllow scripts to use this shortcut.")
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

                Button("Allow Scripts") {
                    showEnableConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("script-disabled-allow-button")
            }
        }
        .padding(24)
        .frame(width: 380)
        .sheet(isPresented: $showEnableConfirmation) {
            ScriptEnableConfirmationView(
                onAllow: {
                    showEnableConfirmation = false
                    onAllow()
                },
                onCancel: {
                    showEnableConfirmation = false
                }
            )
        }
    }
}

/// Confirmation dialog for globally enabling script execution.
/// Shown when the user first toggles scripts on in Settings or saves a script mapping.
struct ScriptEnableConfirmationView: View {
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Allow Script Shortcuts?")
                .font(.title2.weight(.bold))

            Text("Script shortcuts can run programs and commands on your Mac when you press a key. This is powerful but requires trust in the scripts you add.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                warningPoint(
                    icon: "terminal.fill",
                    text: "Scripts can run any command on your Mac"
                )
                warningPoint(
                    icon: "folder.fill",
                    text: "Scripts can read, change, or delete files"
                )
                warningPoint(
                    icon: "network",
                    text: "Scripts can connect to the internet"
                )
            }
            .padding(.horizontal, 8)

            Text("You can turn this off anytime in Settings.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("script-enable-cancel-button")

                Button("Allow Scripts") {
                    ScriptSecurityService.shared.isScriptExecutionEnabled = true
                    onAllow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("script-enable-allow-button")
            }
        }
        .padding(24)
        .frame(width: 400)
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

/// Confirmation dialog for enabling the "skip confirmation dialog" bypass.
/// This is the riskier sub-toggle: with it on, scripts run with no per-run
/// warning, so flipping it on warrants its own explicit confirmation.
struct ScriptBypassConfirmationView: View {
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Skip the Per-Script Warning?")
                .font(.title2.weight(.bold))

            Text("With this on, scripts run the moment you press their shortcut — KeyPath will no longer show a warning before each one. Only do this if you fully trust every script you've added.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                warningPoint(
                    icon: "bolt.fill",
                    text: "Scripts run immediately, with no confirmation"
                )
                warningPoint(
                    icon: "terminal.fill",
                    text: "A mistaken or malicious script runs unchecked"
                )
            }
            .padding(.horizontal, 8)

            Text("You can turn this back on anytime in Settings.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("script-bypass-cancel-button")

                Button("Skip Warnings") {
                    ScriptSecurityService.shared.bypassFirstRunDialog = true
                    onAllow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("script-bypass-allow-button")
            }
        }
        .padding(24)
        .frame(width: 400)
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

#Preview("Enable Confirmation") {
    ScriptEnableConfirmationView(
        onAllow: {},
        onCancel: {}
    )
}

#Preview("Bypass Confirmation") {
    ScriptBypassConfirmationView(
        onAllow: {},
        onCancel: {}
    )
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
        onAllow: {},
        onCancel: {}
    )
}
