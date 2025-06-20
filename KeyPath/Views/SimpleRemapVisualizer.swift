import SwiftUI

struct SimpleRemapVisualizer: View {
    let visualization: RemapVisualization
    @State private var animateArrow = false

    var body: some View {
        HStack(spacing: 32) {
            KeycapView(label: visualization.from, isSource: true)

            ZStack {
                // Arrow with animation
                Image(systemName: "arrow.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.secondary, .accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: animateArrow ? 5 : -5)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: animateArrow
                    )
            }

            KeycapView(label: visualization.toKey, isSource: false)
        }
        .padding(.vertical, 20)
        .onAppear {
            animateArrow = true
        }
    }
}

struct KeycapView: View {
    let label: String
    let isSource: Bool

    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme

    private var keyColor: Color {
        if isSource {
            return colorScheme == .dark ?
                Color(red: 0.3, green: 0.3, blue: 0.3) :
                Color(red: 0.5, green: 0.5, blue: 0.5)
        } else {
            // Use a more vibrant color for destination with better contrast
            return colorScheme == .dark ?
                Color.accentColor :
                Color.accentColor.opacity(0.9)
        }
    }

    private var labelColor: Color {
        if isSource {
            return .white
        } else {
            // For destination keys, use high contrast color
            return colorScheme == .dark ? .white : .white
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Key cap
            ZStack {
                // Shadow layer
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: isPressed ? 1 : 4)

                // Main key
                RoundedRectangle(cornerRadius: 12)
                    .fill(keyColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        keyColor.opacity(0.6),
                                        keyColor.opacity(0.2)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )

                // Highlight
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(2)

                // Label
                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
            .frame(width: max(80, CGFloat(label.count * 12 + 40)), height: 50)
            .offset(y: isPressed ? 2 : 0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        SimpleRemapVisualizer(
            visualization: RemapVisualization(
                from: "Caps Lock",
                toKey: "Escape"
            )
        )

        SimpleRemapVisualizer(
            visualization: RemapVisualization(
                from: "Right Cmd",
                toKey: "Enter"
            )
        )

        SimpleRemapVisualizer(
            visualization: RemapVisualization(
                from: "F1",
                toKey: "Volume Down"
            )
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color(NSColor.windowBackgroundColor))
}
