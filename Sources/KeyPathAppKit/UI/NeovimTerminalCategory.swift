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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basicMotions: "Basic Motions"
        case .operators: "Operators"
        case .textObjects: "Text Objects"
        case .windowNavigation: "Window Navigation"
        case .buffersTabs: "Buffers & Tabs"
        case .lsp: "LSP"
        case .telescope: "Telescope"
        case .terminalMode: "Terminal Mode"
        case .search: "Search"
        }
    }

    var detail: String {
        switch self {
        case .basicMotions: "h/j/k/l, w/b/e, 0/$, gg/G, f/t"
        case .operators: "d, c, y, >, <, ="
        case .textObjects: "iw/aw, ip/ap, i\"/a\""
        case .windowNavigation: "Ctrl-w split + focus commands"
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

    var accentColor: Color {
        switch self {
        case .basicMotions: .blue
        case .operators: .orange
        case .textObjects: .pink
        case .windowNavigation: .indigo
        case .buffersTabs: .teal
        case .lsp: .mint
        case .telescope: .cyan
        case .terminalMode: .gray
        case .search: .purple
        }
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
                .init(keys: "h j k l", meaning: "left/down/up/right"),
                .init(keys: "w b e", meaning: "word motions"),
                .init(keys: "0  $", meaning: "line start/end"),
                .init(keys: "gg  G", meaning: "file start/end"),
                .init(keys: "f  t", meaning: "find/till char"),
            ]
        case .operators:
            [
                .init(keys: "d  c  y", meaning: "delete/change/yank"),
                .init(keys: ">  <  =", meaning: "indent/outdent/reindent"),
            ]
        case .textObjects:
            [
                .init(keys: "iw  aw", meaning: "inner/a word"),
                .init(keys: "ip  ap", meaning: "inner/a paragraph"),
                .init(keys: "i\"  a\"", meaning: "inner/a quoted string"),
            ]
        case .windowNavigation:
            [
                .init(keys: "⌃ w h/j/k/l", meaning: "focus split left/down/up/right"),
                .init(keys: "⌃ w v  /  s", meaning: "split vertical / horizontal"),
                .init(keys: "⌃ w =", meaning: "equalize split sizes"),
                .init(keys: "⌃ w q", meaning: "close current split"),
            ]
        case .buffersTabs:
            [
                .init(keys: ":bn  :bp  :bd", meaning: "next/prev/delete buffer"),
                .init(keys: "gt  gT", meaning: "next/prev tab"),
                .init(keys: "Ctrl-^", meaning: "alternate buffer"),
            ]
        case .lsp:
            [
                .init(keys: "gd  gr", meaning: "go to def / references"),
                .init(keys: "K", meaning: "hover docs"),
                .init(keys: "<leader>rn", meaning: "rename symbol"),
                .init(keys: "<leader>ca", meaning: "code actions"),
            ]
        case .telescope:
            [
                .init(keys: "<leader>ff", meaning: "find files"),
                .init(keys: "<leader>fg", meaning: "live grep"),
                .init(keys: "<leader>fb", meaning: "buffers"),
                .init(keys: "<leader>fh", meaning: "help tags"),
            ]
        case .terminalMode:
            [
                .init(keys: ":terminal", meaning: "open terminal buffer"),
                .init(keys: "Ctrl-\\ Ctrl-n", meaning: "terminal → normal mode"),
                .init(keys: "i", meaning: "normal → terminal insert"),
            ]
        case .search:
            [
                .init(keys: "/  ?", meaning: "search fwd/back"),
                .init(keys: "n  N", meaning: "next/prev match"),
                .init(keys: "*  #", meaning: "word under cursor"),
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

    var id: String { "\(keys)-\(meaning)" }
}
