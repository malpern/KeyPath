import Foundation

struct KeyCodeSuggestion: Identifiable, Hashable {
    let keyCode: UInt16
    let canonicalName: String
    let preferredLabel: String

    var id: UInt16 { keyCode }

    var displayText: String {
        "\(keyCode)  \(preferredLabel)  \(canonicalName)"
    }

    var searchTokens: [String] {
        [String(keyCode), preferredLabel, canonicalName]
    }
}

enum KeySuggestionCatalog {
    static let keyCodeSuggestions: [KeyCodeSuggestion] = buildKeyCodeSuggestions()
    static let commonLabelSuggestions: [String] = buildLabelSuggestions()

    private static func buildKeyCodeSuggestions() -> [KeyCodeSuggestion] {
        let preferredLabels = preferredLabelsByKeyCode()
        return macOSKeycodes
            .map { keyCode, canonicalName in
                KeyCodeSuggestion(
                    keyCode: keyCode,
                    canonicalName: canonicalName,
                    preferredLabel: preferredLabels[keyCode] ?? defaultLabel(for: canonicalName)
                )
            }
            .sorted { lhs, rhs in lhs.keyCode < rhs.keyCode }
    }

    private static func buildLabelSuggestions() -> [String] {
        var labels = Set<String>()

        for entry in LayoutCatalog.builtInLayouts() {
            guard let data = try? Data(contentsOf: entry.fileURL),
                  let imported = try? LayoutTracerImporter.load(from: data)
            else { continue }
            for key in imported.keys {
                let trimmed = key.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    labels.insert(trimmed)
                }
            }
        }

        labels.formUnion([
            "esc", "tab", "caps", "shift", "control", "option", "command", "return",
            "space", "home", "end", "pgup", "pgdn", "help", "fn", "delete",
            "⌘", "⌥", "⌃", "⇧", "⇪", "⇥", "↩", "⌫", "⌦", "␣",
            "←", "→", "↑", "↓", "▲", "▼", "◀", "▶",
            "`", "~", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "_",
            "{", "}", "(", ")", "+", "!", "@", "#", "$", "%", "^", "&", "*"
        ])

        return labels.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private static func preferredLabelsByKeyCode() -> [UInt16: String] {
        var counts: [UInt16: [String: Int]] = [:]
        for entry in LayoutCatalog.builtInLayouts() {
            guard let data = try? Data(contentsOf: entry.fileURL),
                  let imported = try? LayoutTracerImporter.load(from: data)
            else { continue }
            for key in imported.keys {
                let trimmed = key.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                counts[key.keyCode, default: [:]][trimmed, default: 0] += 1
            }
        }

        return counts.reduce(into: [:]) { result, entry in
            if let best = entry.value.max(by: { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.count > rhs.key.count
                }
                return lhs.value < rhs.value
            }) {
                result[entry.key] = best.key
            }
        }
    }

    private static func defaultLabel(for canonicalName: String) -> String {
        switch canonicalName {
        case "backspace": "⌫"
        case "delete": "⌦"
        case "return", "enter": "↩"
        case "space": "space"
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "leftmeta", "rightmeta": "⌘"
        case "leftalt", "rightalt": "⌥"
        case "leftctrl", "rightctrl": "⌃"
        case "leftshift", "rightshift": "⇧"
        case "capslock": "⇪"
        case "tab": "⇥"
        case "pageup": "pgup"
        case "pagedown": "pgdn"
        default: canonicalName
        }
    }

    // Sourced from KeyPath's canonical macOS keycode mapping used by the overlay/simulator.
    private static let macOSKeycodes: [(UInt16, String)] = [
        (0, "a"), (1, "s"), (2, "d"), (3, "f"), (4, "h"), (5, "g"),
        (6, "z"), (7, "x"), (8, "c"), (9, "v"), (10, "intlbackslash"), (11, "b"),
        (12, "q"), (13, "w"), (14, "e"), (15, "r"), (16, "y"), (17, "t"),
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (22, "6"), (23, "5"),
        (24, "equal"), (25, "9"), (26, "7"), (27, "minus"), (28, "8"), (29, "0"),
        (30, "rightbrace"), (31, "o"), (32, "u"), (33, "leftbrace"), (34, "i"), (35, "p"),
        (36, "return"), (37, "l"), (38, "j"), (39, "apostrophe"), (40, "k"), (41, "semicolon"),
        (42, "backslash"), (43, "comma"), (44, "slash"), (45, "n"), (46, "m"), (47, "dot"),
        (48, "tab"), (49, "space"), (50, "grave"), (51, "backspace"), (53, "esc"),
        (54, "rightmeta"), (55, "leftmeta"), (56, "leftshift"), (57, "capslock"),
        (58, "leftalt"), (59, "leftctrl"), (60, "rightshift"), (61, "rightalt"), (63, "fn"),
        (64, "f17"), (79, "f18"), (80, "f19"), (94, "intlro"), (96, "f5"), (97, "f6"),
        (98, "f7"), (99, "f3"), (100, "f8"), (101, "f9"), (102, "rightctrl"),
        (103, "f11"), (104, "hangeul"), (105, "f13"), (106, "f16"), (107, "f14"),
        (109, "f10"), (111, "f12"), (113, "f15"), (114, "help"), (115, "home"),
        (116, "pageup"), (117, "delete"), (118, "f4"), (119, "end"), (120, "f2"),
        (121, "pagedown"), (122, "f1"), (123, "left"), (124, "right"), (125, "down"), (126, "up")
    ]
}
