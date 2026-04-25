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
        case .accessibility: "Accessibility"
        case .keyboard: "Keyboard fallback"
        case .hybrid: "Hybrid"
        case .ignored: "Ignored for this app"
        }
    }
}
