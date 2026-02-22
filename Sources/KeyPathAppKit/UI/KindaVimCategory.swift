import SwiftUI

enum KindaVimCategory: String, CaseIterable, Identifiable {
    case movement
    case wordMotion
    case editing
    case search
    case clipboard

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .movement: "Movement"
        case .wordMotion: "Word Motion"
        case .editing: "Editing"
        case .search: "Search"
        case .clipboard: "Clipboard"
        }
    }

    var icon: String {
        switch self {
        case .movement: "arrow.up.arrow.down"
        case .wordMotion: "textformat.abc"
        case .editing: "scissors"
        case .search: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var commandInputs: [String] {
        switch self {
        case .movement: ["h", "j", "k", "l", "0", "4", "a", "g"]
        case .wordMotion: ["w", "b", "e"]
        case .editing: ["x", "r", "d", "u", "o"]
        case .search: ["/", "n"]
        case .clipboard: ["y", "p"]
        }
    }

    var accentColor: Color {
        switch self {
        case .movement: .blue
        case .wordMotion: .teal
        case .editing: .orange
        case .search: .purple
        case .clipboard: .green
        }
    }
}
