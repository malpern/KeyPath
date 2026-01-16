import SwiftUI

/// Observable state for tracking which keys in the hide shortcut are pressed
@MainActor
final class HideShortcutKeyState: ObservableObject {
    @Published var commandPressed = false
    @Published var optionPressed = false
    @Published var kPressed = false
    @Published var allPressedPulse = false

    /// Check if all keys are pressed and trigger pulse if so
    func checkAllPressed() {
        if commandPressed, optionPressed, kPressed, !allPressedPulse {
            allPressedPulse = true
        }
    }

    /// Reset all states
    func reset() {
        commandPressed = false
        optionPressed = false
        kPressed = false
        allPressedPulse = false
    }
}

/// A hint bubble that teaches users how to hide the overlay using the keyboard shortcut.
/// Shows "Hide - ⌘⌥K" with visual key chips and auto-dismisses after 10 seconds.
/// The key chips respond to actual key presses for visual feedback.
struct HideHintBubble: View {
    /// Whether the bubble should be visible
    @Binding var isVisible: Bool
    /// Key press state for visual feedback
    @ObservedObject var keyState: HideShortcutKeyState
    /// Auto-dismiss timer task
    @State private var dismissTask: Task<Void, Never>?

    /// Bubble background color
    private static let bubbleBackground = Color(white: 0.08, opacity: 0.95)

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Main bubble content
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                // Hide label with icon
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11, weight: .medium))
                    Text("Hide")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)

                // Separator
                Text("—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.4))

                // Key chips for ⌘⌥K - respond to actual key presses
                HStack(spacing: 3) {
                    ModifierKeyChip(
                        symbol: "⌘",
                        isPressed: keyState.commandPressed,
                        isPulsing: keyState.allPressedPulse
                    )
                    ModifierKeyChip(
                        symbol: "⌥",
                        isPressed: keyState.optionPressed,
                        isPulsing: keyState.allPressedPulse
                    )
                    ModifierKeyChip(
                        symbol: "K",
                        isPressed: keyState.kPressed,
                        isPulsing: keyState.allPressedPulse
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Self.bubbleBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            // Caret pointing down toward the hide button (right-aligned)
            HStack {
                Spacer()
                DownCaretShape()
                    .fill(Self.bubbleBackground)
                    .frame(width: 12, height: 6)
                    .padding(.trailing, 12) // Align with hide button
            }
        }
        .onAppear {
            startDismissTimer()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func startDismissTimer() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = false
            }
        }
    }
}

/// A modifier key chip with bright blue styling that responds to press state
private struct ModifierKeyChip: View {
    let symbol: String
    var isPressed: Bool = false
    var isPulsing: Bool = false

    /// Normal bright blue color
    private static let normalTextColor = Color(red: 0.4, green: 0.8, blue: 1.0)
    /// Normal dark blue background
    private static let normalBackgroundColor = Color(red: 0.1, green: 0.28, blue: 0.45)

    /// Pressed/active bright color (more vibrant)
    private static let pressedTextColor = Color(red: 0.6, green: 0.95, blue: 1.0)
    /// Pressed/active background (brighter)
    private static let pressedBackgroundColor = Color(red: 0.15, green: 0.45, blue: 0.7)

    /// Pulse glow color
    private static let pulseGlowColor = Color(red: 0.4, green: 0.8, blue: 1.0)

    private var textColor: Color {
        isPressed ? Self.pressedTextColor : Self.normalTextColor
    }

    private var backgroundColor: Color {
        isPressed ? Self.pressedBackgroundColor : Self.normalBackgroundColor
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(textColor)
            .frame(minWidth: 18)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(textColor.opacity(isPressed ? 0.6 : 0.3), lineWidth: isPressed ? 1 : 0.5)
            )
            .shadow(color: isPulsing ? Self.pulseGlowColor.opacity(0.8) : .clear, radius: isPulsing ? 8 : 0)
            .scaleEffect(isPressed ? 1.1 : 1.0)
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isPulsing)
    }
}

/// A small caret/arrow shape pointing down toward the hide button
private struct DownCaretShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview("Hide Hint Bubble") {
    ZStack {
        Color.black.opacity(0.8)

        VStack(spacing: 4) {
            // Simulated header with hide button
            HStack {
                Spacer()
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    )
            }
            .padding(.horizontal, 8)

            HideHintBubble(isVisible: .constant(true), keyState: HideShortcutKeyState())
                .padding(.trailing, 8)

            Spacer()
        }
        .padding(.top, 8)
    }
    .frame(width: 500, height: 200)
}
