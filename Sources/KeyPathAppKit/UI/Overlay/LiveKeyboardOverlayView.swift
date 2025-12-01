import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel

    @Environment(\.colorScheme) private var colorScheme

    /// Constants matching OverlayKeyboardView for scale calculation
    private let keyUnitSize: CGFloat = 32
    private let keyGap: CGFloat = 2
    private let layout = PhysicalLayout.macBookUS

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)
            let cornerRadius = 10 * scale // Larger than keys for harmonious container feel

            // Main keyboard with directional shadow (light from above)
            OverlayKeyboardView(
                layout: .macBookUS,
                pressedKeyCodes: viewModel.pressedKeyCodes,
                isDarkMode: isDark
            )
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isDark
                        ? Color(red: 0.11, green: 0.11, blue: 0.13)
                        : Color(red: 0.78, green: 0.80, blue: 0.83))
                    // Apple-style floating shadow: subtle wrap, stronger below
                    // 1. Ambient shadow - very soft, wraps gently, pushed down
                    .shadow(color: .black.opacity(isDark ? 0.25 : 0.12), radius: 12, x: 0, y: 8)
                    // 2. Contact shadow - tighter, grounds the element
                    .shadow(color: .black.opacity(isDark ? 0.15 : 0.08), radius: 3, x: 0, y: 2)
            )
            // Padding for shadow to fade naturally (asymmetric - more below)
            .padding(.bottom, 25)
            .padding(.horizontal, 15)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Styling

    private var isDark: Bool { colorScheme == .dark }

    /// Calculate scale to match OverlayKeyboardView's scale calculation
    private func calculateScale(for size: CGSize) -> CGFloat {
        // Account for padding (10pt on each side)
        let contentSize = CGSize(width: size.width - 20, height: size.height - 20)
        let widthScale = contentSize.width / (layout.totalWidth * (keyUnitSize + keyGap))
        let heightScale = contentSize.height / (layout.totalHeight * (keyUnitSize + keyGap))
        return min(widthScale, heightScale)
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
