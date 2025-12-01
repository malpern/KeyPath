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

            // Main keyboard
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
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: shadowColor, radius: isDark ? 20 : 15, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Styling

    private var isDark: Bool { colorScheme == .dark }

    private var shadowColor: Color {
        isDark ? .black.opacity(0.6) : .black.opacity(0.35)
    }

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
