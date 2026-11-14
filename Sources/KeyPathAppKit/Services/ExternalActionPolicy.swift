import Foundation
import KeyPathCore

/// Choices the user made about links from other apps.
@MainActor
public protocol LinkGrantStore: AnyObject {
    /// Whether links from other apps may press virtual keys without asking.
    var allowsVirtualKeys: Bool { get }
    /// Returns false when the choice could not be saved.
    func setAllowsVirtualKeys(_ allowed: Bool) -> Bool
}

/// Keeps the choice in the Keychain, where another process cannot set it silently.
@MainActor
public final class KeychainLinkGrantStore: LinkGrantStore {
    public static let shared = KeychainLinkGrantStore()
    private let items = KeychainStringSet(account: "link-grants")
    private static let virtualKeys = "virtual-keys"

    public var allowsVirtualKeys: Bool {
        items.members.contains(Self.virtualKeys)
    }

    public func setAllowsVirtualKeys(_ allowed: Bool) -> Bool {
        allowed ? items.insert(Self.virtualKeys) : items.remove(Self.virtualKeys)
    }
}

/// Keeps the choice in memory. Used by tests.
@MainActor
public final class InMemoryLinkGrantStore: LinkGrantStore {
    public private(set) var allowsVirtualKeys = false
    public init() {}
    public func setAllowsVirtualKeys(_ allowed: Bool) -> Bool {
        allowsVirtualKeys = allowed
        return true
    }
}

/// What a `keypath://` link opened by another app may do.
///
/// Raycast, Alfred, Hammerspoon and Terminal open these links on purpose, so
/// most actions stay available. A web page or a document can open them too,
/// so actions that could run code or open local files in other apps are limited:
///
/// - `script` does not run from a link. Scripts run from a key binding or from
///   the Send KeyPath Action shortcut.
/// - `open` opens only web pages (http and https).
/// - `fakekey` / `vkey` asks first, unless the user chose "Always Allow". A
///   virtual key runs whatever the config binds to it, scripts included, and
///   the prompt says so.
///
/// Still allowed: `launch` (an app name, never a path), `folder` (shows a
/// folder in Finder), `layer`, `window`, `system`, `notify`, `settings`,
/// `overlay`, `rule` (feedback only) and `runtime` (start or stop remapping;
/// a link can turn remapping off, which is a nuisance, not a way in).
/// A new action defaults to allowed, so add it here deliberately.
enum ExternalActionPolicy {
    enum Decision: Equatable {
        case allow
        case refuse(String)
        case confirmVirtualKey(name: String)
    }

    static func decision(for uri: KeyPathActionURI, allowsVirtualKeys: Bool) -> Decision {
        switch uri.action {
        case "script":
            return .refuse(String(localized: "Scripts can't be started by a link from another app. Bind the script to a key, or run it with the Send KeyPath Action shortcut."))
        case "open":
            guard let url = openTarget(uri) else {
                return .refuse(String(localized: "KeyPath couldn't read the web address in a link from another app."))
            }
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return .refuse(String(localized: "Links from other apps can only open web pages."))
            }
            return .allow
        case "fakekey", "vkey":
            return allowsVirtualKeys ? .allow : .confirmVirtualKey(name: uri.target ?? "?")
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

    /// An app name or bundle ID, never a path. Without a "/", a ".." inside a
    /// name cannot leave the folder it is looked up in, so only an exact ".."
    /// is refused. (A full path never worked here: the handler looks names up
    /// in /Applications, /System/Applications and ~/Applications.)
    static func isPlainAppName(_ name: String) -> Bool {
        !name.contains("/") && name != ".." && name != "."
    }
}
