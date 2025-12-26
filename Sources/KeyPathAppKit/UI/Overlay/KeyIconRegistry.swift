import AppKit
import SwiftUI

/// Source for a custom key icon in the overlay
enum KeyIconSource {
    case sfSymbol(String) // SF Symbol name -> Image(systemName:)
    case appIcon(String) // App name -> NSWorkspace icon lookup
    case text(String) // Fallback to text label
}

/// Registry mapping icon names to their visual sources
/// Used by keyboard overlay to display custom icons on keys via push-msg
enum KeyIconRegistry {
    /// Built-in icon mappings
    /// Users trigger these via: (push-msg "icon:arrow-left")
    static let registry: [String: KeyIconSource] = [
        // MARK: - Navigation (SF Symbols)

        "arrow-left": .sfSymbol("arrow.left"),
        "arrow-right": .sfSymbol("arrow.right"),
        "arrow-up": .sfSymbol("arrow.up"),
        "arrow-down": .sfSymbol("arrow.down"),
        "home": .sfSymbol("house"),
        "end": .sfSymbol("arrow.down.to.line"),
        "page-up": .sfSymbol("arrow.up.doc"),
        "page-down": .sfSymbol("arrow.down.doc"),

        // MARK: - Editing (SF Symbols)

        "delete": .sfSymbol("delete.left"),
        "forward-delete": .sfSymbol("delete.right"),
        "cut": .sfSymbol("scissors"),
        "copy": .sfSymbol("doc.on.doc"),
        "paste": .sfSymbol("doc.on.clipboard"),
        "undo": .sfSymbol("arrow.uturn.backward"),
        "redo": .sfSymbol("arrow.uturn.forward"),

        // MARK: - Media (SF Symbols)

        "play": .sfSymbol("play.fill"),
        "pause": .sfSymbol("pause.fill"),
        "stop": .sfSymbol("stop.fill"),
        "next": .sfSymbol("forward.fill"),
        "previous": .sfSymbol("backward.fill"),
        "volume-up": .sfSymbol("speaker.wave.3.fill"),
        "volume-down": .sfSymbol("speaker.wave.1.fill"),
        "mute": .sfSymbol("speaker.slash.fill"),

        // MARK: - System (SF Symbols)

        "brightness-up": .sfSymbol("sun.max.fill"),
        "brightness-down": .sfSymbol("sun.min.fill"),
        "lock": .sfSymbol("lock.fill"),
        "unlock": .sfSymbol("lock.open.fill"),
        "search": .sfSymbol("magnifyingglass"),
        "settings": .sfSymbol("gearshape.fill"),

        // MARK: - Common Apps (resolved via NSWorkspace)

        "safari": .appIcon("Safari"),
        "terminal": .appIcon("Terminal"),
        "obsidian": .appIcon("Obsidian"),
        "finder": .appIcon("Finder"),
        "mail": .appIcon("Mail"),
        "messages": .appIcon("Messages"),
        "calendar": .appIcon("Calendar"),
        "notes": .appIcon("Notes"),
        "reminders": .appIcon("Reminders"),
        "music": .appIcon("Music"),
        "photos": .appIcon("Photos"),
        "xcode": .appIcon("Xcode"),
        "vscode": .appIcon("Visual Studio Code"),
        "slack": .appIcon("Slack"),
        "discord": .appIcon("Discord"),
        "chrome": .appIcon("Google Chrome"),
        "firefox": .appIcon("Firefox")
    ]

    /// Resolve an icon name to its source
    /// - Parameter name: Icon name from push-msg (e.g., "arrow-left", "safari")
    /// - Returns: Icon source, or text fallback if not found
    static func resolve(_ name: String) -> KeyIconSource {
        registry[name] ?? .text(name)
    }
}
