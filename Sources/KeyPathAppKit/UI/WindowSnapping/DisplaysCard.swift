import KeyPathRulesCore
import SwiftUI

// MARK: - Displays Card

struct DisplaysCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    var body: some View {
        ActionCard(
            icon: "display.2",
            title: String(localized: "Displays", comment: "Window snapping card: move windows between displays"),
            isHovered: isHovered,
            accentColor: .orange
        ) {
            HStack(spacing: 8) {
                SnapKeyBadge(key: "[", color: .orange, isHighlighted: isHovered, size: .small)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                SnapKeyBadge(key: "]", color: .orange, isHighlighted: isHovered, size: .small)
            }
        }
        .onHover { isHovered = $0 }
    }
}
