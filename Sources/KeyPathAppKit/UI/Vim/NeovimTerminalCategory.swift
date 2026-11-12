import SwiftUI

/// Categories for the Neovim Terminal quick-reference HUD.
/// These are educational topics only (not active key-mapping features).
enum NeovimTerminalCategory: String, CaseIterable, Identifiable {
    case basicMotions
    case operators
    case textObjects
    case windowNavigation
    case buffersTabs
    case lsp
    case telescope
    case terminalMode
    case search

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .basicMotions: String(localized: "Basic Motions")
        case .operators: String(localized: "Operators")
        case .textObjects: String(localized: "Text Objects")
        case .windowNavigation: String(localized: "Window Navigation")
        case .buffersTabs: String(localized: "Buffers & Tabs")
        case .lsp: "LSP"
        case .telescope: "Telescope"
        case .terminalMode: String(localized: "Terminal Mode")
        case .search: String(localized: "Search", comment: "Neovim reference category")
        }
    }

    var detail: String {
        switch self {
        case .basicMotions: "h/j/k/l, w/b/e, 0/$, gg/G, f/t"
        case .operators: "d, c, y, >, <, ="
        case .textObjects: "iw/aw, ip/ap, i\"/a\""
        case .windowNavigation: String(localized: "Ctrl-w split + focus commands")
        case .buffersTabs: ":bn/:bp/:bd, gt/gT, Ctrl-^"
        case .lsp: "gd, gr, K, <leader>rn, <leader>ca"
        case .telescope: "<leader>ff, fg, fb, fh"
        case .terminalMode: ":terminal, Ctrl-\\ Ctrl-n, i"
        case .search: "/, ?, n/N, */#"
        }
    }

    var icon: String {
        switch self {
        case .basicMotions: "arrow.up.left.and.arrow.down.right"
        case .operators: "wand.and.stars"
        case .textObjects: "quote.opening"
        case .windowNavigation: "rectangle.split.2x2"
        case .buffersTabs: "rectangle.stack"
        case .lsp: "dot.radiowaves.left.and.right"
        case .telescope: "scope"
        case .terminalMode: "terminal"
        case .search: "magnifyingglass"
        }
    }

    /// One color for the pack: the overlay's editor blue (KeycapSymbols.LayerColors.editor),
    /// so Settings, the terminal cheat sheet and the overlay agree. Topics differ by
    /// title and icon, not by hue.
    var accentColor: Color {
        KeyPathColors.layerBlue
    }

    var isNeovimSpecific: Bool {
        switch self {
        case .windowNavigation, .buffersTabs, .lsp, .telescope, .terminalMode:
            true
        case .basicMotions, .operators, .textObjects, .search:
            false
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .basicMotions, .operators, .textObjects, .windowNavigation:
            true
        case .buffersTabs, .lsp, .telescope, .terminalMode, .search:
            false
        }
    }

    var commands: [NeovimReferenceCommand] {
        switch self {
        case .basicMotions:
            [
                .init(keys: "h j k l", meaning: String(localized: "left/down/up/right", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "w b e", meaning: String(localized: "word motions", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "0  $", meaning: String(localized: "line start/end", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "gg  G", meaning: String(localized: "file start/end", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "f  t", meaning: String(localized: "find/till char", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .operators:
            [
                .init(keys: "d  c  y", meaning: String(localized: "delete/change/yank", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: ">  <  =", meaning: String(localized: "indent/outdent/reindent", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .textObjects:
            [
                .init(keys: "iw  aw", meaning: String(localized: "inner/a word", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "ip  ap", meaning: String(localized: "inner/a paragraph", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "i\"  a\"", meaning: String(localized: "inner/a quoted string", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .windowNavigation:
            [
                .init(keys: "⌃ w h/j/k/l", meaning: String(localized: "focus split left/down/up/right", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "⌃ w v  /  s", meaning: String(localized: "split vertical / horizontal", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "⌃ w =", meaning: String(localized: "equalize split sizes", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "⌃ w q", meaning: String(localized: "close current split", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .buffersTabs:
            [
                .init(keys: ":bn  :bp  :bd", meaning: String(localized: "next/prev/delete buffer", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "gt  gT", meaning: String(localized: "next/prev tab", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "Ctrl-^", meaning: String(localized: "alternate buffer", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .lsp:
            [
                .init(keys: "gd  gr", meaning: String(localized: "go to def / references", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "K", meaning: String(localized: "hover docs", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "<leader>rn", meaning: String(localized: "rename symbol", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "<leader>ca", meaning: String(localized: "code actions", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .telescope:
            [
                .init(keys: "<leader>ff", meaning: String(localized: "find files", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "<leader>fg", meaning: String(localized: "live grep", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "<leader>fb", meaning: String(localized: "buffers", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "<leader>fh", meaning: String(localized: "help tags", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .terminalMode:
            [
                .init(keys: ":terminal", meaning: String(localized: "open terminal buffer", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "Ctrl-\\ Ctrl-n", meaning: String(localized: "terminal → normal mode", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "i", meaning: String(localized: "normal → terminal insert", comment: "Vim command meaning, shown next to its keys")),
            ]
        case .search:
            [
                .init(keys: "/  ?", meaning: String(localized: "search fwd/back", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "n  N", meaning: String(localized: "next/prev match", comment: "Vim command meaning, shown next to its keys")),
                .init(keys: "*  #", meaning: String(localized: "word under cursor", comment: "Vim command meaning, shown next to its keys")),
            ]
        }
    }

    static var defaultRawValues: Set<String> {
        Set(allCases.filter(\.defaultEnabled).map(\.rawValue))
    }
}

struct NeovimReferenceCommand: Identifiable {
    let keys: String
    let meaning: String

    var id: String {
        "\(keys)-\(meaning)"
    }
}
