import AppKit
import KeyPathCore
import SwiftUI

// MARK: - BaseKeycap

/// Renders base-layer keycap content (everything except launcher mode, layer mode, and touchId).
/// Extracted from OverlayKeycapView to reduce view complexity.
struct BaseKeycap: View {
    let key: PhysicalKey
    let baseLabel: String
    let scale: CGFloat
    let foregroundColor: Color
    let colorway: GMKColorway
    let layerKeyInfo: LayerKeyInfo?
    let holdLabel: String?
    let tapHoldIdleLabel: String?
    let useFloatingLabels: Bool
    let shiftLabelOverride: String?
    let isPressed: Bool
    let currentLayerName: String
    let isLauncherMode: Bool
    let isLayerMode: Bool
    let isKeymapTransitioning: Bool
    let appIcon: NSImage?
    let faviconImage: NSImage?
    let systemActionIcon: String?
    let zoneSubtitle: String?
    let isLoadingLayerMap: Bool
    let isCapsLockOn: Bool
    let isInlineLayer: Bool
    let hasLayerMapping: Bool

    // MARK: - Body (Content Routing)

    var body: some View {
        // Multi-legend keys (JIS/ISO) get special 4-position rendering
        if key.hasMultipleLegends {
            multiLegendContent
        }
        // Check for novelty override first (ESC, Enter with special icons)
        else if hasNoveltyKey {
            noveltyKeyContent
        }
        // Function keys always show F-label + icon (even when remapped)
        else if key.layoutRole == .functionKey {
            functionKeyWithMappingContent
        }
        // URL mapping keys show favicon
        else if hasURLMapping {
            urlMappingContent
        }
        // App launch keys show app icon regardless of layout role
        else if hasAppLaunch {
            appLaunchContent
        }
        // System action keys show SF Symbol icon
        else if hasSystemAction {
            systemActionContent
        }
        // Inline layer mapped keys: arrows centered, nav words bottom-aligned
        else if isInlineLayer, hasLayerMapping, let info = layerKeyInfo {
            inlineLayerMappedContent(info: info)
        } else {
            switch key.layoutRole {
            case .centered:
                centeredContent
            case .bottomAligned:
                bottomAlignedContent
            case .narrowModifier:
                narrowModifierContent
            case .functionKey:
                functionKeyContent // Should never reach here due to check above
            case .arrow:
                arrowContent
            case .touchId:
                touchIdContent
            case .escKey:
                escKeyContent
            }
        }
    }

    // MARK: - Computed Properties (derived from parameters)

    private var effectiveLabel: String {
        if isPressed, let holdLabel {
            return holdLabel
        }
        if !isPressed, let tapHoldIdleLabel, shouldShowTapHoldIdleLabel {
            return tapHoldIdleLabel
        }
        if isLayerMode, let subtitle = zoneSubtitle {
            return subtitle
        }
        guard let info = layerKeyInfo else {
            return baseLabel
        }
        if info.displayLabel.isEmpty {
            return baseLabel.isEmpty ? key.label : baseLabel
        }
        if shouldUseBaseLabel, baseLabel != key.label {
            return baseLabel
        }
        return info.displayLabel
    }

    private var shouldShowTapHoldIdleLabel: Bool {
        guard !isLauncherMode else { return false }
        return currentLayerName.lowercased() == "base"
    }

    private var inputKeyName: String {
        OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
    }

    private var shouldUseBaseLabel: Bool {
        guard let info = layerKeyInfo else { return true }
        if info.isTransparent { return true }
        if info.isLayerSwitch { return false }
        if info.appLaunchIdentifier != nil || info.systemActionIdentifier != nil
            || info.urlIdentifier != nil
        {
            return false
        }
        if !info.displayLabel.isEmpty, info.displayLabel.lowercased() != inputKeyName {
            return false
        }
        if let outputKey = info.outputKey {
            return outputKey.lowercased() == inputKeyName
        }
        return true
    }

    private var metadata: LabelMetadata {
        var meta = LabelMetadata.forLabel(effectiveLabel)
        if let shiftOverride = shiftLabelOverride {
            meta.shiftSymbol = shiftOverride
        }
        if let customShift = layerKeyInfo?.customShiftLabel {
            meta.shiftSymbol = customShift
        }
        return meta
    }

    private var adjustments: OpticalAdjustments {
        OpticalAdjustments.forLabel(effectiveLabel)
    }

    private var isSmallSize: Bool {
        scale < 0.8
    }

    private var isNumpadKey: Bool {
        let numpadKeyCodes: Set<UInt16> = [
            65, 67, 69, 71, 75, 76, 78, 81, // operators and special
            82, 83, 84, 85, 86, 87, 88, 89, 91, 92, // numbers 0-9
        ]
        return numpadKeyCodes.contains(key.keyCode)
    }

    private var hasAppLaunch: Bool {
        layerKeyInfo?.appLaunchIdentifier != nil
    }

    private var hasURLMapping: Bool {
        layerKeyInfo?.urlIdentifier != nil
    }

    private var hasSystemAction: Bool {
        layerKeyInfo?.systemActionIdentifier != nil
    }

    // MARK: - Label Classification

    private var hasSpecialLabel: Bool {
        let specialLabels: Set = [
            "Home", "End", "PgUp", "PgDn", "Del", "Lyr", "Fn", "Mod", "\u{2726}", "\u{25C6}",
            "\u{21A9}", "\u{232B}", "\u{21E5}", "\u{21EA}", "esc", "\u{238B}",
            "\u{25C0}", "\u{25B6}", "\u{25B2}", "\u{25BC}", "\u{2190}", "\u{2192}", "\u{2191}", "\u{2193}",
            "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
            "prt", "scr", "pse",
            "ins", "del", "home", "end", "pgup", "pgdn",
            "INS", "DEL", "HOME", "END", "PGUP", "PGDN",
            "\u{2326}",
            "num",
            "mute", "v-", "v+",
            "play", "next", "prev", "stop", "eject",
            "bri+", "bri-",
            "clr", "CLR", "/", "*", "+", ".",
            "\u{00A7}", "#",
            "\u{00A5}", "\u{82F1}\u{6570}", "\u{304B}\u{306A}", "_", "^", ":", "@", "fn", "Fn",
            "kana", "henk", "mhen",
            "~", "(", ")", "{", "}", "<", ">",
            "help",
            "\u{2630}", "\u{25A4}",
            "\u{23CE}", "\u{2305}",
            "Shift", "shift", "\u{21E7}",
            "Control", "control", "Ctrl", "ctrl", "\u{2303}",
            "Option", "option", "Alt", "alt", "\u{2325}",
            "Command", "command", "Cmd", "cmd", "\u{2318}",
            "Lower", "lower", "Lwr", "lwr",
            "Raise", "raise", "Rse", "rse",
            "Adjust", "adjust", "Adj", "adj",
        ]
        if specialLabels.contains(key.label) || specialLabels.contains(baseLabel) {
            return true
        }
        if PhysicalLayout.isLayerKeyLabel(key.label) {
            return true
        }
        return specialLabels.contains(effectiveLabel)
    }

    private var navigationWordLabel: String? {
        let label = key.label.lowercased()
        switch label {
        case "home": return "home"
        case "end": return "end"
        case "pgup": return "pg up"
        case "pgdn": return "pg dn"
        case "ins": return "insert"
        case "del", "\u{2326}": return "del"
        case "prt": return "print screen"
        case "scr": return "scroll"
        case "pse": return "pause"
        case "clr": return "clear"
        case "\u{2630}", "\u{25A4}": return "menu"
        case "lyr": return "layer"
        case "fn": return "fn"
        case "mod": return "mod"
        case "shift": return "shift"
        case "control", "ctrl": return "ctrl"
        case "option", "alt": return "opt"
        case "command", "cmd": return "cmd"
        case "lower", "lwr": return "lower"
        case "raise", "rse": return "raise"
        case "adjust", "adj": return "adjust"
        default: break
        }
        guard PreferencesService.shared.keyLabelStyle == .text else { return nil }
        switch label {
        case "\u{232B}": return "delete"
        case "\u{21A9}": return "return"
        case "\u{23CE}", "\u{2305}": return "enter"
        case "\u{21E7}": return "shift"
        case "\u{2303}": return "ctrl"
        case "\u{2325}": return "opt"
        case "\u{2318}": return "cmd"
        default: return nil
        }
    }

    private var navigationSFSymbol: String? {
        nil
    }

    private var isRemappedKey: Bool {
        if isKeymapTransitioning {
            return false
        }
        guard let info = layerKeyInfo else { return false }
        return !info.displayLabel.isEmpty && info.displayLabel.uppercased() != baseLabel.uppercased()
    }

    // MARK: - Vim Nav Overlay

    private var navOverlaySymbol: String? {
        guard key.layoutRole == .centered, let info = layerKeyInfo else { return nil }
        let arrowLabels: Set = ["\u{2190}", "\u{2192}", "\u{2191}", "\u{2193}"]
        if arrowLabels.contains(info.displayLabel) {
            return info.displayLabel
        }
        return nil
    }

    private var zoneSubtitleRenderedInline: Bool {
        guard zoneSubtitle != nil, !isLayerMode, !isLauncherMode else { return false }
        guard colorway.legendStyle == .standard else { return false }
        guard key.layoutRole == .centered else { return false }
        guard navigationSFSymbol == nil else { return false }
        guard navOverlaySymbol == nil else { return false }
        guard metadata.shiftSymbol == nil || isNumpadKey else { return false }
        return true
    }

    // MARK: - Novelty Keys

    private var hasNoveltyKey: Bool {
        colorway.noveltyConfig.noveltyForKey(label: key.label) != nil
    }

    // MARK: - Layout: Centered (letters, symbols, spacebar)

    @ViewBuilder
    private var centeredContent: some View {
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
                if let subtitle = zoneSubtitle, !isLayerMode, !isLauncherMode {
                    let adj = OpticalAdjustments.forLabel(displayText)
                    VStack(spacing: dualSymbolSpacing(for: displayText)) {
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
                } else {
                    Text(isNumpadKey ? displayText : displayText.uppercased())
                        .font(.system(size: isNumpadKey ? 14 * scale : 12 * scale, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Navigation Word Content

    private func navigationWordContent(_ label: String) -> some View {
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
    private func dualSymbolContent(main: String, shift: String) -> some View {
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

    private func navOverlayContent(arrow: String, letter: String) -> some View {
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

    private func navOverlayArrowOnly(arrow: String) -> some View {
        Text(arrow)
            .font(.system(size: 14 * scale, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isPressed ? 1.0 : 0.9))
            .shadow(color: Color.black.opacity(0.25), radius: 1.5 * scale, y: 1 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Spacing Helper

    private func dualSymbolSpacing(for label: String) -> CGFloat {
        switch label {
        case ",", ".": -0.5 * scale
        case ";", "'", "/": 0
        default: 2 * scale
        }
    }

    // MARK: - Layout: Bottom Aligned (wide modifiers)

    @ViewBuilder
    private var bottomAlignedContent: some View {
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
    private func labelText(_ text: String, isHoldLabel: Bool) -> some View {
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
    private var noveltyKeyContent: some View {
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
    private var appLaunchContent: some View {
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
    private var urlMappingContent: some View {
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
    private var systemActionContent: some View {
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
    private var narrowModifierContent: some View {
        if key.label == "fn" {
            fnKeyContent
        } else {
            modifierSymbolContent
        }
    }

    @ViewBuilder
    private var fnKeyContent: some View {
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
    private var modifierSymbolContent: some View {
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
    private var functionKeyWithMappingContent: some View {
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
    private var functionKeyContent: some View {
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

    // MARK: - Arrow Content

    private var arrowContent: some View {
        Text(effectiveLabel)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Touch ID Content

    @ViewBuilder
    private var touchIdContent: some View {
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

    private func layerKeyContent(label: String) -> some View {
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

    private var escKeyContent: some View {
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

    private var multiLegendContent: some View {
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
    private func inlineLayerMappedContent(info: LayerKeyInfo) -> some View {
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
