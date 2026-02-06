import SwiftUI

// MARK: - Create Rule Button

struct CreateRuleButton: View {
    @Binding var isPressed: Bool
    @Binding var externalHover: Bool
    @State private var isHovered = false
    @State private var isMouseDown = false

    private var isAnyHovered: Bool {
        isHovered || externalHover
    }

    var body: some View {
        Button {
            isPressed = true
        } label: {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(iconColor)
            }
            .scaleEffect(isMouseDown ? 0.95 : (isAnyHovered ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isAnyHovered)
            .animation(.easeInOut(duration: 0.1), value: isMouseDown)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isMouseDown = true
                }
                .onEnded { _ in
                    isMouseDown = false
                }
        )
    }

    private var fillColor: Color {
        if isMouseDown {
            Color.blue.opacity(0.3)
        } else if isAnyHovered {
            Color.blue.opacity(0.25)
        } else {
            Color.blue.opacity(0.15)
        }
    }

    private var iconColor: Color {
        if isMouseDown {
            .blue.opacity(0.8)
        } else if isAnyHovered {
            .blue
        } else {
            .blue.opacity(0.9)
        }
    }

    private var shadowColor: Color {
        if isMouseDown {
            .clear
        } else if isAnyHovered {
            Color.blue.opacity(0.3)
        } else {
            .clear
        }
    }

    private var shadowRadius: CGFloat {
        isAnyHovered ? 8 : 0
    }

    private var shadowY: CGFloat {
        isAnyHovered ? 2 : 0
    }
}
