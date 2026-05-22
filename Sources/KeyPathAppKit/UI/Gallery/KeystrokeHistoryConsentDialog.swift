import SwiftUI

struct KeystrokeHistoryConsentDialog: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Enable Keystroke History?")
                .font(.headline)

            Text("This shows every keypress, tap-hold decision, and layer change in real time — helping you understand, refine, and debug your keymaps.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            privacyNotice

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("keystroke-history-consent-cancel")

                Button("Enable Keystroke History") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("keystroke-history-consent-confirm")
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380)
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            privacyRow(
                icon: "memorychip",
                text: "Kept in memory only — nothing is saved to disk"
            )
            privacyRow(
                icon: "lock.shield",
                text: "Never leaves your machine"
            )
            privacyRow(
                icon: "xmark.circle",
                text: "Disappears when you quit KeyPath"
            )
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.green)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
        }
    }
}
