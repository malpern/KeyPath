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
    /// Color for this entry's collection
    let color: Color
    /// Physical key code for sorting by position
    let keyCode: UInt16

    static func == (lhs: HUDKeyEntry, rhs: HUDKeyEntry) -> Bool {
        lhs.keycap == rhs.keycap && lhs.action == rhs.action && lhs.keyCode == rhs.keyCode
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

    static func == (lhs: HUDKeyGroup, rhs: HUDKeyGroup) -> Bool {
        lhs.name == rhs.name && lhs.entries == rhs.entries
    }
}

/// The style of content to display in the HUD
enum HUDContentStyle: Equatable {
    case defaultList
    case windowSnappingGrid
    case launcherIcons
    case symbolPicker
}
