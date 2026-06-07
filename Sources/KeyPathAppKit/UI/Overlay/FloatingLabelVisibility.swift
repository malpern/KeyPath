import Foundation

struct FloatingLabelVisibility {
    let labelToKeyCode: [String: UInt16]
    let isLauncherMode: Bool
    let isLayerMode: Bool
    let vimHintsActive: Bool
    let remappedLabels: Set<String>
    let zoneSubtitleLabels: Set<String>

    func isVisible(_ label: String) -> Bool {
        suppressesKeycapContent(label)
            && !(vimHintsActive && Self.isLoudVimHintLabel(label.uppercased()))
    }

    func suppressesKeycapContent(_ label: String) -> Bool {
        let normalized = label.uppercased()
        return labelToKeyCode[normalized] != nil
            && !Self.isSpecialLabel(label)
            && !isLauncherMode
            && !isLayerMode
            && !remappedLabels.contains(normalized)
            && !zoneSubtitleLabels.contains(normalized)
    }

    private static func isLoudVimHintLabel(_ label: String) -> Bool {
        ["H", "J", "K", "L"].contains(label)
    }

    private static let specialLabels: Set<String> = [
        "Home", "End", "PgUp", "PgDn", "Del", "␣", "Lyr", "Fn", "Mod", "✦", "◆",
        "↩", "⌫", "⇥", "⇪", "esc", "ESC", "⎋", "🔒",
        "⇧", "⌃", "⌥", "⌘",
        "◀", "▶", "▲", "▼", "←", "→", "↑", "↓",
        "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        "prt", "scr", "pse",
        "ins", "del", "home", "end", "pgup", "pgdn",
        "INS", "DEL", "HOME", "END", "PGUP", "PGDN",
        "clr", "CLR", "/", "*", "+", ".",
        "¥", "英数", "かな", "_", "^", ":", "@", "fn",
        "☰", "▤",
        "⏎", "⌅"
    ]

    static func isSpecialLabel(_ label: String) -> Bool {
        specialLabels.contains(label) || specialLabels.contains(label.lowercased())
    }
}
