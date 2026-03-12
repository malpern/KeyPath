import SwiftUI

// MARK: - Spaces Card

struct SpacesCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    private var prevKey: String {
        convention == .standard ? "," : "A"
    }

    private var nextKey: String {
        convention == .standard ? "." : "S"
    }

    var body: some View {
        ActionCard(
            icon: "square.stack.3d.up",
            title: "Spaces",
            isHovered: isHovered,
            accentColor: .cyan
        ) {
            HStack(spacing: 8) {
                SnapKeyBadge(key: prevKey, color: .cyan, isHighlighted: isHovered, size: .small)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                SnapKeyBadge(key: nextKey, color: .cyan, isHighlighted: isHovered, size: .small)
            }
        }
        .onHover { isHovered = $0 }
    }
}
