import SwiftUI

// MARK: - Tap-Hold Mini Keycap

/// Small keycap for tap-hold configuration in the customize panel
struct TapHoldMiniKeycap: View {
    let label: String
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let size: CGFloat = 48
    private let cornerRadius: CGFloat = 8
    private let fontSize: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            if isRecording {
                Text("...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.7, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.4))
            } else {
                Text(label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var foregroundColor: Color {
        isDark
            ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(isPressed ? 1.0 : 0.88)
            : Color.primary.opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            Color.accentColor
        } else if isHovered {
            if isDark {
                Color(white: 0.18)
            } else {
                Color(white: 0.92)
            }
        } else {
            if isDark {
                Color(white: 0.12)
            } else {
                Color(white: 0.96)
            }
        }
    }

    private var borderColor: Color {
        if isRecording {
            Color.accentColor.opacity(0.8)
        } else if isHovered {
            if isDark {
                Color.white.opacity(0.3)
            } else {
                Color.black.opacity(0.15)
            }
        } else {
            if isDark {
                Color.white.opacity(0.15)
            } else {
                Color.black.opacity(0.1)
            }
        }
    }

    private var shadowColor: Color {
        isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 1 : 2
    }
}
