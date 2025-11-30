import AppKit
import SwiftUI

/// A clickable keycap for the simulator keyboard.
/// Click for tap, long-press for hold.
/// Highlights when pressed via physical keyboard.
struct SimulatorKeycapView: View {
    let key: PhysicalKey
    let isExternallyPressed: Bool  // From physical keyboard
    let onTap: () -> Void
    let onHold: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var isHolding = false

    /// Combined pressed state (either from click or external keyboard)
    private var showAsPressed: Bool {
        isPressed || isExternallyPressed
    }

    var body: some View {
        Text(key.label)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(currentBackgroundColor)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(currentBorderColor, lineWidth: currentBorderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
            .scaleEffect(showAsPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 0.08), value: showAsPressed)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                    if pressing {
                        isHolding = false
                    }
                }
            }) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHolding = true
                }
                onHold()
                // Reset holding state after brief feedback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        isHolding = false
                    }
                }
            }
    }

    // MARK: - Styling

    private var isDark: Bool { colorScheme == .dark }

    private var fontSize: CGFloat {
        if key.width > 1.5 {
            return 10
        } else if key.width > 1.0 {
            return 11
        }
        return 12
    }

    private var foregroundColor: Color {
        if showAsPressed {
            return isDark ? .white.opacity(0.9) : .black.opacity(0.8)
        }
        return isDark ? .white : .black
    }

    private var currentBackgroundColor: Color {
        if isHolding {
            return holdBackgroundColor
        } else if isExternallyPressed {
            return externalPressBackgroundColor
        }
        return backgroundColor
    }

    private var currentBorderColor: Color {
        if isHolding {
            return Color.orange
        } else if isExternallyPressed {
            return Color.accentColor
        }
        return borderColor
    }

    private var currentBorderWidth: CGFloat {
        (isHolding || isExternallyPressed) ? 2 : 1.5
    }

    private var backgroundColor: Color {
        if isDark {
            if isPressed {
                return Color(white: 0.35)
            } else if isHovered {
                return Color(white: 0.32)
            }
            return Color(white: 0.28)
        } else {
            if isPressed {
                return Color(white: 0.78)
            } else if isHovered {
                return Color(white: 0.82)
            }
            return Color(white: 0.88)
        }
    }

    private var holdBackgroundColor: Color {
        Color.orange.opacity(isDark ? 0.4 : 0.3)
    }

    private var externalPressBackgroundColor: Color {
        Color.accentColor.opacity(isDark ? 0.4 : 0.3)
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
        showAsPressed ? .clear : .black.opacity(isDark ? 0.3 : 0.15)
    }

    private var shadowRadius: CGFloat {
        showAsPressed ? 0 : 2
    }

    private var shadowOffset: CGFloat {
        showAsPressed ? 0 : 2
    }
}

// MARK: - Preview

#Preview("Regular Key") {
    SimulatorKeycapView(
        key: PhysicalKey(keyCode: 0, label: "A", x: 0, y: 0),
        isExternallyPressed: false,
        onTap: {},
        onHold: {}
    )
    .frame(width: 40, height: 40)
    .padding()
}

#Preview("Externally Pressed") {
    SimulatorKeycapView(
        key: PhysicalKey(keyCode: 0, label: "A", x: 0, y: 0),
        isExternallyPressed: true,
        onTap: {},
        onHold: {}
    )
    .frame(width: 40, height: 40)
    .padding()
}

#Preview("Wide Key") {
    SimulatorKeycapView(
        key: PhysicalKey(keyCode: 48, label: "Tab", x: 0, y: 0, width: 1.5),
        isExternallyPressed: false,
        onTap: {},
        onHold: {}
    )
    .frame(width: 60, height: 40)
    .padding()
}
