import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Main keyboard
            OverlayKeyboardView(
                layout: .macBookUS,
                pressedKeyCodes: viewModel.pressedKeyCodes,
                isDarkMode: isDark
            )
            .padding(10)
            .background(windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: shadowColor, radius: isDark ? 20 : 15, y: 8)

            // Resize handles (visible on hover)
            if isHovering {
                ResizeHandles(isDark: isDark)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.openHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }

    // MARK: - Styling

    private var isDark: Bool { colorScheme == .dark }

    private var windowBackground: some View {
        Group {
            if isDark {
                // Dark mode: darker aluminum, like Space Gray MacBook
                Color(red: 0.11, green: 0.11, blue: 0.13)
            } else {
                // Light mode: Silver aluminum
                Color(red: 0.78, green: 0.80, blue: 0.83)
            }
        }
    }

    private var shadowColor: Color {
        isDark ? .black.opacity(0.6) : .black.opacity(0.35)
    }
}

// MARK: - Resize Handles

/// Visual resize handles at corners
private struct ResizeHandles: View {
    let isDark: Bool

    var body: some View {
        GeometryReader { geo in
            let handleSize: CGFloat = 12
            let handleColor = isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)

            // Corner handles
            ForEach(corners, id: \.self) { corner in
                RoundedRectangle(cornerRadius: 2)
                    .fill(handleColor)
                    .frame(width: handleSize, height: handleSize)
                    .position(position(for: corner, in: geo.size, handleSize: handleSize))
            }
        }
    }

    private var corners: [UnitPoint] {
        [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
    }

    private func position(for corner: UnitPoint, in size: CGSize, handleSize: CGFloat) -> CGPoint {
        let inset: CGFloat = 4
        switch corner {
        case .topLeading:
            return CGPoint(x: inset + handleSize / 2, y: inset + handleSize / 2)
        case .topTrailing:
            return CGPoint(x: size.width - inset - handleSize / 2, y: inset + handleSize / 2)
        case .bottomLeading:
            return CGPoint(x: inset + handleSize / 2, y: size.height - inset - handleSize / 2)
        case .bottomTrailing:
            return CGPoint(x: size.width - inset - handleSize / 2, y: size.height - inset - handleSize / 2)
        default:
            return .zero
        }
    }
}

// MARK: - Preview

#Preview("Keys Pressed") {
    LiveKeyboardOverlayView(
        viewModel: {
            let vm = KeyboardVisualizationViewModel()
            vm.pressedKeyCodes = [0, 56, 55] // a, leftshift, leftmeta
            return vm
        }()
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

#Preview("No Keys") {
    LiveKeyboardOverlayView(
        viewModel: KeyboardVisualizationViewModel()
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}
