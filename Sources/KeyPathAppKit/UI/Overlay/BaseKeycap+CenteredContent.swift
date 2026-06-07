import SwiftUI

// MARK: - Centered Content (letters, symbols, spacebar)

extension BaseKeycap {
    @ViewBuilder
    var centeredContent: some View {
        let hasActiveSubtitle = zoneSubtitle != nil && !isLayerMode && !isLauncherMode
        if useFloatingLabels, !hasSpecialLabel, !isRemappedKey, !hasActiveSubtitle {
            if let navSymbol = navOverlaySymbol {
                navOverlayArrowOnly(arrow: navSymbol)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            if let sfSymbol = navigationSFSymbol {
                Image(systemName: sfSymbol)
                    .font(.system(size: 10 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let wordLabel = navigationWordLabel {
                navigationWordContent(wordLabel)
            } else if key.label == "Fn" {
                fnKeyContent
            } else if let navSymbol = navOverlaySymbol {
                navOverlayContent(arrow: navSymbol, letter: baseLabel)
            } else if let subtitle = zoneSubtitle, !isLayerMode, !isLauncherMode, zoneSubtitleRenderedInline {
                inlineSubtitleContent(primary: effectiveLabel, subtitle: subtitle)
            } else if let shiftSymbol = metadata.shiftSymbol, !isNumpadKey {
                dualSymbolContent(main: effectiveLabel, shift: shiftSymbol)
            } else if let sfSymbol = LabelMetadata.sfSymbol(forOutputLabel: effectiveLabel) {
                Image(systemName: sfSymbol)
                    .font(.system(size: 14 * scale, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if PhysicalLayout.isLayerKeyLabel(key.label) {
                layerKeyContent(label: key.label)
            } else {
                let displayText = effectiveLabel.isEmpty ? key.label : effectiveLabel
                Text(isNumpadKey ? displayText : displayText.uppercased())
                    .font(.system(size: isNumpadKey ? 14 * scale : 12 * scale, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func inlineSubtitleContent(primary: String, subtitle: String) -> some View {
        let displayText = primary.isEmpty ? key.label : primary
        let adj = OpticalAdjustments.forLabel(displayText)
        return VStack(spacing: dualSymbolSpacing(for: displayText)) {
            Text(displayText.uppercased())
                .font(.system(
                    size: 12.5 * scale * adj.fontScale,
                    weight: adj.fontWeight ?? .medium
                ))
                .offset(y: adj.verticalOffset * scale)
                .foregroundStyle(foregroundColor)
            Text(subtitle)
                .font(.system(size: 8.5 * scale, weight: .light))
                .foregroundStyle(foregroundColor.opacity(isSmallSize ? 0 : 0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation Word Content

    func navigationWordContent(_ label: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                if label.lowercased() == "print screen" {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("print")
                            .font(.system(size: 7 * scale, weight: .regular))
                            .foregroundStyle(foregroundColor)
                        Text("screen")
                            .font(.system(size: 7 * scale, weight: .regular))
                            .foregroundStyle(foregroundColor)
                    }
                } else {
                    Text(label)
                        .font(.system(size: 7 * scale, weight: .regular))
                        .foregroundStyle(foregroundColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4 * scale)
            .padding(.trailing, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dual Symbol Content

    @ViewBuilder
    func dualSymbolContent(main: String, shift: String) -> some View {
        let shiftAdj = OpticalAdjustments.forLabel(shift)
        let mainAdj = OpticalAdjustments.forLabel(main)

        VStack(spacing: dualSymbolSpacing(for: main)) {
            Text(shift)
                .font(.system(
                    size: 8.5 * scale * shiftAdj.fontScale,
                    weight: .light
                ))
                .foregroundStyle(foregroundColor.opacity(isSmallSize ? 0 : 0.65))

            Text(main)
                .font(.system(
                    size: 12.5 * scale * mainAdj.fontScale,
                    weight: mainAdj.fontWeight ?? .medium
                ))
                .offset(y: mainAdj.verticalOffset * scale)
                .foregroundStyle(foregroundColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Nav Overlay Content

    func navOverlayContent(arrow: String, letter: String) -> some View {
        VStack(spacing: 6 * scale) {
            Text(arrow)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isPressed ? 1.0 : 0.9))
                .shadow(color: Color.black.opacity(0.25), radius: 1.5 * scale, y: 1 * scale)
            Text(letter.uppercased())
                .font(.system(size: 9.5 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(isPressed ? 0.8 : 0.65))
        }
        .padding(.top, 4 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func navOverlayArrowOnly(arrow: String) -> some View {
        Text(arrow)
            .font(.system(size: 14 * scale, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isPressed ? 1.0 : 0.9))
            .shadow(color: Color.black.opacity(0.25), radius: 1.5 * scale, y: 1 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Spacing Helper

    func dualSymbolSpacing(for label: String) -> CGFloat {
        switch label {
        case ",", ".": -0.5 * scale
        case ";", "'", "/": 0
        default: 2 * scale
        }
    }
}
