import AppKit
import SwiftUI

// MARK: - Layout-Specific Content (modifiers, function keys, arrows, etc.)

extension BaseKeycap {
    // MARK: - Bottom Aligned (wide modifiers)

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
                if let tapHoldLabel = tapHoldIdleLabel {
                    let tapMetadata = LabelMetadata.forLabel(tapHoldLabel)
                    return tapMetadata.wordLabel ?? tapHoldLabel
                }
                if isRemappedKey, let remapLabel = metadata.wordLabel {
                    return remapLabel
                }
                if currentLayerName.lowercased() != "base" {
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

    // MARK: - Label Text Helper

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

    // MARK: - Novelty Key Content

    @ViewBuilder
    var noveltyKeyContent: some View {
        if let noveltyChar = colorway.noveltyConfig.noveltyForKey(label: key.label) {
            let noveltyColor = colorway.noveltyConfig.useAccentColor
                ? colorway.accentLegendColor
                : foregroundColor
            Text(noveltyChar)
                .font(.system(size: 16 * scale, weight: .medium))
                .foregroundStyle(noveltyColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - App Launch Content

    @ViewBuilder
    var appLaunchContent: some View {
        if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4 * scale)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14 * scale, weight: .light))
                .foregroundStyle(foregroundColor.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - URL Mapping Content

    @ViewBuilder
    var urlMappingContent: some View {
        if let favicon = faviconImage {
            Image(nsImage: favicon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4 * scale)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14 * scale, weight: .light))
                .foregroundStyle(foregroundColor.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - System Action Content

    @ViewBuilder
    var systemActionContent: some View {
        if let iconName = systemActionIcon {
            Image(systemName: iconName)
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(effectiveLabel)
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Narrow Modifier Content

    @ViewBuilder
    var narrowModifierContent: some View {
        if key.label == "fn" {
            fnKeyContent
        } else {
            modifierSymbolContent
        }
    }

    @ViewBuilder
    var fnKeyContent: some View {
        let canInline = scale >= 1.0

        Group {
            if canInline {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "globe")
                        .font(.system(size: 8.5 * scale, weight: .regular))
                    Text("fn")
                        .font(.system(size: 7 * scale, weight: .regular))
                }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 8.5 * scale, weight: .regular))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
    }

    @ViewBuilder
    var modifierSymbolContent: some View {
        let baseFontSize: CGFloat = 11 * scale
        let fontSize = baseFontSize * adjustments.fontScale
        let offset = adjustments.verticalOffset * scale

        Text(key.label)
            .font(.system(size: fontSize, weight: .light))
            .offset(y: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foregroundColor)
    }

    // MARK: - Function Key Content

    @ViewBuilder
    var functionKeyWithMappingContent: some View {
        let iconName: String? = if hasSystemAction, let sysIcon = systemActionIcon {
            sysIcon
        } else {
            LabelMetadata.sfSymbol(forKeyCode: key.keyCode)
        }

        VStack(spacing: 0) {
            if let icon = iconName {
                Image(systemName: icon)
                    .font(.system(size: 8 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
            }
            Spacer()
            Text(key.label)
                .font(.system(size: 5.4 * scale, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .padding(.top, 4 * scale)
        .padding(.bottom, 2 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var functionKeyContent: some View {
        let remappedLabel = layerKeyInfo?.displayLabel
        let sfSymbolResult = remappedLabel.flatMap { LabelMetadata.sfSymbol(forOutputLabel: $0) }
        let hasSystemRemapping = sfSymbolResult != nil
        let isRemappedToRegularKey = remappedLabel != nil && !hasSystemRemapping
            && remappedLabel != key.label

        if isRemappedToRegularKey, let label = remappedLabel {
            Text(label.uppercased())
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let sfSymbol: String? = {
                if let info = layerKeyInfo,
                   let outputSymbol = LabelMetadata.sfSymbol(forOutputLabel: info.displayLabel) {
                    return outputSymbol
                }
                return LabelMetadata.sfSymbol(forKeyCode: key.keyCode)
            }()

            VStack(spacing: 0) {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 8 * scale, weight: .regular))
                        .foregroundStyle(foregroundColor)
                }
                Spacer()
                Text(key.label)
                    .font(.system(size: 5.4 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor.opacity(0.6))
            }
            .padding(.top, 4 * scale)
            .padding(.bottom, 2 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Arrow Content

    var arrowContent: some View {
        Text(effectiveLabel)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Touch ID Content

    @ViewBuilder
    var touchIdContent: some View {
        if isLoadingLayerMap {
            Circle()
                .fill(foregroundColor.opacity(0.6))
                .frame(width: 4 * scale, height: 4 * scale)
                .modifier(PulseAnimation())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "sidebar.right")
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layer Key Content

    func layerKeyContent(label: String) -> some View {
        VStack(spacing: 1 * scale) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 10 * scale, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.7))
            Text(label)
                .font(.system(size: 7 * scale, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - ESC Key Content

    var escKeyContent: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                labelText("esc", isHoldLabel: false)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4 * scale)
            .padding(.trailing, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
    }

    // MARK: - Multi-Legend Content (JIS/ISO)

    var multiLegendContent: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 3 * scale
            let subFontSize: CGFloat = 7 * scale

            if key.shiftLabel != nil {
                let mainFontSize: CGFloat = 10 * scale
                let shiftFontSize: CGFloat = 8 * scale

                ZStack {
                    if let shiftLabel = key.shiftLabel {
                        Text(shiftLabel)
                            .font(.system(size: shiftFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.7))
                            .position(
                                x: padding + shiftFontSize / 2,
                                y: padding + shiftFontSize / 2
                            )
                    }

                    if let tertiaryLabel = key.tertiaryLabel {
                        Text(tertiaryLabel)
                            .font(.system(size: subFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.5))
                            .position(
                                x: geometry.size.width - padding - subFontSize / 2,
                                y: padding + subFontSize / 2
                            )
                    }

                    Text(key.label)
                        .font(.system(size: mainFontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .position(
                            x: padding + mainFontSize / 2,
                            y: geometry.size.height - padding - mainFontSize / 2
                        )

                    if let subLabel = key.subLabel {
                        Text(subLabel)
                            .font(.system(size: subFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.6))
                            .position(
                                x: geometry.size.width - padding - subFontSize / 2,
                                y: geometry.size.height - padding - subFontSize / 2
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                let mainFontSize: CGFloat = 14 * scale

                ZStack {
                    Text(key.label.uppercased())
                        .font(.system(size: mainFontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let subLabel = key.subLabel {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(subLabel)
                                    .font(.system(size: subFontSize, weight: .regular))
                                    .foregroundStyle(foregroundColor.opacity(0.5))
                                    .padding(.trailing, padding)
                                    .padding(.bottom, padding)
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    // MARK: - Inline Layer Mapped Content

    @ViewBuilder
    func inlineLayerMappedContent(info: LayerKeyInfo) -> some View {
        let arrowLabels: Set = ["\u{2190}", "\u{2192}", "\u{2191}", "\u{2193}"]
        let labelColor = Color.white.opacity(0.85)
        if arrowLabels.contains(info.displayLabel) {
            Text(info.displayLabel)
                .font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Text(info.displayLabel.lowercased())
                        .font(.system(size: 9 * scale, weight: .medium))
                        .foregroundStyle(labelColor)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 4 * scale)
                .padding(.bottom, 3 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
