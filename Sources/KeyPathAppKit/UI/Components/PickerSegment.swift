import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct PickerSegment: View {
    let label: String
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : (isHovered ? .primary : .secondary))
                .padding(.horizontal, 14)
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
        .accessibilityIdentifier("rules-summary-segment-button-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
