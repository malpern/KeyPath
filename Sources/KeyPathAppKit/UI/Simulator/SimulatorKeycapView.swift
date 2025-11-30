import AppKit
import SwiftUI

/// A clickable keycap for the simulator keyboard.
/// Provides visual feedback on hover and click.
struct SimulatorKeycapView: View {
    let key: PhysicalKey
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Text(key.label)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(borderColor, lineWidth: 1.5)
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

    private var isDark: Bool { colorScheme == .dark }

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
        if isPressed {
            return isDark ? .white.opacity(0.9) : .black.opacity(0.8)
        }
        return isDark ? .white : .black
    }

    private var backgroundColor: Color {
        if isDark {
            // Dark mode: lighter keys on dark background
            if isPressed {
                return Color(white: 0.35)
            } else if isHovered {
                return Color(white: 0.32)
            }
            return Color(white: 0.28)
        } else {
            // Light mode: darker keys for contrast
            if isPressed {
                return Color(white: 0.78)
            } else if isHovered {
                return Color(white: 0.82)
            }
            return Color(white: 0.88)
        }
    }

    private var borderColor: Color {
        if isDark {
            if isPressed {
                return Color(white: 0.55)
            } else if isHovered {
                return Color(white: 0.48)
            }
            return Color(white: 0.42)
        } else {
            if isPressed {
                return Color(white: 0.55)
            } else if isHovered {
                return Color(white: 0.62)
            }
            return Color(white: 0.70)
        }
    }

    private var shadowColor: Color {
        isPressed ? .clear : .black.opacity(isDark ? 0.3 : 0.15)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 0 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 0 : 2
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
