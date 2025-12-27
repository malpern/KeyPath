import AppKit

/// Resolves app icons from bundle identifiers or app names.
///
/// Uses `NSWorkspace` to locate apps and retrieve their icons.
/// Falls back to generic app icon if app cannot be found.
enum AppIconResolver {
    /// Get icon for an app by name or bundle ID
    static func icon(for target: LauncherTarget) -> NSImage? {
        guard case let .app(name, bundleId) = target else { return nil }

        // Try bundle ID first (most reliable)
        if let bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        // Fall back to app name search in common locations
        let searchPaths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app"
        ]

        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }

        // Try variations of the name (e.g., "VS Code" -> "Visual Studio Code")
        let nameVariations = Self.nameVariations(for: name)
        for variation in nameVariations {
            let paths = [
                "/Applications/\(variation).app",
                "/System/Applications/\(variation).app"
            ]
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    return NSWorkspace.shared.icon(forFile: path)
                }
            }
        }

        return nil // Fall back to generic app icon in UI
    }

    /// Get icon for a bundle identifier directly
    static func icon(forBundleIdentifier bundleId: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    /// Get icon for an app by name
    static func icon(forAppName name: String) -> NSImage? {
        icon(for: .app(name: name, bundleId: nil))
    }

    /// Common name variations for apps
    private static func nameVariations(for name: String) -> [String] {
        switch name.lowercased() {
        case "vs code", "vscode":
            ["Visual Studio Code"]
        case "chrome":
            ["Google Chrome"]
        case "edge":
            ["Microsoft Edge"]
        case "word":
            ["Microsoft Word"]
        case "excel":
            ["Microsoft Excel"]
        case "powerpoint":
            ["Microsoft PowerPoint"]
        case "teams":
            ["Microsoft Teams"]
        case "outlook":
            ["Microsoft Outlook"]
        case "figma":
            ["Figma"]
        case "1password":
            ["1Password 7", "1Password"]
        case "arc":
            ["Arc"]
        case "dia":
            ["Dia"]
        default:
            []
        }
    }
}
