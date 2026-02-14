import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Transform Keycap

struct TransformKeycap: View {
    let label: String
    let isHighlighted: Bool
    let isInput: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular, design: .monospaced))
            .frame(width: 22, height: 22)
            .foregroundColor(isHighlighted ? (isInput ? .primary : .accentColor) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHighlighted && !isInput ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHighlighted ? (isInput ? Color.primary.opacity(0.3) : Color.accentColor.opacity(0.5)) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}
