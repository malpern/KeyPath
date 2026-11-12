import KeyPathRulesCore
import SwiftUI

// MARK: - Undo Card

struct UndoCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    var body: some View {
        ActionCard(
            icon: "arrow.uturn.backward",
            title: String(localized: "Undo", comment: "Window snapping card: undo the last window move"),
            isHovered: isHovered,
            accentColor: .gray
        ) {
            SnapKeyBadge(key: "Z", color: .gray, isHighlighted: isHovered)
        }
        .onHover { isHovered = $0 }
    }
}
