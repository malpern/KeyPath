import SwiftUI

// MARK: - Undo Card

struct UndoCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    var body: some View {
        ActionCard(
            icon: "arrow.uturn.backward",
            title: "Undo",
            isHovered: isHovered,
            accentColor: .gray
        ) {
            SnapKeyBadge(key: "Z", color: .gray, isHighlighted: isHovered)
        }
        .onHover { isHovered = $0 }
    }
}
