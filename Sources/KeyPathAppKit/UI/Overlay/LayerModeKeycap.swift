import AppKit
import KeyPathCore
import SwiftUI

struct LayerModeKeycap: View {
    let key: PhysicalKey
    let baseLabel: String
    let holdLabel: String?
    let scale: CGFloat
    let currentLayerName: String
    let layerKeyInfo: LayerKeyInfo?
    let customIcon: String?
    let zoneSubtitle: String?
    let foregroundColor: Color
    let appIcon: NSImage?
    let faviconImage: NSImage?
    let systemActionIcon: String?
    let hasLayerMapping: Bool
    let isNavIdentityMapping: Bool

    private var keyLabel: String {
        if key.keyCode == 57 { return "✦" }
        return holdLabel ?? baseLabel
    }

    private var isArrowKey: Bool {
        key.layoutRole == .arrow
    }

    var body: some View {
        if isNavIdentityMapping {
            navIdentityContent
        } else if hasLayerMapping || zoneSubtitle != nil {
            if key.label == "fn" {
                fnKeyFallback
            } else if let subtitle = zoneSubtitle, !hasLayerMapping {
                ZStack(alignment: .topLeading) {
                    if !isArrowKey {
                        topLeftLabel(opacity: 0.25)
                    }
                    zoneSubtitleIcon(subtitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                let useWindowSymbol = currentLayerName.lowercased().contains("window")
                let windowSymbol = useWindowSymbol
                    ? KeycapSymbols.windowActionSymbol(from: layerKeyInfo?.displayLabel ?? "", layerName: currentLayerName)
                    : nil

                if let symbol = windowSymbol {
                    ZStack(alignment: .topLeading) {
                        Image(systemName: symbol)
                            .font(.system(size: 16 * scale, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !isArrowKey {
                            topLeftLabel(opacity: 0.7)
                        }
                    }
                } else {
                    let arrowLabels: Set = ["←", "→", "↑", "↓"]
                    let isArrowAction = arrowLabels.contains(layerKeyInfo?.vimLabel ?? "")
                        || arrowLabels.contains(layerKeyInfo?.displayLabel ?? "")
                    let hasActionSymbol = KeycapSymbols.sfSymbolForAction(layerKeyInfo?.displayLabel ?? "") != nil
                        || LabelMetadata.sfSymbol(forOutputLabel: layerKeyInfo?.displayLabel ?? "") != nil

                    ZStack(alignment: .topLeading) {
                        if !isArrowKey, !isArrowAction {
                            topLeftLabel(opacity: hasActionSymbol ? 0.25 : 0.7)
                        }

                        actionContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        } else {
            unmappedContent
        }
    }

    // MARK: - Sub-views

    private var navIdentityContent: some View {
        Text(baseLabel.uppercased())
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topLeftLabel(opacity: Double) -> some View {
        Text(keyLabel.uppercased())
            .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(opacity))
            .padding(3 * scale)
    }

    @ViewBuilder
    private var actionContent: some View {
        if let iconName = customIcon {
            Image(systemName: iconName)
                .font(.system(size: 18 * scale, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.9))
        } else if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18 * scale, height: 18 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))
        } else if let favicon = faviconImage {
            Image(nsImage: favicon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18 * scale, height: 18 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))
        } else if let iconName = systemActionIcon {
            Image(systemName: iconName)
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        } else if let info = layerKeyInfo {
            let arrowLabels: Set = ["←", "→", "↑", "↓"]
            if arrowLabels.contains(info.displayLabel) || arrowLabels.contains(info.vimLabel ?? "") {
                let arrow = arrowLabels.contains(info.displayLabel) ? info.displayLabel : info.vimLabel!
                Text(arrow)
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            } else if let vimLabel = info.vimLabel, !vimLabel.isEmpty {
                KeycapSymbols.dynamicTextLabel(vimLabel, scale: scale)
                    .help(info.displayLabel)
            } else if !info.displayLabel.isEmpty {
                let skipSymbolConversion = KeycapSymbols.isModifierOrSpecialKey(info.displayLabel)

                if !skipSymbolConversion, let actionSymbol = KeycapSymbols.sfSymbolForAction(info.displayLabel) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .help(info.displayLabel)
                } else if !skipSymbolConversion, let sfSymbol = LabelMetadata.sfSymbol(forOutputLabel: info.displayLabel) {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .help(info.displayLabel)
                } else {
                    KeycapSymbols.dynamicTextLabel(info.displayLabel, scale: scale)
                        .help(info.displayLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func zoneSubtitleIcon(_ subtitle: String) -> some View {
        let arrowLabels: Set = ["←", "→", "↑", "↓"]
        if arrowLabels.contains(subtitle) {
            Text(subtitle)
                .font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        } else if let actionSymbol = KeycapSymbols.sfSymbolForAction(subtitle) {
            Image(systemName: actionSymbol)
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
        } else {
            KeycapSymbols.dynamicTextLabel(subtitle, scale: scale)
        }
    }

    // MARK: - Unmapped Key Fallback

    @ViewBuilder
    private var unmappedContent: some View {
        if isArrowKey {
            Text(baseLabel)
                .font(.system(size: 8 * scale, weight: .regular))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if key.layoutRole == .narrowModifier {
            fnKeyFallback
        } else if key.layoutRole == .bottomAligned || key.layoutRole == .escKey {
            unmappedBottomLabel
        } else {
            unmappedCenteredLabel
        }
    }

    private var fnKeyFallback: some View {
        Group {
            if key.label == "fn" {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "globe")
                        .font(.system(size: 8.5 * scale, weight: .regular))
                    if scale >= 1.0 {
                        Text("fn")
                            .font(.system(size: 7 * scale, weight: .regular))
                    }
                }
            } else {
                Text(baseLabel)
                    .font(.system(size: 11 * scale, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
    }

    private var unmappedBottomLabel: some View {
        let displayLabel: String = {
            if currentLayerName.lowercased() == "nav" {
                let physicalMetadata = LabelMetadata.forLabel(keyLabel)
                return physicalMetadata.wordLabel ?? keyLabel
            }
            return keyLabel
        }()
        let finalLabel = displayLabel.count > 2 ? displayLabel : displayLabel.uppercased()

        return VStack {
            Spacer(minLength: 0)
            HStack {
                Text(finalLabel)
                    .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                Spacer(minLength: 0)
            }
            .padding(.leading, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unmappedCenteredLabel: some View {
        let displayLabel: String = {
            if currentLayerName.lowercased() == "nav" {
                let modifierSymbols: Set = ["⌃", "⌥", "⌘", "fn"]
                if modifierSymbols.contains(keyLabel) { return keyLabel }
                let physicalMetadata = LabelMetadata.forLabel(keyLabel)
                return physicalMetadata.wordLabel ?? keyLabel
            }
            return keyLabel
        }()
        let finalLabel = displayLabel.count > 2 ? displayLabel : displayLabel.uppercased()
        let isCapsLock = key.keyCode == 57
        let alignment: Alignment = isCapsLock ? .bottomLeading : .topLeading

        return ZStack(alignment: alignment) {
            Text(finalLabel)
                .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
