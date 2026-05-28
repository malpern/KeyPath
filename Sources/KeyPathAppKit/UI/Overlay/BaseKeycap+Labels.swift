import SwiftUI

// MARK: - Label Classification & Computed Properties

extension BaseKeycap {
    var effectiveLabel: String {
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

    var shouldShowTapHoldIdleLabel: Bool {
        guard !isLauncherMode else { return false }
        return currentLayerName.lowercased() == "base"
    }

    var inputKeyName: String {
        OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
    }

    var shouldUseBaseLabel: Bool {
        guard let info = layerKeyInfo else { return true }
        if info.isTransparent { return true }
        if info.isLayerSwitch { return false }
        if info.appLaunchIdentifier != nil || info.systemActionIdentifier != nil
            || info.urlIdentifier != nil {
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

    var metadata: LabelMetadata {
        var meta = LabelMetadata.forLabel(effectiveLabel)
        if let shiftOverride = shiftLabelOverride {
            meta.shiftSymbol = shiftOverride
        }
        if let customShift = layerKeyInfo?.customShiftLabel {
            meta.shiftSymbol = customShift
        }
        return meta
    }

    var adjustments: OpticalAdjustments {
        OpticalAdjustments.forLabel(effectiveLabel)
    }

    var isSmallSize: Bool {
        scale < 0.8
    }

    var isNumpadKey: Bool {
        let numpadKeyCodes: Set<UInt16> = [
            65, 67, 69, 71, 75, 76, 78, 81,
            82, 83, 84, 85, 86, 87, 88, 89, 91, 92
        ]
        return numpadKeyCodes.contains(key.keyCode)
    }

    var hasAppLaunch: Bool {
        layerKeyInfo?.appLaunchIdentifier != nil
    }

    var hasURLMapping: Bool {
        layerKeyInfo?.urlIdentifier != nil
    }

    var hasSystemAction: Bool {
        layerKeyInfo?.systemActionIdentifier != nil
    }

    var hasSpecialLabel: Bool {
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
            "Adjust", "adjust", "Adj", "adj"
        ]
        if specialLabels.contains(key.label) || specialLabels.contains(baseLabel) {
            return true
        }
        if PhysicalLayout.isLayerKeyLabel(key.label) {
            return true
        }
        return specialLabels.contains(effectiveLabel)
    }

    var navigationWordLabel: String? {
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

    var navigationSFSymbol: String? {
        nil
    }

    var isRemappedKey: Bool {
        if isKeymapTransitioning {
            return false
        }
        guard let info = layerKeyInfo else { return false }
        return !info.displayLabel.isEmpty && info.displayLabel.uppercased() != baseLabel.uppercased()
    }

    var navOverlaySymbol: String? {
        guard key.layoutRole == .centered, let info = layerKeyInfo else { return nil }
        let arrowLabels: Set = ["\u{2190}", "\u{2192}", "\u{2191}", "\u{2193}"]
        if arrowLabels.contains(info.displayLabel) {
            return info.displayLabel
        }
        return nil
    }

    var zoneSubtitleRenderedInline: Bool {
        guard zoneSubtitle != nil, !isLayerMode, !isLauncherMode else { return false }
        guard colorway.legendStyle == .standard else { return false }
        guard key.layoutRole == .centered else { return false }
        guard navigationSFSymbol == nil else { return false }
        guard navOverlaySymbol == nil else { return false }
        guard metadata.shiftSymbol == nil || isNumpadKey else { return false }
        return true
    }

    var hasNoveltyKey: Bool {
        colorway.noveltyConfig.noveltyForKey(label: key.label) != nil
    }
}
