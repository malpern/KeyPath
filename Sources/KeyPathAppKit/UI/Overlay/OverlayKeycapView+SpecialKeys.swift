import AppKit
import KeyPathCore
import SwiftUI

extension OverlayKeycapView {
    // MARK: - Novelty Keys

    var hasNoveltyKey: Bool {
        colorway.noveltyConfig.noveltyForKey(label: key.label) != nil
    }

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

    // MARK: - App Launch (shows app icon)

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

    // MARK: - URL Mapping (shows favicon)

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

    // MARK: - System Action (shows SF Symbol icon)

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

    // MARK: - Narrow Modifier (fn, ctrl, opt, cmd)

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

    // MARK: - Function Key

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
        let isRemappedToRegularKey = remappedLabel != nil && !hasSystemRemapping && remappedLabel != key.label

        if isRemappedToRegularKey {
            Text(remappedLabel!.uppercased())
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let sfSymbol: String? = {
                if let info = layerKeyInfo,
                   let outputSymbol = LabelMetadata.sfSymbol(forOutputLabel: info.displayLabel)
                {
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

    // MARK: - Arrow

    var arrowContent: some View {
        Text(effectiveLabel)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Touch ID / Layer Indicator

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

    // MARK: - Layer Key

    @ViewBuilder
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

    // MARK: - ESC Key

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

    // MARK: - Caps Lock Indicator

    var capsLockIndicator: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isCapsLockOn ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 4 * scale, height: 4 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(1.0) : .clear, radius: 2 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(0.8) : .clear, radius: 4 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(0.5) : .clear, radius: 8 * scale)
                    .animation(.easeInOut(duration: 0.2), value: isCapsLockOn)
                Spacer()
            }
            .padding(.leading, 4.4 * scale)
            .padding(.top, 3 * scale)
            Spacer()
        }
    }
}
