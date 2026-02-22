import SwiftUI

/// A single key entry in the Context HUD
struct HUDKeyEntry: Identifiable, Equatable {
    let id = UUID()
    /// The keycap label (e.g., "H", "J", "K", "L")
    let keycap: String
    /// The action description (e.g., "Left", "Down", "Up", "Right")
    let action: String
    /// SF Symbol name for the action, if available
    let sfSymbol: String?
    /// App bundle identifier for app launch actions
    let appIdentifier: String?
    /// URL identifier for web URL actions
    let urlIdentifier: String?
    /// Hold action label for tap-hold keys (e.g., "✦" for Hyper)
    let holdAction: String?
    /// Color for this entry's collection
    let color: Color
    /// Physical key code for sorting by position
    let keyCode: UInt16

    static func == (lhs: HUDKeyEntry, rhs: HUDKeyEntry) -> Bool {
        lhs.keycap == rhs.keycap && lhs.action == rhs.action && lhs.holdAction == rhs.holdAction && lhs.keyCode == rhs.keyCode
    }
}

/// A group of key entries from the same collection
struct HUDKeyGroup: Identifiable, Equatable {
    let id = UUID()
    /// Collection name (e.g., "Vim Navigation", "Window Snapping")
    let name: String
    /// Collection color
    let color: Color
    /// Entries in this group, sorted by key position
    let entries: [HUDKeyEntry]
    /// Sort order for display (sub-groups get explicit order; default 0)
    let sortOrder: Int

    init(name: String, color: Color, entries: [HUDKeyEntry], sortOrder: Int = 0) {
        self.name = name
        self.color = color
        self.entries = entries
        self.sortOrder = sortOrder
    }

    static func == (lhs: HUDKeyGroup, rhs: HUDKeyGroup) -> Bool {
        lhs.name == rhs.name && lhs.entries == rhs.entries && lhs.sortOrder == rhs.sortOrder
    }
}

/// The style of content to display in the HUD
enum HUDContentStyle: Equatable {
    case defaultList
    case windowSnappingGrid
    case launcherIcons
    case symbolPicker
    case kindaVimLearning
}
