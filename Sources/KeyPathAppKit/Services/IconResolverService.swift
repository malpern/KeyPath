import AppKit
import Foundation
import KeyPathCore

/// Unified service for resolving icons for keycap display
///
/// Consolidates all icon lookup logic previously scattered across OverlayKeycapView:
/// - App icons (via NSWorkspace)
/// - System action icons (SF Symbols)
/// - URL favicons (delegates to FaviconFetcher)
/// - Custom icons from KeyIconRegistry (for push-msg "icon:name")
///
/// Usage:
/// ```swift
/// let icon = await IconResolverService.shared.resolveAppIcon(for: "Safari")
/// let symbol = IconResolverService.shared.systemActionSymbol(for: "spotlight")
/// ```
@MainActor
final class IconResolverService {
    static let shared = IconResolverService()

    // MARK: - Cache

    /// In-memory cache for app icons (keyed by identifier)
    private var appIconCache: [String: NSImage] = [:]

    // MARK: - App Icon Resolution

    /// Resolve app icon by bundle identifier or app name
    /// - Parameter identifier: Bundle ID (e.g., "com.apple.Safari") or app name (e.g., "Safari")
    /// - Returns: App icon as NSImage, or nil if not found
    func resolveAppIcon(for identifier: String) -> NSImage? {
        // Check cache first
        if let cached = appIconCache[identifier] {
            return cached
        }

        // Find app URL
        guard let appURL = findAppURL(for: identifier) else {
            return nil
        }

        // Load icon from NSWorkspace
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)

        // Cache and return
        appIconCache[identifier] = icon
        AppLogger.shared.debug("🖼️ [IconResolver] Cached app icon for \(identifier)")
        return icon
    }

    /// Find app URL by bundle identifier or name
    /// Searches in order: bundle ID → /Applications/Name.app → /Applications/Capitalized.app
    private func findAppURL(for identifier: String) -> URL? {
        // Try bundle identifier first (most reliable)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return url
        }

        // Try app name in /Applications
        let directPath = "/Applications/\(identifier).app"
        if FileManager.default.fileExists(atPath: directPath) {
            return URL(fileURLWithPath: directPath)
        }

        // Try with capitalized first letter
        let capitalizedPath = "/Applications/\(identifier.capitalized).app"
        if FileManager.default.fileExists(atPath: capitalizedPath) {
            return URL(fileURLWithPath: capitalizedPath)
        }

        return nil
    }

    // MARK: - System Action Resolution

    /// System action ID to SF Symbol mapping
    /// Used for keys mapped to system actions like Spotlight, Mission Control, etc.
    private static let systemActionSymbols: [String: String] = [
        // Spotlight
        "spotlight": "magnifyingglass",

        // Mission Control / Spaces
        "mission-control": "rectangle.3.group",
        "missioncontrol": "rectangle.3.group",

        // Launchpad
        "launchpad": "square.grid.3x3",

        // Do Not Disturb
        "dnd": "moon.fill",
        "do-not-disturb": "moon.fill",
        "donotdisturb": "moon.fill",

        // Notification Center
        "notification-center": "bell.fill",
        "notificationcenter": "bell.fill",

        // Dictation
        "dictation": "mic.fill",

        // Siri
        "siri": "waveform.circle.fill"
    ]

    /// Resolve SF Symbol name for a system action ID
    /// - Parameter actionId: System action identifier (e.g., "spotlight", "mission-control")
    /// - Returns: SF Symbol name, or nil if not a recognized system action
    func systemActionSymbol(for actionId: String) -> String? {
        Self.systemActionSymbols[actionId.lowercased()]
    }

    // MARK: - URL Favicon Resolution

    /// Resolve favicon for a URL
    /// Delegates to FaviconFetcher which handles caching and network fetching
    /// - Parameter url: URL string (e.g., "github.com", "https://example.com")
    /// - Returns: Favicon as NSImage, or nil if fetch failed
    func resolveFavicon(for url: String) async -> NSImage? {
        await FaviconFetcher.shared.fetchFavicon(for: url)
    }

    // MARK: - Custom Icon Resolution (KeyIconRegistry)

    /// Resolve custom icon from KeyIconRegistry by name
    /// Used for push-msg "icon:name" feature (see ADR-024)
    /// - Parameter name: Icon name from push-msg (e.g., "arrow-left", "safari")
    /// - Returns: Icon source (SF Symbol, app icon, or text fallback)
    func resolveCustomIcon(named name: String) -> KeyIconSource {
        KeyIconRegistry.resolve(name)
    }

    /// Resolve custom icon to displayable NSImage
    /// - Parameter name: Icon name from push-msg
    /// - Returns: NSImage if resolvable, nil otherwise
    func resolveCustomIconImage(named name: String) async -> NSImage? {
        let source = resolveCustomIcon(named: name)

        switch source {
        case let .sfSymbol(symbolName):
            // Create NSImage from SF Symbol
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: name)

        case let .appIcon(appName):
            // Resolve app icon
            return resolveAppIcon(for: appName)

        case .text:
            // Text fallback - caller should handle this case
            return nil
        }
    }

    // MARK: - Pre-loading

    /// Pre-load app icons and favicons for all launcher mappings
    /// Call this on app startup to ensure icons are cached before user enters launcher mode
    func preloadLauncherIcons() async {
        let collections = await RuleCollectionStore.shared.loadCollections()

        guard let launcher = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
              let config = launcher.configuration.launcherGridConfig
        else {
            AppLogger.shared.debug("🖼️ [IconResolver] No launcher collection found for preloading")
            return
        }

        let enabledMappings = config.mappings.filter(\.isEnabled)
        AppLogger.shared.log("🖼️ [IconResolver] Preloading \(enabledMappings.count) launcher icons...")

        for mapping in enabledMappings {
            await preloadIcon(for: mapping.target)
        }

        AppLogger.shared.log("🖼️ [IconResolver] Launcher icon preload complete")
    }

    /// Pre-load icons for all layer-based app launches and URLs
    /// Call this on app startup to ensure layer icons are cached
    func preloadLayerIcons(from collections: [RuleCollection]) async {
        var appCount = 0
        var urlCount = 0

        for collection in collections where collection.isEnabled {
            for mapping in collection.mappings {
                let output = mapping.output.lowercased()

                // Check for app launch: (push-msg "launch:AppName")
                if output.contains("launch:") {
                    if let appName = extractAppName(from: mapping.output) {
                        _ = resolveAppIcon(for: appName)
                        appCount += 1
                    }
                }

                // Check for URL open: (push-msg "open:domain.com")
                if output.contains("open:") {
                    if let url = extractUrl(from: mapping.output) {
                        _ = await resolveFavicon(for: url)
                        urlCount += 1
                    }
                }
            }
        }

        if appCount > 0 || urlCount > 0 {
            AppLogger.shared.log("🖼️ [IconResolver] Layer icon preload complete: \(appCount) apps, \(urlCount) URLs")
        }
    }

    /// Pre-load a single icon (for cache warming on collection change)
    func preloadIcon(for target: LauncherTarget) async {
        switch target {
        case let .app(name, bundleId):
            let identifier = bundleId ?? name
            _ = resolveAppIcon(for: identifier)
        case let .url(urlString):
            _ = await resolveFavicon(for: urlString)
        case let .folder(path, _):
            // Folder icons are resolved synchronously by NSWorkspace
            _ = AppIconResolver.folderIcon(for: path)
        case let .script(path, _):
            // Script icons are resolved synchronously by NSWorkspace
            _ = AppIconResolver.scriptIcon(for: path)
        }
    }

    // MARK: - Helper Methods

    /// Extract app name from push-msg output: (push-msg "launch:AppName")
    /// Delegates to KeyboardVisualizationViewModel's cached regex implementation
    private func extractAppName(from output: String) -> String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: output)
    }

    /// Extract URL from push-msg output: (push-msg "open:domain.com")
    /// Delegates to KeyboardVisualizationViewModel's cached regex implementation
    private func extractUrl(from output: String) -> String? {
        KeyboardVisualizationViewModel.extractUrlIdentifier(from: output)
    }

    // MARK: - Cache Management

    /// Clear all cached app icons
    func clearAppIconCache() {
        appIconCache.removeAll()
        AppLogger.shared.log("🧹 [IconResolver] Cleared app icon cache")
    }

    /// Clear all caches (app icons + favicons)
    func clearAllCaches() {
        clearAppIconCache()
        FaviconFetcher.shared.clearCache()
    }

    // MARK: - Init

    private init() {
        AppLogger.shared.debug("🖼️ [IconResolver] Service initialized")
    }
}
