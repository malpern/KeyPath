import KeyPathCore
import SwiftUI

extension OverlayKeycapView {
    /// Whether this key has a special label that should always be rendered in the keycap
    /// (not handled by floating labels). Includes navigation keys, system keys, number row, etc.
    var hasSpecialLabel: Bool {
        let specialLabels: Set<String> = [
            "Home", "End", "PgUp", "PgDn", "Del", "Lyr", "Fn", "Mod", "✦", "◆",
            "↩", "⌫", "⇥", "⇪", "esc", "⎋",
            "◀", "▶", "▲", "▼", "←", "→", "↑", "↓",
            "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
            "prt", "scr", "pse",
            "ins", "del", "home", "end", "pgup", "pgdn",
            "INS", "DEL", "HOME", "END", "PGUP", "PGDN",
            "⌦",
            "num",
            "mute", "v-", "v+",
            "play", "next", "prev", "stop", "eject",
            "bri+", "bri-",
            "clr", "CLR", "/", "*", "+", ".",
            "§", "#",
            "¥", "英数", "かな", "_", "^", ":", "@", "fn", "Fn",
            "kana", "henk", "mhen",
            "~", "(", ")", "{", "}", "<", ">",
            "help",
            "☰", "▤",
            "⏎", "⌅",
            "Shift", "shift", "⇧",
            "Control", "control", "Ctrl", "ctrl", "⌃",
            "Option", "option", "Alt", "alt", "⌥",
            "Command", "command", "Cmd", "cmd", "⌘",
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

    /// Word labels for navigation/system keys (like ESC style).
    var navigationWordLabel: String? {
        let label = key.label.lowercased()
        switch label {
        case "home": return "home"
        case "end": return "end"
        case "pgup": return "pg up"
        case "pgdn": return "pg dn"
        case "ins": return "insert"
        case "del", "⌦": return "del"
        case "prt": return "print screen"
        case "scr": return "scroll"
        case "pse": return "pause"
        case "clr": return "clear"
        case "☰", "▤": return "menu"
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
        case "⌫": return "delete"
        case "↩": return "return"
        case "⏎", "⌅": return "enter"
        case "⇧": return "shift"
        case "⌃": return "ctrl"
        case "⌥": return "opt"
        case "⌘": return "cmd"
        default: return nil
        }
    }

    /// SF Symbol for special keys (some use icons instead of text)
    var navigationSFSymbol: String? {
        nil
    }

    /// Whether this key is remapped to a different output
    var isRemappedKey: Bool {
        if isKeymapTransitioning {
            return false
        }
        guard let info = layerKeyInfo else { return false }
        return !info.displayLabel.isEmpty && info.displayLabel.uppercased() != baseLabel.uppercased()
    }
}
