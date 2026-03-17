import SwiftUI

/// Toast notification shown when a QMK keyboard is detected on plug-in.
///
/// First detection: "Detected [Name] — Switch layout?" with Accept/Dismiss.
/// Repeat detection (binding exists): brief "Switched to [Name]" confirmation.
struct AutoDetectToastView: View {
    let keyboardName: String
    let isAutoSwitch: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.title3)
                .foregroundStyle(.secondary)

            if isAutoSwitch {
                Text("Switched to **\(keyboardName)**")
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                Text("Detected **\(keyboardName)** — Switch layout?")
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Spacer()

            if !isAutoSwitch {
                Button("Accept") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("auto-detect-accept-button")
            }

            dismissButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            withAnimation { isVisible = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("auto-detect-toast")
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
        .accessibilityIdentifier("auto-detect-dismiss-button")
    }
}
