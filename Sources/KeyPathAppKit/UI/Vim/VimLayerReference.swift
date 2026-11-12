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
        case .plain: String(localized: "Plain", comment: "Vim key-name style: plain words")
        case .vim: String(localized: "Vim terms", comment: "Vim key-name style: Vim's own words")
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
        "h": Curated(title: String(localized: "Left"), vim: VimTerms(keycap: "←", title: String(localized: "Left"))),
        "j": Curated(title: String(localized: "Down"), vim: VimTerms(keycap: "↓", title: String(localized: "Down"))),
        "k": Curated(title: String(localized: "Up"), vim: VimTerms(keycap: "↑", title: String(localized: "Up"))),
        "l": Curated(title: String(localized: "Right"), vim: VimTerms(keycap: "→", title: String(localized: "Right"))),
        "0": Curated(title: String(localized: "Line start"), vim: VimTerms(keycap: "0", title: String(localized: "Start of line"))),
        "4": Curated(title: String(localized: "Line end"), capLabel: "$", listLabel: "$", vim: VimTerms(keycap: "$", title: String(localized: "End of line"))),
        "a": Curated(title: String(localized: "Append"), shiftTitle: String(localized: "Append at line end"),
                     vim: VimTerms(keycap: "append", title: String(localized: "Append"), shiftTitle: String(localized: "Append at end of line"))),
        "g": Curated(title: String(localized: "Top of document"), listLabel: "gg", shiftTitle: String(localized: "Bottom of document"),
                     vim: VimTerms(keycap: "gg", title: String(localized: "Go to first line"), shiftTitle: String(localized: "Go to last line"))),
        "/": Curated(title: String(localized: "Find"), vim: VimTerms(keycap: "search", title: String(localized: "Search"))),
        "n": Curated(title: String(localized: "Next match"), shiftTitle: String(localized: "Previous match"),
                     vim: VimTerms(keycap: "next", title: String(localized: "Next match"), shiftTitle: String(localized: "Previous match"))),
        "y": Curated(title: String(localized: "Copy"), vim: VimTerms(keycap: "yank", title: String(localized: "Yank"))),
        "p": Curated(title: String(localized: "Paste"), vim: VimTerms(keycap: "put", title: String(localized: "Put"))),
        "x": Curated(title: String(localized: "Delete character"), vim: VimTerms(keycap: "del", title: String(localized: "Delete character"))),
        "r": Curated(title: String(localized: "Redo"), vim: VimTerms(keycap: "redo", title: String(localized: "Redo"))),
        "d": Curated(title: String(localized: "Delete previous word"), ctrlTitle: String(localized: "Page down"),
                     vim: VimTerms(keycap: "db", title: String(localized: "Delete word back"), ctrlTitle: String(localized: "Half page down"))),
        "u": Curated(title: String(localized: "Undo"), ctrlTitle: String(localized: "Page up"),
                     vim: VimTerms(keycap: "undo", title: String(localized: "Undo"), ctrlTitle: String(localized: "Half page up"))),
        "o": Curated(title: String(localized: "New line below"), shiftTitle: String(localized: "New line above"),
                     vim: VimTerms(keycap: "open", title: String(localized: "Open line below"), shiftTitle: String(localized: "Open line above"))),
        // Word motions (Neovim Terminal)
        "w": Curated(title: String(localized: "Next word"), vim: VimTerms(keycap: "word", title: String(localized: "Word forward"))),
        "b": Curated(title: String(localized: "Previous word"), vim: VimTerms(keycap: "back", title: String(localized: "Word back"))),
        "e": Curated(title: String(localized: "End of word"), vim: VimTerms(keycap: "end", title: String(localized: "End of word")))
    ]

    /// Keyed by the (localized) full title, so a lookup matches whatever `curated` produced.
    /// Built with `uniquingKeysWith` because two English titles may share one translation.
    private static let capTitles: [String: String] = Dictionary([
        (String(localized: "Line start"), String(localized: "Start", comment: "Vim keycap: start of line")),
        (String(localized: "Line end"), String(localized: "End", comment: "Vim keycap: end of line")),
        (String(localized: "Top of document"), String(localized: "Top", comment: "Vim keycap: top of document")),
        (String(localized: "Bottom of document"), String(localized: "Bottom", comment: "Vim keycap: bottom of document")),
        (String(localized: "Delete character"), String(localized: "Delete", comment: "Vim keycap: delete character")),
        (String(localized: "Delete previous word"), String(localized: "Del ←", comment: "Vim keycap: delete previous word")),
        (String(localized: "New line below"), String(localized: "Open", comment: "Vim keycap: new line below")),
        (String(localized: "New line above"), String(localized: "Open ↑", comment: "Vim keycap: new line above")),
        (String(localized: "Next match"), String(localized: "Next", comment: "Vim keycap: next search match")),
        (String(localized: "Previous match"), String(localized: "Prev", comment: "Vim keycap: previous search match")),
        (String(localized: "Append"), String(localized: "After", comment: "Vim keycap: append after cursor")),
        (String(localized: "Append at line end"), String(localized: "At end", comment: "Vim keycap: append at end of line")),
        (String(localized: "Page down"), String(localized: "Pg ↓", comment: "Vim keycap: page down")),
        (String(localized: "Page up"), String(localized: "Pg ↑", comment: "Vim keycap: page up")),
        (String(localized: "Next word"), String(localized: "Word →", comment: "Vim keycap: next word")),
        (String(localized: "Previous word"), String(localized: "← Word", comment: "Vim keycap: previous word")),
        (String(localized: "End of word"), String(localized: "Wd end", comment: "Vim keycap: end of word")),
        // Vim-terms variants: Vim's own notation for the shifted and Control forms.
        (String(localized: "Go to first line"), "gg"), (String(localized: "Go to last line"), "G"),
        (String(localized: "Append at end of line"), "A"), (String(localized: "Open line above"), "O"),
        (String(localized: "Half page down"), "⌃d"), (String(localized: "Half page up"), "⌃u"),
        (String(localized: "Start of line"), "0"), (String(localized: "End of line"), "$"),
        (String(localized: "Delete word back"), "db"), (String(localized: "Open line below"), "open"),
        (String(localized: "Word forward"), "word"), (String(localized: "Word back"), "back"),
        (String(localized: "Yank"), "yank"), (String(localized: "Put"), "put"), (String(localized: "Search"), "search")
    ], uniquingKeysWith: { first, _ in first })

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
                title: vim?.shiftTitle ?? known?.shiftTitle ?? String(localized: "Shifted: \(symbols(for: output))"),
                sends: symbols(for: output)
            )
        }
        let ctrl = mapping.ctrlOutput.map { output in
            VimLayerReferenceEntry.Variant(
                label: "⌃" + capLabel,
                title: vim?.ctrlTitle ?? known?.ctrlTitle ?? String(localized: "With Control: \(symbols(for: output))"),
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
                "bspc": "⌫", "del": "⌦", "pgup": String(localized: "Page Up"), "pgdn": String(localized: "Page Down"),
                "esc": "⎋", "tab": "⇥", "spc": String(localized: "Space", comment: "Key name: the space bar")
            ]
            let key = keys[text] ?? (text.count == 1 ? text.uppercased() : text)
            return prefix + key
        }.joined(separator: " ")
    }
}
