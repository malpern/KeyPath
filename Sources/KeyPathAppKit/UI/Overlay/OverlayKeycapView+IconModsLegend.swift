import KeyPathCore
import SwiftUI

extension OverlayKeycapView {
    /// Icon mods style: symbols for modifiers, standard content for others
    @ViewBuilder
    var iconModsContent: some View {
        if key.layoutRole == .bottomAligned || key.layoutRole == .narrowModifier {
            modifierSymbolOnlyContent
        } else {
            standardKeyContent
        }
    }

    /// Modifier with symbol only (no text) for icon mods style
    @ViewBuilder
    var modifierSymbolOnlyContent: some View {
        let symbol = modifierSymbolForKey
        Text(symbol)
            .font(.system(size: 14 * scale, weight: .light))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Get the appropriate symbol for a modifier key
    var modifierSymbolForKey: String {
        let label = key.label.lowercased()
        switch label {
        case "⇧", "shift", "lshift", "rshift": return "⇧"
        case "⌃", "ctrl", "control", "lctrl", "rctrl": return "⌃"
        case "⌥", "opt", "option", "alt", "lalt", "ralt": return "⌥"
        case "⌘", "cmd", "command", "lcmd", "rcmd", "meta", "lmeta", "rmeta": return "⌘"
        case "fn", "function": return "🌐"
        case "⇪", "caps", "capslock", "caps lock": return "⇪"
        case "⌫", "delete", "backspace", "bksp", "bspc": return "⌫"
        case "⌦", "del", "forward delete", "fwd del": return "⌦"
        case "⏎", "↵", "↩", "return", "enter", "ret", "ent": return "↩"
        case "⇥", "tab": return "⇥"
        case "⎋", "esc", "escape": return "⎋"
        case "␣", " ", "space", "spc": return "␣"
        case "home": return "↖"
        case "end": return "↘"
        case "pageup", "pgup", "page up": return "⇞"
        case "pagedown", "pgdn", "page down", "page dn": return "⇟"
        case "◀", "←", "left": return "◀"
        case "▶", "→", "right": return "▶"
        case "▲", "↑", "up": return "▲"
        case "▼", "↓", "down": return "▼"
        case "🔇", "mute": return "🔇"
        case "🔉", "voldown", "vol-": return "🔉"
        case "🔊", "volup", "vol+": return "🔊"
        case "🔅", "bridn", "bri-": return "🔅"
        case "🔆", "briup", "bri+": return "🔆"
        default: return key.label
        }
    }
}
