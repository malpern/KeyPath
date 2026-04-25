// Resolves the kindaVim "strategy" (Accessibility / Keyboard / Hybrid /
// Ignored) for a given app bundle ID, by reading the user's kindaVim
// preferences plist.
//
// The plist lists three opt-in/out groups:
// - `appsToIgnore`: kindaVim does nothing in these apps
// - `appsForWhichToEnforceKeyboardStrategy`: forced into the degraded
//   Keyboard fallback (e.g. Slack, where AX support is shaky)
// - `appsForWhichToUseHybridMode`: explicit Hybrid bucket
//
// Anything not in any of these lists falls through to the default,
// which kindaVim's docs describe as the Accessibility strategy.

import Foundation

struct KindaVimStrategyResolver: Sendable {
    /// Lists pulled from the kindaVim prefs plist.
    struct PreferenceLists: Equatable, Sendable {
        let ignored: Set<String>
        let keyboardEnforced: Set<String>
        let hybrid: Set<String>

        static let empty = PreferenceLists(ignored: [], keyboardEnforced: [], hybrid: [])
    }

    static let defaultPreferencesURL: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library")
        .appendingPathComponent("Preferences")
        .appendingPathComponent("mo.com.sleeplessmind.kindaVim.plist")

    private let preferencesURL: URL

    init(preferencesURL: URL = KindaVimStrategyResolver.defaultPreferencesURL) {
        self.preferencesURL = preferencesURL
    }

    /// Read the three app lists out of the kindaVim plist. Returns
    /// `.empty` if the file is missing or unreadable — callers can treat
    /// that as "no overrides, default everywhere."
    func loadPreferenceLists() -> PreferenceLists {
        guard let data = try? Data(contentsOf: preferencesURL) else {
            return .empty
        }
        return Self.parsePreferenceLists(from: data)
    }

    /// Resolve a bundle ID against the given lists.
    func strategy(
        for bundleID: String?,
        lists: PreferenceLists
    ) -> KindaVimStrategy {
        guard let bundleID, !bundleID.isEmpty else { return .accessibility }
        if lists.ignored.contains(bundleID) { return .ignored }
        if lists.hybrid.contains(bundleID) { return .hybrid }
        if lists.keyboardEnforced.contains(bundleID) { return .keyboard }
        return .accessibility
    }

    // MARK: - Parsing

    static func parsePreferenceLists(from data: Data) -> PreferenceLists {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return .empty
        }
        return PreferenceLists(
            ignored: stringSet(in: plist, forKey: "appsToIgnore"),
            keyboardEnforced: stringSet(in: plist, forKey: "appsForWhichToEnforceKeyboardStrategy"),
            hybrid: stringSet(in: plist, forKey: "appsForWhichToUseHybridMode")
        )
    }

    private static func stringSet(in plist: [String: Any], forKey key: String) -> Set<String> {
        guard let array = plist[key] as? [Any] else { return [] }
        return Set(array.compactMap { $0 as? String })
    }
}
