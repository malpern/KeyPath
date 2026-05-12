import AppKit
import SwiftUI

extension OverlayKeycapView {
    // MARK: - App Icon Loading

    /// Load app icon for launch action if needed (via IconResolverService)
    func loadAppIconIfNeeded() {
        // Check for custom icon on launcher mapping first
        if let mapping = launcherMapping, let iconPath = mapping.customIconPath {
            let expanded = (iconPath as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                img.size = NSSize(width: 32, height: 32)
                appIcon = img
                return
            }
        }

        // Check layer-based app launch first
        if let appIdentifier = layerKeyInfo?.appLaunchIdentifier {
            appIcon = services.iconResolver.resolveAppIcon(for: appIdentifier)
            return
        }

        // Check launcher mapping for app target
        if let mapping = launcherMapping, case let .launchApp(name, bundleId) = mapping.action {
            appIcon = AppIconResolver.icon(for: .launchApp(name: name, bundleId: bundleId))
            return
        }

        appIcon = nil
    }

    // MARK: - Favicon Loading

    /// Load favicon for URL action if needed (via IconResolverService)
    func loadFaviconIfNeeded() {
        // Check layer-based URL first
        if let url = layerKeyInfo?.urlIdentifier {
            Task { @MainActor in
                faviconImage = await services.iconResolver.resolveFavicon(for: url)
            }
            return
        }

        // Check launcher mapping for URL target
        if let mapping = launcherMapping, case let .openURL(urlString) = mapping.action {
            Task { @MainActor in
                faviconImage = await services.iconResolver.resolveFavicon(for: urlString)
            }
            return
        }

        faviconImage = nil
    }
}
