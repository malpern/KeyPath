import SwiftUI

/// Double opt-in flow for activity logging
/// Requires user to acknowledge privacy implications before enabling
struct ActivityOptInFlow: View {
    @Binding var isPresented: Bool
    @State private var confirmedLocalOnly = false
    @State private var confirmedEncrypted = false
    @State private var isEnabling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Enable Activity Logging")
                    .font(.headline)
            }

            // Description
            Text("Activity logging helps you understand your keyboard usage patterns by tracking:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                BulletPoint("App launches and switches")
                BulletPoint("Keyboard shortcuts (modifier + key combinations)")
                BulletPoint("KeyPath actions (layer switches, app launches)")
            }
            .padding(.leading, 8)

            Divider()

            // Privacy checkboxes
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $confirmedLocalOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I understand data is stored locally only")
                            .font(.body)
                        Text("Your activity data never leaves this device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("activity-logging-local-only-checkbox")

                Toggle(isOn: $confirmedEncrypted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I understand data is encrypted")
                            .font(.body)
                        Text("Protected with a device-bound encryption key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("activity-logging-encrypted-checkbox")
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("activity-logging-cancel-button")

                Spacer()

                Button {
                    enableLogging()
                } label: {
                    if isEnabling {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Enable Logging")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canEnable || isEnabling)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("activity-logging-enable-button")
            }
        }
        .padding(24)
        .frame(width: 400, height: 380)
    }

    private var canEnable: Bool {
        confirmedLocalOnly && confirmedEncrypted
    }

    private func enableLogging() {
        isEnabling = true

        Task { @MainActor in
            // Record consent
            PreferencesService.shared.activityLoggingConsentDate = Date()
            PreferencesService.shared.activityLoggingEnabled = true

            // Enable the logger
            await ActivityLogger.shared.enable()

            isEnabling = false
            isPresented = false
        }
    }
}

/// Helper view for bullet points
private struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    ActivityOptInFlow(isPresented: .constant(true))
}
