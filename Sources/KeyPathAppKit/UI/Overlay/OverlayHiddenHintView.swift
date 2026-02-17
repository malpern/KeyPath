import SwiftUI

/// Education message shown after the overlay is hidden, teaching users
/// the keyboard shortcut to bring it back: Option + Command + K.
/// Shows up to 4 times total across app restarts.
struct OverlayHiddenHintView: View {
    private static let bubbleBackground = Color(white: 0.08, opacity: 0.95)

    var body: some View {
        HStack(spacing: 6) {
            Text("Overlay Hidden")
                .foregroundStyle(.secondary)

            Text("—")
                .foregroundStyle(.secondary.opacity(0.4))

            Text("press")
                .foregroundStyle(.secondary)

            HStack(spacing: 3) {
                ModifierKeyChip(symbol: "⌥")
                ModifierKeyChip(symbol: "⌘")
                ModifierKeyChip(symbol: "K")
            }

            Text("to bring it back")
                .foregroundStyle(.secondary)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Self.bubbleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

#Preview("Overlay Hidden Hint") {
    ZStack {
        Color.black.opacity(0.3)
        OverlayHiddenHintView()
    }
    .frame(width: 500, height: 100)
}
