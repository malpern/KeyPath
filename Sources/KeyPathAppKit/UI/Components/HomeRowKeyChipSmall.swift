import SwiftUI

/// Small key chip showing letter above modifier symbol (for home row mods summary)
struct HomeRowKeyChipSmall: View {
    let letter: String
    let symbol: String
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 14, weight: .medium))
            if !symbol.isEmpty {
                Text(symbol)
                    .font(.system(size: 12))
                    .foregroundColor(isHovered ? Color(NSColor.windowBackgroundColor).opacity(0.8) : Color.secondary)
            }
        }
        .frame(width: 36, height: 40)
        .foregroundColor(isHovered ? Color(NSColor.windowBackgroundColor) : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
