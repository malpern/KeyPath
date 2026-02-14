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
        case .navigation: "Navigation"
        case .editing: "Editing"
        case .search: "Search"
        case .clipboard: "Clipboard"
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
        case .navigation: ["h", "j", "k", "l", "0", "4", "a", "g"]
        case .editing: ["x", "r", "d", "u", "o"]
        case .search: ["/", "n"]
        case .clipboard: ["y", "p"]
        }
    }

    var accentColor: Color {
        switch self {
        case .navigation: .blue
        case .editing: .orange
        case .search: .purple
        case .clipboard: .green
        }
    }
}
