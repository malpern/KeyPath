import SwiftUI

/// Slide-over panels that can appear in the drawer
enum DrawerPanel {
    case launcherSettings // Launcher activation mode & history suggestions

    var title: String {
        switch self {
        case .launcherSettings: "Launcher Settings"
        }
    }
}

enum InspectorSection: String {
    case mapper
    case customRules // Only shown when custom rules exist
    case keyboard
    case layout
    case keycaps
    case sounds
    case launchers
}

extension InspectorSection {
    var isSettingsShelf: Bool {
        switch self {
        case .keycaps, .sounds, .keyboard, .layout:
            true
        case .mapper, .customRules, .launchers:
            false
        }
    }
}
