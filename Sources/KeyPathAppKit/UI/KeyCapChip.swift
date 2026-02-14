import SwiftUI

// MARK: - KeyCap styling for key labels

struct KeyCapChip: View {
    let text: String
    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(isHovered ? Color(NSColor.windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
            }
    }
}
