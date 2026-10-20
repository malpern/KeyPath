import Foundation
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
    /// Short label drawn on the keycap, the same one the overlay uses (arrows for h/j/k/l).
    var keycap: String = ""
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

/// How a Vim-family pack names its keys: plain words ("Copy", "Top") or Vim's own
/// terms ("yank", "gg"). Chosen per pack; Vim Navigation defaults to plain, Neovim
/// Terminal to Vim terms.
enum VimKeyNameStyle: String, CaseIterable, Identifiable, Sendable {
    case plain
    case vim

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .plain: "Plain"
        case .vim: "Vim terms"
        }
    }

    static func defaultStyle(for collectionId: UUID) -> VimKeyNameStyle {
        collectionId == RuleCollectionIdentifier.neovimTerminal ? .vim : .plain
    }

    static let defaultsKey = "KeyPath.Vim.KeyNameStyle"

    /// The pack's chosen style. Reads UserDefaults directly so the layer mapper (an
    /// actor, off the main thread) can use it.
    static func current(for collectionId: UUID, defaults: UserDefaults = .standard) -> VimKeyNameStyle {
        let stored = defaults.dictionary(forKey: defaultsKey) as? [String: String]
        return stored?[collectionId.uuidString].flatMap(VimKeyNameStyle.init(rawValue:))
            ?? defaultStyle(for: collectionId)
    }

    static func set(_ style: VimKeyNameStyle, for collectionId: UUID, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        stored[collectionId.uuidString] = style.rawValue
        defaults.set(stored, forKey: defaultsKey)
        NotificationCenter.default.post(name: .vimKeyNameStyleChanged, object: nil)
    }

    /// Changes whenever either pack's style changes; part of layer-mapping cache keys.
    static func cacheSignature(defaults: UserDefaults = .standard) -> String {
        [RuleCollectionIdentifier.vimNavigation, RuleCollectionIdentifier.neovimTerminal]
            .map { current(for: $0, defaults: defaults).rawValue }
            .joined(separator: ",")
    }
}

extension Notification.Name {
    /// Posted when a Vim-family pack switches between plain and Vim-term key names.
    static let vimKeyNameStyleChanged = Notification.Name("KeyPath.VimKeyNameStyleChanged")
}

enum VimLayerReference {
    /// Vim's own name for a key, for packs set to Vim terms.
    private struct VimTerms {
        let keycap: String
        let title: String
        var shiftTitle: String?
        var ctrlTitle: String?
    }

    private struct Curated {
        let title: String
        var capLabel: String?
        var listLabel: String?
        var shiftTitle: String?
        var shiftLabel: String?
        var ctrlTitle: String?
        var vim: VimTerms?
    }

    private static let curated: [String: Curated] = [
        "h": Curated(title: "Left", vim: VimTerms(keycap: "←", title: "Left")),
        "j": Curated(title: "Down", vim: VimTerms(keycap: "↓", title: "Down")),
        "k": Curated(title: "Up", vim: VimTerms(keycap: "↑", title: "Up")),
        "l": Curated(title: "Right", vim: VimTerms(keycap: "→", title: "Right")),
        "0": Curated(title: "Line start", vim: VimTerms(keycap: "0", title: "Start of line")),
        "4": Curated(title: "Line end", capLabel: "$", listLabel: "$", vim: VimTerms(keycap: "$", title: "End of line")),
        "a": Curated(title: "Append", shiftTitle: "Append at line end",
                     vim: VimTerms(keycap: "append", title: "Append", shiftTitle: "Append at end of line")),
        "g": Curated(title: "Top of document", listLabel: "gg", shiftTitle: "Bottom of document",
                     vim: VimTerms(keycap: "gg", title: "Go to first line", shiftTitle: "Go to last line")),
        "/": Curated(title: "Find", vim: VimTerms(keycap: "search", title: "Search")),
        "n": Curated(title: "Next match", shiftTitle: "Previous match",
                     vim: VimTerms(keycap: "next", title: "Next match", shiftTitle: "Previous match")),
        "y": Curated(title: "Copy", vim: VimTerms(keycap: "yank", title: "Yank")),
        "p": Curated(title: "Paste", vim: VimTerms(keycap: "put", title: "Put")),
        "x": Curated(title: "Delete character", vim: VimTerms(keycap: "del", title: "Delete character")),
        "r": Curated(title: "Redo", vim: VimTerms(keycap: "redo", title: "Redo")),
        "d": Curated(title: "Delete previous word", ctrlTitle: "Page down",
                     vim: VimTerms(keycap: "db", title: "Delete word back", ctrlTitle: "Half page down")),
        "u": Curated(title: "Undo", ctrlTitle: "Page up",
                     vim: VimTerms(keycap: "undo", title: "Undo", ctrlTitle: "Half page up")),
        "o": Curated(title: "New line below", shiftTitle: "New line above",
                     vim: VimTerms(keycap: "open", title: "Open line below", shiftTitle: "Open line above")),
        // Word motions (Neovim Terminal)
        "w": Curated(title: "Next word", vim: VimTerms(keycap: "word", title: "Word forward")),
        "b": Curated(title: "Previous word", vim: VimTerms(keycap: "back", title: "Word back")),
        "e": Curated(title: "End of word", vim: VimTerms(keycap: "end", title: "End of word"))
    ]

    private static let capTitles: [String: String] = [
        "Line start": "Start", "Line end": "End", "Top of document": "Top",
        "Bottom of document": "Bottom", "Delete character": "Delete", "Delete previous word": "Del ←",
        "New line below": "Open", "New line above": "Open ↑", "Next match": "Next",
        "Previous match": "Prev", "Append": "After", "Append at line end": "At end",
        "Page down": "Pg ↓", "Page up": "Pg ↑",
        "Next word": "Word →", "Previous word": "← Word", "End of word": "Wd end",
        // Vim-terms variants: Vim's own notation for the shifted and Control forms.
        "Go to first line": "gg", "Go to last line": "G", "Append at end of line": "A",
        "Open line above": "O", "Half page down": "⌃d", "Half page up": "⌃u",
        "Start of line": "0", "End of line": "$", "Delete word back": "db", "Open line below": "open",
        "Word forward": "word", "Word back": "back", "Yank": "yank", "Put": "put", "Search": "search"
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

    static func presentation(forInput rawInput: String, style: VimKeyNameStyle = .plain) -> KeyPresentation? {
        let input = rawInput.lowercased()
        guard let known = curated[input] else { return nil }
        let arrow = arrowCluster.first { $0.input == input }?.arrow
        let vim = style == .vim ? known.vim : nil
        return KeyPresentation(
            keyLabel: known.listLabel ?? known.capLabel ?? input,
            keycapLabel: arrow ?? vim?.keycap ?? capTitle(for: known.title),
            title: vim?.title ?? known.title,
            category: VimCategory.allCases.first { $0.commandInputs.contains(input) }
        )
    }

    /// The four home-row arrows, drawn as one cluster in the list instead of four rows.
    static let arrowCluster: [(input: String, arrow: String)] = [
        ("h", "←"), ("j", "↓"), ("k", "↑"), ("l", "→")
    ]

    static func entries(from mappings: [KeyMapping], style: VimKeyNameStyle = .plain) -> [VimLayerReferenceEntry] {
        mappings.map { entry(for: $0, style: style) }
    }

    static func entry(for mapping: KeyMapping, style: VimKeyNameStyle = .plain) -> VimLayerReferenceEntry {
        let input = mapping.input.lowercased()
        let known = curated[input]
        let vim = style == .vim ? known?.vim : nil
        let capLabel = known?.capLabel ?? input
        let title = vim?.title ?? known?.title ?? fallbackTitle(mapping)
        let category = VimCategory.allCases.first { $0.commandInputs.contains(input) }

        let shift = mapping.shiftedOutput.map { output in
            VimLayerReferenceEntry.Variant(
                label: "⇧" + (known?.shiftLabel ?? capLabel.uppercased()),
                title: vim?.shiftTitle ?? known?.shiftTitle ?? "Shifted: \(symbols(for: output))",
                sends: symbols(for: output)
            )
        }
        let ctrl = mapping.ctrlOutput.map { output in
            VimLayerReferenceEntry.Variant(
                label: "⌃" + capLabel,
                title: vim?.ctrlTitle ?? known?.ctrlTitle ?? "With Control: \(symbols(for: output))",
                sends: symbols(for: output)
            )
        }

        return VimLayerReferenceEntry(
            input: input,
            capLabel: capLabel,
            listLabel: known?.listLabel ?? capLabel,
            keycap: presentation(forInput: input, style: style)?.keycapLabel ?? capTitle(for: title),
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
