import SwiftUI
import AppKit

// MARK: - Liquid Glass View Modifier
struct LiquidGlassEffect: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let intensity: Double
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base glass layer with dynamic material
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.regularMaterial)

                    // Gradient overlay for depth
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15),
                            Color.clear,
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(colorScheme == .dark ? .plusLighter : .overlay)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                    // Inner glow for glass effect
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - Liquid Glass Container
struct LiquidGlassContainer<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let intensity: Double

    init(
        cornerRadius: CGFloat = 20,
        intensity: Double = 0.8,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.intensity = intensity
        self.content = content()
    }

    var body: some View {
        content
            .modifier(LiquidGlassEffect(
                intensity: intensity,
                cornerRadius: cornerRadius
            ))
    }
}

// MARK: - Liquid Glass Button Style
struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Dynamic glass material
                    Capsule()
                        .fill(.thinMaterial)

                    // Gradient overlay
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(configuration.isPressed ? 0.3 : 0.2),
                            Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.overlay)
                    .clipShape(Capsule())
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: configuration.isPressed ?
                                [Color.clear, Color.clear] :
                                [Color.white.opacity(0.4), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Liquid Glass Alert Style
struct LiquidGlassAlertStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(24)
            .background(
                ZStack {
                    // Ultra thin material for alerts
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)

                    // Subtle gradient
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 15)
    }
}

// MARK: - View Extensions
extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        intensity: Double = 0.8
    ) -> some View {
        self.modifier(LiquidGlassEffect(
            intensity: intensity,
            cornerRadius: cornerRadius
        ))
    }

    func liquidGlassAlert() -> some View {
        self.modifier(LiquidGlassAlertStyle())
    }
}

// MARK: - Liquid Glass Text Field
struct LiquidGlassTextField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .padding()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? .thickMaterial : .regularMaterial)

                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            Color.accentColor.opacity(isFocused ? 0.5 : 0),
                            lineWidth: 2
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: isFocused ?
                                [Color.white.opacity(0.5), Color.clear] :
                                [Color.clear, Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .focused($isFocused)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}

// MARK: - Liquid Glass Progress View
struct LiquidGlassProgressView: View {
    let progress: Double
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(height: 8)

                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.7)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedProgress, height: 8)
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = newValue
            }
        }
    }
}
