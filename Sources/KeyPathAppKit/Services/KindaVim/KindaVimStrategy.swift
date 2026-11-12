// kindaVim ships two backends — the docs call them strategies. Most apps
// fall under the Accessibility strategy; a curated list (Slack today, see
// the user's prefs plist) gets forced into the Keyboard fallback for AX
// compatibility reasons. A small set of apps gets Hybrid.
//
// We surface the strategy in our hint UI because it determines which Vim
// commands are actually wired up: Keyboard drops `gg`/`G`/visual mode and
// most text objects, for example. Accessibility is the full set.

import Foundation

enum KindaVimStrategy: String, CaseIterable, Sendable, Equatable {
    case accessibility
    case keyboard
    case hybrid
    case ignored

    var displayName: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .keyboard: String(localized: "Keyboard fallback")
        case .hybrid: String(localized: "Hybrid")
        case .ignored: String(localized: "Ignored for this app")
        }
    }
}
