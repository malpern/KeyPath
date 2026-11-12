import SwiftUI

// MARK: - BehaviorSlot

/// The behavior intents for a key (tap, hold, combo)
enum BehaviorSlot: String, Identifiable, CaseIterable {
    case tap
    case hold
    case shift
    case combo

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .tap: String(localized: "Tap", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        case .hold: String(localized: "Hold", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        case .shift: String(localized: "Shift", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        case .combo: String(localized: "Combo", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        }
    }

    var shortLabel: String {
        switch self {
        case .tap: String(localized: "Tap", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        case .hold: String(localized: "Hold", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        case .shift: String(localized: "Shift", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        case .combo: String(localized: "Combo", comment: "Key behavior slot: what the key does when tapped, held, shifted, or pressed with another key")
        }
    }

    var verbPhrase: String {
        switch self {
        case .tap: "tap"
        case .hold: "hold"
        case .shift: "shift +"
        case .combo: "press together with"
        }
    }

    var icon: String {
        switch self {
        case .tap: "hand.tap"
        case .hold: "hand.point.down.fill"
        case .shift: "shift"
        case .combo: "rectangle.on.rectangle"
        }
    }
}
