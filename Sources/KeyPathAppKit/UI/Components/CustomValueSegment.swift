import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// A segment that displays a custom value (with optional icon for system actions)
struct CustomValueSegment: View {
    let label: String
    let sfSymbol: String?
    let isSelected: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : (isHovered ? .primary : .secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.primary.opacity(isHovered ? 0.15 : 0.08),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-custom-segment-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
