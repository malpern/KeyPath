import Foundation
import KeyPathCore

/// What a `keypath://` link opened by another app may do.
///
/// Raycast, Alfred, Hammerspoon and Terminal open these links on purpose, so
/// most actions stay available. A web page or a document can open them too,
/// so the actions that could run code, reach local files, or fire a macro are
/// limited:
///
/// - `script` never runs from a link. Scripts run from a key binding or from
///   the Send KeyPath Action shortcut.
/// - `open` opens only web pages (http and https).
/// - `fakekey` / `vkey` asks first, unless the user chose "Always Allow".
enum ExternalActionPolicy {
    enum Decision: Equatable {
        case allow
        case refuse(String)
        case confirm(summary: String, alwaysAllowKey: String)
    }

    /// Set when the user chooses "Always Allow" for virtual keys from other apps.
    static let allowLinkedVirtualKeysKey = "KeyPath.Security.AllowLinkedVirtualKeys"

    static func decision(for uri: KeyPathActionURI, defaults: UserDefaults) -> Decision {
        switch uri.action {
        case "script":
            return .refuse(String(localized: "Scripts can't be started by a link from another app. Bind the script to a key, or run it with the Send KeyPath Action shortcut."))
        case "open":
            guard let url = openTarget(uri), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                return .refuse(String(localized: "Links from other apps can only open web pages."))
            }
            return .allow
        case "fakekey", "vkey":
            if defaults.bool(forKey: allowLinkedVirtualKeysKey) { return .allow }
            let name = uri.target ?? "?"
            return .confirm(
                summary: String(localized: "press the virtual key “\(name)”"),
                alwaysAllowKey: allowLinkedVirtualKeysKey
            )
        default:
            return .allow
        }
    }

    /// The URL `keypath://open/…` would open, normalised the same way as the handler.
    static func openTarget(_ uri: KeyPathActionURI) -> URL? {
        let raw = uri.pathComponents.joined(separator: "/")
        guard !raw.isEmpty else { return nil }
        var string = raw.removingPercentEncoding ?? raw
        if !string.contains("://") { string = "https://\(string)" }
        return URL(string: string)
    }

    /// An app name or bundle ID, never a path.
    static func isPlainAppName(_ name: String) -> Bool {
        !name.contains("/") && !name.contains("..")
    }
}
