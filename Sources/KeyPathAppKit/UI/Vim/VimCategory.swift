import SwiftUI

enum VimCategory: String, CaseIterable, Identifiable {
    case navigation
    case editing
    case search
    case clipboard

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .navigation: String(localized: "Move", comment: "Vim command category")
        case .editing: String(localized: "Edit", comment: "Vim command category")
        case .search: String(localized: "Search", comment: "Vim command category")
        case .clipboard: String(localized: "Clipboard", comment: "Vim command category")
        }
    }

    var icon: String {
        switch self {
        case .navigation: "arrow.up.arrow.down"
        case .editing: "scissors"
        case .search: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var commandInputs: [String] {
        switch self {
        case .navigation: ["h", "j", "k", "l", "w", "b", "e", "0", "4", "a", "g"]
        case .editing: ["x", "r", "d", "u", "o"]
        case .search: ["/", "n"]
        case .clipboard: ["y", "p"]
        }
    }

    /// Every Vim key uses the overlay's navigation color, so a key looks the same in
    /// Settings, the Shortcut List and the overlay. Groups differ by heading and icon.
    var accentColor: Color {
        KeyPathColors.layerGreen
    }
}
