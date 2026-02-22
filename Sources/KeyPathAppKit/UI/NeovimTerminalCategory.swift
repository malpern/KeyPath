import SwiftUI

/// Categories for the Neovim Terminal quick-reference HUD.
/// Focused on core motions and basic window navigation.
enum NeovimTerminalCategory: String, CaseIterable, Identifiable {
    case movement
    case windowNavigation
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movement: "Movement"
        case .windowNavigation: "Window Navigation"
        case .search: "Search"
        }
    }

    var icon: String {
        switch self {
        case .movement: "arrow.up.left.and.arrow.down.right"
        case .windowNavigation: "rectangle.split.2x2"
        case .search: "magnifyingglass"
        }
    }

    var accentColor: Color {
        switch self {
        case .movement: .blue
        case .windowNavigation: .indigo
        case .search: .purple
        }
    }

    var isNeovimSpecific: Bool {
        switch self {
        case .windowNavigation:
            true
        case .movement, .search:
            false
        }
    }
}
