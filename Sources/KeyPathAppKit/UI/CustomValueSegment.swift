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
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: isLast ? 6 : 0)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                    .clipShape(SegmentShape(isFirst: false, isLast: isLast))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-custom-segment-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
