import AppKit
import UniformTypeIdentifiers

/// Resolves icons for key actions: apps, folders, and scripts.
///
/// Uses `NSWorkspace` to locate apps and retrieve their icons.
/// Falls back to generic icons if actions cannot be found.
enum AppIconResolver {
    private nonisolated(unsafe) static var iconCache: [String: NSImage] = [:]

    /// Get icon for any key action type, using cache when available.
    static func icon(for action: KeyAction) -> NSImage? {
        let cacheKey = Self.cacheKey(for: action)
        if let cacheKey, let cached = iconCache[cacheKey] {
            return cached
        }

        let image: NSImage? = switch action {
        case let .launchApp(name, bundleId):
            appIcon(name: name, bundleId: bundleId)
        case .openURL:
            urlIcon()
        case let .openFolder(path, _):
            folderIcon(for: path)
        case let .runScript(path, _):
            scriptIcon(for: path)
        default:
            nil
        }

        if let cacheKey, let image {
            iconCache[cacheKey] = image
        }
        return image
    }

    /// Pre-warm the icon cache for a key action (called at startup).
    static func prewarmIcon(for action: KeyAction) {
        _ = icon(for: action)
    }

    private static func cacheKey(for action: KeyAction) -> String? {
        switch action {
        case let .launchApp(name, bundleId):
            "app:\(bundleId ?? name)"
        case let .openURL(url):
            "url:\(url)"
        case let .openFolder(path, _):
            "folder:\(path)"
        case let .runScript(path, _):
            "script:\(path)"
        default:
            nil
        }
    }

    // MARK: - App Icons

    /// Get icon for an app by name or bundle ID
    private static func appIcon(name: String, bundleId: String?) -> NSImage? {
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
            if Foundation.FileManager().fileExists(atPath: path) {
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
                if Foundation.FileManager().fileExists(atPath: path) {
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
        icon(for: .launchApp(name: name, bundleId: nil))
    }

    // MARK: - URL Icons

    /// Get generic URL/web icon
    private static func urlIcon() -> NSImage? {
        // Return Safari icon as default browser icon, or generic globe
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            return NSWorkspace.shared.icon(forFile: safariURL.path)
        }
        // Fallback to system globe icon
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "Website")
    }

    // MARK: - Folder Icons

    /// Get icon for a folder path
    static func folderIcon(for path: String) -> NSImage? {
        let expandedPath = (path as NSString).expandingTildeInPath

        // If folder exists, get its actual icon (may have custom icon)
        if Foundation.FileManager().fileExists(atPath: expandedPath) {
            return NSWorkspace.shared.icon(forFile: expandedPath)
        }

        // Fallback to generic folder icon
        return genericFolderIcon()
    }

    /// Get generic folder icon
    static func genericFolderIcon() -> NSImage {
        // UTType.folder is always available
        NSWorkspace.shared.icon(for: .folder)
    }

    // MARK: - Script Icons

    /// Get icon for a script file based on its type
    static func scriptIcon(for path: String) -> NSImage? {
        let expandedPath = (path as NSString).expandingTildeInPath
        let ext = URL(fileURLWithPath: expandedPath).pathExtension.lowercased()

        // If file exists, get its actual icon
        if Foundation.FileManager().fileExists(atPath: expandedPath) {
            return NSWorkspace.shared.icon(forFile: expandedPath)
        }

        // Return icon based on script type
        return scriptIconByType(extension: ext)
    }

    /// Get icon for a script by its extension
    private static func scriptIconByType(extension ext: String) -> NSImage? {
        switch ext {
        case "applescript", "scpt":
            // AppleScript icon - try Script Editor app first
            if let scriptEditorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScriptEditor2") {
                return NSWorkspace.shared.icon(forFile: scriptEditorURL.path)
            }
            // Fallback to UTType icon
            if let appleScriptType = UTType(filenameExtension: "scpt") {
                return NSWorkspace.shared.icon(for: appleScriptType)
            }
            return nil

        case "sh", "bash", "zsh":
            // Shell script icon
            return NSWorkspace.shared.icon(for: .shellScript)

        default:
            // Generic executable icon
            return NSWorkspace.shared.icon(for: .unixExecutable)
        }
    }

    /// Get generic script icon
    static func genericScriptIcon() -> NSImage {
        NSWorkspace.shared.icon(for: .shellScript)
    }

    // MARK: - Name Variations

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
