import SwiftUI

/// Toast notification shown when a QMK keyboard is detected on plug-in.
///
/// First detection: "Detected [Name] — Switch layout?" with Accept/Dismiss.
/// Repeat detection (binding exists): brief "Switched to [Name]" confirmation.
struct AutoDetectToastView: View {
    let keyboardName: String
    let mode: AutoDetectKeyboardController.ToastMode
    let confidence: KeyboardDetectionIndex.Confidence
    let errorMessage: String?
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            if mode == .importingKeyboard {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

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
        case .importingKeyboard:
            "square.and.arrow.down"
        case .importSucceeded:
            "checkmark.circle"
        case .importFailed:
            "exclamationmark.triangle"
        }
    }

    private var titleText: String {
        switch mode {
        case .autoSwitch:
            String(localized: "Switched to \(keyboardName)")
        case .rememberKeyboard:
            confidence == .low ? String(localized: "Possible match: \(keyboardName)") : String(localized: "Detected \(keyboardName)")
        case .importKeyboard:
            String(localized: "Detected \(keyboardName)")
        case .importingKeyboard:
            String(localized: "Importing layout for \(keyboardName)")
        case .importSucceeded:
            String(localized: "Imported layout for \(keyboardName)")
        case .importFailed:
            String(localized: "Couldn’t import \(keyboardName)")
        }
    }

    private var subtitleText: String? {
        switch mode {
        case .autoSwitch:
            nil
        case .rememberKeyboard:
            confidence == .low ? String(localized: "Use this layout and remember it for next time?") : String(localized: "Using this layout now. Remember it for next time?")
        case .importKeyboard:
            String(localized: "Import a layout for this keyboard?")
        case .importingKeyboard:
            String(localized: "Fetching the layout and preparing it for KeyPath.")
        case .importSucceeded:
            String(localized: "Using this layout now.")
        case .importFailed:
            errorMessage ?? String(localized: "You can search for a layout instead.")
        }
    }

    private var primaryActionTitle: String? {
        switch mode {
        case .autoSwitch:
            nil
        case .rememberKeyboard:
            String(localized: "Remember")
        case .importKeyboard:
            String(localized: "Import Layout")
        case .importingKeyboard:
            nil
        case .importSucceeded:
            nil
        case .importFailed:
            String(localized: "Search Layouts")
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
