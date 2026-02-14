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
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 70)
                .background(
                    RoundedRectangle(cornerRadius: isFirst ? 6 : (isLast ? 6 : 0))
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                        .clipShape(SegmentShape(isFirst: isFirst, isLast: isLast))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-segment-button-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
