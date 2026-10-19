import KeyPathRulesCore

/// Display model for the Vim Navigation layer reference (keyboard map + grouped list).
///
/// Built from the collection's live `KeyMapping`s so a customised layer still renders,
/// with curated titles for the shipped keys. The catalog descriptions repeat the key
/// ("h — left"), which reads badly once the key is already drawn next to the text.
struct VimLayerReferenceEntry: Identifiable, Equatable {
    struct Variant: Equatable {
        /// Key as typed with the modifier held, e.g. "⇧G" or "⌃d".
        let label: String
        let title: String
        /// macOS shortcut this sends, in symbols, e.g. "⌘↓".
        let sends: String
    }

    /// The physical input key, lowercased (e.g. "4" for `$`).
    let input: String
    /// Legend drawn on the keyboard key (e.g. "$" on the 4 key).
    let capLabel: String
    /// Label used in the list (e.g. "gg" for g).
    let listLabel: String
    let title: String
    let sends: String
    let category: VimCategory?
    let shift: Variant?
    let ctrl: Variant?

    var id: String {
        input
    }

    func variant(for modifier: VimLayerModifier) -> Variant? {
        switch modifier {
        case .none: Variant(label: capLabel, title: title, sends: sends)
        case .shift: shift
        case .control: ctrl
        }
    }
}

enum VimLayerModifier: String, CaseIterable, Identifiable {
    case none, shift, control

    var id: String {
        rawValue
    }
}

enum VimLayerReference {
    private struct Curated {
        let title: String
        var capLabel: String?
        var listLabel: String?
        var shiftTitle: String?
        var shiftLabel: String?
        var ctrlTitle: String?
    }

    private static let curated: [String: Curated] = [
        "h": Curated(title: "Left"),
        "j": Curated(title: "Down"),
        "k": Curated(title: "Up"),
        "l": Curated(title: "Right"),
        "0": Curated(title: "Line start"),
        "4": Curated(title: "Line end", capLabel: "$", listLabel: "$"),
        "a": Curated(title: "Append", shiftTitle: "Append at line end"),
        "g": Curated(title: "Top of document", listLabel: "gg", shiftTitle: "Bottom of document"),
        "/": Curated(title: "Find"),
        "n": Curated(title: "Next match", shiftTitle: "Previous match"),
        "y": Curated(title: "Copy"),
        "p": Curated(title: "Paste"),
        "x": Curated(title: "Delete character"),
        "r": Curated(title: "Redo"),
        "d": Curated(title: "Delete previous word", ctrlTitle: "Page down"),
        "u": Curated(title: "Undo", ctrlTitle: "Page up"),
        "o": Curated(title: "New line below", shiftTitle: "New line above")
    ]

    private static let capTitles: [String: String] = [
        "Line start": "Start", "Line end": "End", "Top of document": "Top",
        "Bottom of document": "Bottom", "Delete character": "Delete", "Delete previous word": "Del ←",
        "New line below": "Open", "New line above": "Open ↑", "Next match": "Next",
        "Previous match": "Prev", "Append": "After", "Append at line end": "At end",
        "Page down": "Pg ↓", "Page up": "Pg ↑"
    ]

    /// Short form for a keycap, where a full title like "Delete previous word" would truncate.
    static func capTitle(for title: String) -> String {
        capTitles[title] ?? title
    }

    /// How one shipped Vim key reads on every surface (overlay keycap, Shortcut List,
    /// Settings), so the same key never has three names.
    struct KeyPresentation: Equatable {
        /// Legend for the key itself ("$" on the 4 key, "gg" for g).
        let keyLabel: String
        /// Short label that fits a one-unit keycap: arrows for h/j/k/l, else a word.
        let keycapLabel: String
        /// Full name for lists and detail lines.
        let title: String
        let category: VimCategory?
    }

    static func presentation(forInput rawInput: String) -> KeyPresentation? {
        let input = rawInput.lowercased()
        guard let known = curated[input] else { return nil }
        let arrow = arrowCluster.first { $0.input == input }?.arrow
        return KeyPresentation(
            keyLabel: known.listLabel ?? known.capLabel ?? input,
            keycapLabel: arrow ?? capTitle(for: known.title),
            title: known.title,
            category: VimCategory.allCases.first { $0.commandInputs.contains(input) }
        )
    }

    /// The four home-row arrows, drawn as one cluster in the list instead of four rows.
    static let arrowCluster: [(input: String, arrow: String)] = [
        ("h", "←"), ("j", "↓"), ("k", "↑"), ("l", "→")
    ]

    static func entries(from mappings: [KeyMapping]) -> [VimLayerReferenceEntry] {
        mappings.map(entry(for:))
    }

    static func entry(for mapping: KeyMapping) -> VimLayerReferenceEntry {
        let input = mapping.input.lowercased()
        let known = curated[input]
        let capLabel = known?.capLabel ?? input
        let title = known?.title ?? fallbackTitle(mapping)
        let category = VimCategory.allCases.first { $0.commandInputs.contains(input) }

        let shift = mapping.shiftedOutput.map { output in
            VimLayerReferenceEntry.Variant(
                label: "⇧" + (known?.shiftLabel ?? capLabel.uppercased()),
                title: known?.shiftTitle ?? "Shifted: \(symbols(for: output))",
                sends: symbols(for: output)
            )
        }
        let ctrl = mapping.ctrlOutput.map { output in
            VimLayerReferenceEntry.Variant(
                label: "⌃" + capLabel,
                title: known?.ctrlTitle ?? "With Control: \(symbols(for: output))",
                sends: symbols(for: output)
            )
        }

        return VimLayerReferenceEntry(
            input: input,
            capLabel: capLabel,
            listLabel: known?.listLabel ?? capLabel,
            title: title,
            sends: symbols(for: mapping.action.displayName),
            category: category,
            shift: shift,
            ctrl: ctrl
        )
    }

    /// "h — left" → "Left". Falls back to the action when there is no description.
    static func fallbackTitle(_ mapping: KeyMapping) -> String {
        guard let description = mapping.description, !description.isEmpty else {
            return symbols(for: mapping.action.displayName)
        }
        let text = description.components(separatedBy: " — ").last ?? description
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Kanata output notation → macOS symbols ("M-S-z" → "⌘⇧z", "A-bspc" → "⌥⌫").
    static func symbols(for output: String) -> String {
        output.split(separator: " ").map { part -> String in
            var text = String(part)
            let modifiers: [(String, String)] = [
                ("C-M-A-S-", "⌃⌘⌥⇧"), ("C-M-A-", "⌃⌘⌥"), ("M-S-", "⌘⇧"), ("C-S-", "⌃⇧"),
                ("A-S-", "⌥⇧"), ("M-", "⌘"), ("A-", "⌥"), ("C-", "⌃"), ("S-", "⇧")
            ]
            var prefix = ""
            for (token, symbol) in modifiers where text.hasPrefix(token) {
                prefix = symbol
                text.removeFirst(token.count)
                break
            }
            let keys: [String: String] = [
                "left": "←", "right": "→", "up": "↑", "down": "↓", "ret": "↩",
                "bspc": "⌫", "del": "⌦", "pgup": "Page Up", "pgdn": "Page Down",
                "esc": "⎋", "tab": "⇥", "spc": "Space"
            ]
            let key = keys[text] ?? (text.count == 1 ? text.uppercased() : text)
            return prefix + key
        }.joined(separator: " ")
    }
}
