import ApplicationServices
import Foundation

/// Represents a captured key sequence including modifiers and timing
public struct KeySequence: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = .init()
    public let keys: [KeyPress]
    public let captureMode: CaptureMode
    public let timestamp: Date

    public init(keys: [KeyPress], captureMode: CaptureMode, timestamp: Date = Date()) {
        self.keys = keys
        self.captureMode = captureMode
        self.timestamp = timestamp
    }

    /// Display representation for UI
    public var displayString: String {
        switch captureMode {
        case .single:
            keys.first?.displayString ?? ""
        case .chord:
            keys.first?.displayString ?? ""
        case .sequence:
            keys.map(\.displayString).joined(separator: " → ")
        }
    }

    /// Technical representation for Claude API
    public var technicalDescription: String {
        let keyDescriptions = keys.map(\.technicalDescription).joined(separator: ", ")
        return "CaptureMode: \(captureMode), Keys: [\(keyDescriptions)]"
    }

    /// Check if sequence is empty
    public var isEmpty: Bool {
        keys.isEmpty
    }
}

/// Individual key press with modifiers and timing
public struct KeyPress: Codable, Equatable, Sendable {
    public let baseKey: String
    public let modifiers: ModifierSet
    public let timestamp: Date
    public let keyCode: Int64

    public init(baseKey: String, modifiers: ModifierSet, timestamp: Date = Date(), keyCode: Int64) {
        self.baseKey = baseKey
        self.modifiers = modifiers
        self.timestamp = timestamp
        self.keyCode = keyCode
    }

    /// Display string with macOS symbols (single letters uppercased)
    public var displayString: String {
        var result = ""

        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        // Convert key names to user-friendly display
        let displayKey: String = switch baseKey.lowercased() {
        // Modifiers
        case "lmet", "rmet":
            "⌘"
        case "lctl", "rctl":
            "⌃"
        case "lalt", "ralt", "lopt", "ropt":
            "⌥"
        case "lsft", "rsft":
            "⇧"
        case "fn":
            "Fn"
        case "caps", "capslock":
            "⇪"
        // Common keys
        case "space", "spc":
            "Space"
        case "return", "ret":
            "↩"
        case "escape", "esc":
            "⎋"
        case "delete", "bspc":
            "⌫"
        case "forwarddelete":
            "⌦"
        case "tab":
            "⇥"
        // Arrow keys
        case "up":
            "↑"
        case "down":
            "↓"
        case "left":
            "←"
        case "right":
            "→"
        // Navigation
        case "home":
            "↖"
        case "end":
            "↘"
        case "pageup":
            "⇞"
        case "pagedown":
            "⇟"
        // Function keys
        case "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
             "f13", "f14", "f15", "f16":
            baseKey.uppercased()
        // Media keys
        case "volumeup":
            "🔊"
        case "volumedown":
            "🔉"
        case "mute":
            "🔇"
        case "brightnessup":
            "🔆"
        case "brightnessdown":
            "🔅"
        case "playpause":
            "⏯"
        case "next":
            "⏭"
        case "previous":
            "⏮"
        case "fastforward":
            "⏩"
        case "rewind":
            "⏪"
        case "eject":
            "⏏"
        case "kbillumup":
            "🔦+"
        case "kbillumdown":
            "🔦-"
        case "kbillumtoggle":
            "🔦"
        // Numpad
        case "clear":
            "⌧"
        case "kpenter":
            "⌤"
        case let kp where kp.hasPrefix("kp"):
            "KP" + kp.dropFirst(2)
        // Unknown keys (key123 format)
        case let unknown where unknown.hasPrefix("key"):
            "[\(unknown.dropFirst(3))]"
        default:
            // Uppercase single letters for display
            baseKey.count == 1 ? baseKey.uppercased() : baseKey
        }
        result += displayKey
        return result
    }

    /// Technical description for API calls
    public var technicalDescription: String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }

        parts.append("'\(baseKey)'")

        if parts.count == 1 {
            return parts[0]
        } else if let lastPart = parts.last {
            let modifierPart = parts.dropLast().joined(separator: "+")
            return "\(modifierPart)+\(lastPart)"
        } else {
            // Should never happen since parts.count > 1, but provide safe fallback
            return parts.joined(separator: "+")
        }
    }
}

/// Set of modifier keys
public struct ModifierSet: OptionSet, Codable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)

    /// Create from CGEventFlags
    public init(cgEventFlags: CGEventFlags) {
        var modifiers: ModifierSet = []

        if cgEventFlags.contains(.maskControl) { modifiers.insert(.control) }
        if cgEventFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if cgEventFlags.contains(.maskShift) { modifiers.insert(.shift) }
        if cgEventFlags.contains(.maskCommand) { modifiers.insert(.command) }

        self = modifiers
    }

    /// Check if any modifiers are present
    public var hasModifiers: Bool {
        !isEmpty
    }
}

/// Capture mode for key sequences
public enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case single // Single key press
    case chord // Simultaneous key combination (e.g., Cmd+S)
    case sequence // Sequential key presses (e.g., g,g or Cmd+K Cmd+C)

    public var displayName: String {
        switch self {
        case .single: "Single"
        case .chord: "Combos"
        case .sequence: "Sequence"
        }
    }

    public var symbol: String {
        switch self {
        case .single: "●" // Single dot for single key
        case .chord: "⌘" // Command symbol for combinations
        case .sequence: "→" // Arrow for sequences
        }
    }

    public var description: String {
        switch self {
        case .single: "Capture a single key"
        case .chord: "Capture key combinations (e.g., Cmd+S)"
        case .sequence: "Capture key sequences (e.g., g,g)"
        }
    }
}
