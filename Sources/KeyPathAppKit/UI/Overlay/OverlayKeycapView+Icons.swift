import AppKit
import SwiftUI

extension OverlayKeycapView {
    // MARK: - App Icon Loading

    /// Load app icon for launch action if needed (via IconResolverService)
    func loadAppIconIfNeeded() {
        // Check layer-based app launch first
        if let appIdentifier = layerKeyInfo?.appLaunchIdentifier {
            appIcon = IconResolverService.shared.resolveAppIcon(for: appIdentifier)
            return
        }

        // Check launcher mapping for app target
        if let mapping = launcherMapping, case let .app(name, bundleId) = mapping.target {
            appIcon = AppIconResolver.icon(for: .app(name: name, bundleId: bundleId))
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
                faviconImage = await IconResolverService.shared.resolveFavicon(for: url)
            }
            return
        }

        // Check launcher mapping for URL target
        if let mapping = launcherMapping, case let .url(urlString) = mapping.target {
            Task { @MainActor in
                faviconImage = await IconResolverService.shared.resolveFavicon(for: urlString)
            }
            return
        }

        faviconImage = nil
    }
}
