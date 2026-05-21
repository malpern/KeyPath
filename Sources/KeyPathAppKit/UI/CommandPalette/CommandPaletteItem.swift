import AppKit

struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let shortcut: String?
    let group: String
    let action: () -> Void

    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let lower = query.lowercased()
        return title.lowercased().contains(lower)
            || (subtitle?.lowercased().contains(lower) ?? false)
            || group.lowercased().contains(lower)
    }
}

struct CommandPaletteGroup: Identifiable {
    let id: String
    let items: [CommandPaletteItem]
}
