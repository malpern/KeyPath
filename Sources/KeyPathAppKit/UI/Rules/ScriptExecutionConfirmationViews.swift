import SwiftUI

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
                    text: String(localized: "Scripts can run any command on your Mac")
                )
                warningPoint(
                    icon: "folder.fill",
                    text: String(localized: "Scripts can read, change, or delete files")
                )
                warningPoint(
                    icon: "network",
                    text: String(localized: "Scripts can connect to the internet")
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

#Preview("Enable Confirmation") {
    ScriptEnableConfirmationView(
        onAllow: {},
        onCancel: {}
    )
}
