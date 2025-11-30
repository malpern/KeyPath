import SwiftUI

/// A clickable keycap for the simulator keyboard.
/// Provides visual feedback on hover and click.
struct SimulatorKeycapView: View {
    let key: PhysicalKey
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Text(key.label)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
        .animation(.easeInOut(duration: 0.08), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    // MARK: - Styling

    private var fontSize: CGFloat {
        // Smaller font for wider keys to fit labels
        if key.width > 1.5 {
            return 10
        } else if key.width > 1.0 {
            return 11
        }
        return 12
    }

    private var foregroundColor: Color {
        isPressed ? .primary.opacity(0.8) : .primary
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color(white: 0.85)
        } else if isHovered {
            return Color(white: 0.92)
        }
        return Color(white: 0.96)
    }

    private var borderColor: Color {
        if isPressed {
            return Color(white: 0.5)
        } else if isHovered {
            return Color(white: 0.65)
        }
        return Color(white: 0.8)
    }

    private var shadowColor: Color {
        isPressed ? .clear : .black.opacity(0.08)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 0 : 1
    }

    private var shadowOffset: CGFloat {
        isPressed ? 0 : 1
    }
}

// MARK: - Preview

#Preview("Regular Key") {
    SimulatorKeycapView(
        key: PhysicalKey(keyCode: 0, label: "A", x: 0, y: 0),
        onTap: {}
    )
    .frame(width: 40, height: 40)
    .padding()
}

#Preview("Wide Key") {
    SimulatorKeycapView(
        key: PhysicalKey(keyCode: 48, label: "Tab", x: 0, y: 0, width: 1.5),
        onTap: {}
    )
    .frame(width: 60, height: 40)
    .padding()
}
