import KeyPathCore
import SwiftUI

extension OverlayKeycapView {
    /// Renders a colored dot/circle instead of text legend (GMK Dots style)
    @ViewBuilder
    var dotsLegendContent: some View {
        let config = colorway.dotsConfig ?? .default

        if key.layoutRole == .functionKey {
            functionKeyWithMappingContent
        } else if key.layoutRole == .touchId {
            touchIdContent
        } else if key.layoutRole == .arrow {
            dotShape(config: config, isModifier: false, sizeMultiplier: 0.7)
        } else if isModifierKey || key.layoutRole == .bottomAligned || key.layoutRole == .narrowModifier {
            oblongShape(config: config)
        } else if key.layoutRole == .escKey {
            dotShape(config: config, isModifier: false, sizeMultiplier: 0.8)
        } else {
            dotShape(config: config, isModifier: false, sizeMultiplier: 1.0)
        }
    }

    /// Circular dot for alpha keys
    @ViewBuilder
    func dotShape(config: DotsLegendConfig, isModifier _: Bool, sizeMultiplier: CGFloat) -> some View {
        let baseSize: CGFloat = 36 * scale * config.dotSize * sizeMultiplier
        let color = dotColorForCurrentKey(config: config)

        Circle()
            .fill(color)
            .frame(width: baseSize, height: baseSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Oblong/bar shape for modifier keys
    @ViewBuilder
    func oblongShape(config: DotsLegendConfig) -> some View {
        let height: CGFloat = 4 * scale
        let width: CGFloat = height * config.oblongWidthMultiplier
        let color = dotColorForCurrentKey(config: config)

        RoundedRectangle(cornerRadius: height / 2)
            .fill(color)
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Calculate dot color based on key position and config
    func dotColorForCurrentKey(config: DotsLegendConfig) -> Color {
        let fallbackColor = isModifierKey ? colorway.modLegendColor : colorway.alphaLegendColor
        return config.dotColor(forColumn: Int(key.x), totalColumns: Int(layoutTotalWidth), fallbackColor: fallbackColor)
    }
}
