import AppKit
import UniformTypeIdentifiers

/// Resolves icons for launcher targets: apps, folders, and scripts.
///
/// Uses `NSWorkspace` to locate apps and retrieve their icons.
/// Falls back to generic icons if targets cannot be found.
enum AppIconResolver {
    /// Get icon for any launcher target type
    static func icon(for target: LauncherTarget) -> NSImage? {
        switch target {
        case let .app(name, bundleId):
            appIcon(name: name, bundleId: bundleId)
        case .url:
            urlIcon()
        case let .folder(path, _):
            folderIcon(for: path)
        case let .script(path, _):
            scriptIcon(for: path)
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
        if FileManager.default.fileExists(atPath: expandedPath) {
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
        if FileManager.default.fileExists(atPath: expandedPath) {
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
