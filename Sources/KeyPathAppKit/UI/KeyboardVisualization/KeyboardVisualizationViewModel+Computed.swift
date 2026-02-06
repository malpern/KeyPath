import Foundation
import SwiftUI

@MainActor
extension KeyboardVisualizationViewModel {
    // MARK: - Launcher Mode State

    /// Layer name that triggers launcher mode display
    static let launcherLayerName = "launcher"

    /// Whether the overlay is in launcher mode (should show app icons on keys)
    var isLauncherModeActive: Bool {
        currentLayerName.lowercased() == Self.launcherLayerName
    }

    // MARK: - One-Shot Modifier State

    /// One-shot modifier key codes for visual highlighting
    /// Maps modifier name to keyCode (e.g., "lsft" -> 56)
    static let oneShotModifierKeyCodes: [String: UInt16] = [
        "lsft": 56, "rsft": 60,
        "lctl": 59, "rctl": 62,
        "lalt": 58, "ralt": 61,
        "lmet": 55, "rmet": 54,
        "lcmd": 55, "rcmd": 54,
        "lopt": 58, "ropt": 61
    ]

    /// Get key codes for currently active one-shot modifiers
    var oneShotHighlightedKeyCodes: Set<UInt16> {
        var codes = Set<UInt16>()
        for modifier in activeOneShotModifiers {
            if let code = Self.oneShotModifierKeyCodes[modifier.lowercased()] {
                codes.insert(code)
            }
        }
        return codes
    }

    // MARK: - Key Emphasis

    /// HJKL key codes for nav layer auto-emphasis (computed once from key names)
    static let hjklKeyCodes: Set<UInt16> = ["h", "j", "k", "l"]
        .compactMap { kanataNameToKeyCode($0) }
        .reduce(into: Set<UInt16>()) { $0.insert($1) }

    /// Key codes to emphasize based on current layer and custom emphasis commands
    /// HJKL keys are auto-emphasized when on nav layer, plus any custom emphasis via push-msg
    var emphasizedKeyCodes: Set<UInt16> {
        // Auto-emphasis: HJKL on nav layer, but only when those keys are actually mapped.
        let autoEmphasis: Set<UInt16> = {
            guard currentLayerName.lowercased() == "nav" else { return [] }
            return Self.hjklKeyCodes.filter { keyCode in
                guard let info = layerKeyMap[keyCode] else { return false }
                return !info.isTransparent
            }
            .reduce(into: Set<UInt16>()) { $0.insert($1) }
        }()

        // Merge with custom emphasis from push-msg
        return autoEmphasis.union(customEmphasisKeyCodes)
    }

    /// Effective key codes that should appear pressed (TCP physical keys only)
    /// Uses only Kanata TCP KeyInput events to show the actual physical keys pressed,
    /// not the transformed output keys from CGEvent tap.
    var effectivePressedKeyCodes: Set<UInt16> {
        // Use TCP physical keys and any keys currently in an active hold state.
        pressedKeyCodes.union(holdActiveKeyCodes)
    }
}
