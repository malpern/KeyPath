import SwiftUI

// MARK: - Layer Picker Item Button Style

/// Custom button style for layer picker items with hover effect
struct LayerPickerItemButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : (configuration.isPressed ? 0.15 : 0)))
            )
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
