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
        case .tap: "Tap"
        case .hold: "Hold"
        case .shift: "Shift"
        case .combo: "Combo"
        }
    }

    var shortLabel: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .shift: "Shift"
        case .combo: "Combo"
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
