import AppKit
import KeyPathCore

/// Handles `keypath://` URL scheme routing.
///
/// Extracted from `AppDelegate.application(_:open:)` to keep URL handling logic
/// in a dedicated, testable type.
@MainActor
enum DeepLinkRouter {
    /// Process an array of URLs, dispatching any `keypath://` action URIs.
    static func handle(_ urls: [URL]) {
        AppLogger.shared.log("🔗 [DeepLinkRouter] Received \(urls.count) URL(s) to open")

        for url in urls {
            // Only handle keypath:// URLs
            guard url.scheme == KeyPathActionURI.scheme else {
                AppLogger.shared.log("⚠️ [DeepLinkRouter] Ignoring non-keypath URL: \(url.scheme ?? "nil")")
                continue
            }

            // Parse and dispatch
            if let actionURI = KeyPathActionURI(string: url.absoluteString) {
                AppLogger.shared.log("🎬 [DeepLinkRouter] Dispatching action: \(actionURI.action)")
                // Another app opened this link; it may come from a web page or a document.
                ActionDispatcher.shared.dispatch(actionURI, origin: .externalURL)
            } else {
                AppLogger.shared.log("⚠️ [DeepLinkRouter] Failed to parse URL as KeyPathActionURI")
                ActionDispatcher.shared.onError?(String(localized: "KeyPath couldn't read a keypath:// link from another app."))
            }
        }
    }
}
