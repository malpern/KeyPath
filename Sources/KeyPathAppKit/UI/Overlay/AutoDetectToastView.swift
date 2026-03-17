import SwiftUI

/// Toast notification shown when a QMK keyboard is detected on plug-in.
///
/// First detection: "Detected [Name] — Switch layout?" with Accept/Dismiss.
/// Repeat detection (binding exists): brief "Switched to [Name]" confirmation.
struct AutoDetectToastView: View {
    let keyboardName: String
    let mode: AutoDetectKeyboardController.ToastMode
    let confidence: KeyboardDetectionIndex.Confidence
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if let subtitleText {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let primaryActionTitle {
                Button(primaryActionTitle) {
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

    private var iconName: String {
        switch mode {
        case .autoSwitch:
            "keyboard"
        case .rememberKeyboard:
            confidence == .low ? "questionmark.keyboard" : "keyboard.badge.ellipsis"
        case .importKeyboard:
            "square.and.arrow.down"
        }
    }

    private var titleText: String {
        switch mode {
        case .autoSwitch:
            "Switched to \(keyboardName)"
        case .rememberKeyboard:
            confidence == .low ? "Possible match: \(keyboardName)" : "Detected \(keyboardName)"
        case .importKeyboard:
            "Detected \(keyboardName)"
        }
    }

    private var subtitleText: String? {
        switch mode {
        case .autoSwitch:
            nil
        case .rememberKeyboard:
            confidence == .low ? "Use this layout and remember it for next time?" : "Using this layout now. Remember it for next time?"
        case .importKeyboard:
            "Import a layout for this keyboard?"
        }
    }

    private var primaryActionTitle: String? {
        switch mode {
        case .autoSwitch:
            nil
        case .rememberKeyboard:
            "Remember"
        case .importKeyboard:
            "Import Layout"
        }
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
