import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Layout-Specific Content Rendering

extension OverlayKeycapView {
    // MARK: - Layout: Centered (letters, symbols, spacebar)

    @ViewBuilder
    var centeredContent: some View {
        if useFloatingLabels, !hasSpecialLabel, !isRemappedKey {
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

    // MARK: - Vim Nav Overlay (arrow + letter)

    var navOverlaySymbol: String? {
        guard key.layoutRole == .centered, let info = layerKeyInfo else { return nil }
        let arrowLabels: Set<String> = ["←", "→", "↑", "↓"]
        if arrowLabels.contains(info.displayLabel) {
            return info.displayLabel
        }
        return nil
    }

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

    func dualSymbolSpacing(for label: String) -> CGFloat {
        switch label {
        case ",", ".": -0.5 * scale
        case ";", "'", "/": 0
        default: 2 * scale
        }
    }

    // MARK: - Layout: Bottom Aligned (wide modifiers)

    @ViewBuilder
    var bottomAlignedContent: some View {
        if useFloatingLabels, !hasSpecialLabel, !isRemappedKey {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let physicalMetadata = LabelMetadata.forLabel(key.label)
            let useSymbols = PreferencesService.shared.keyLabelStyle == .symbols
            let wordLabel: String = {
                if let holdLabel {
                    return holdLabel
                }
                if currentLayerName.lowercased() == "nav" {
                    return physicalMetadata.wordLabel ?? key.label
                }
                if useSymbols {
                    return metadata.wordLabel ?? key.label
                }
                return metadata.wordLabel ?? physicalMetadata.wordLabel ?? key.label
            }()
            let isRight = key.isRightSideKey
            let isHold = holdLabel != nil

            VStack {
                Spacer(minLength: 0)
                HStack {
                    if !isRight {
                        labelText(wordLabel, isHoldLabel: isHold)
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        labelText(wordLabel, isHoldLabel: isHold)
                    }
                }
                .padding(.leading, 4 * scale)
                .padding(.trailing, 4 * scale)
                .padding(.bottom, 3 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foregroundColor)
        }
    }

    @ViewBuilder
    func labelText(_ text: String, isHoldLabel: Bool) -> some View {
        if isHoldLabel {
            Text(text)
                .font(.system(size: 12 * scale, weight: .semibold))
        } else if isSmallSize {
            Text(text)
                .font(.system(size: 10 * scale, weight: .regular))
        } else {
            Text(text)
                .font(.system(size: 7 * scale, weight: .regular))
        }
    }
}
