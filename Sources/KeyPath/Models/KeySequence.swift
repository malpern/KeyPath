import ApplicationServices
import Foundation

/// Represents a captured key sequence including modifiers and timing
public struct KeySequence: Identifiable, Codable, Equatable {
    public let id = UUID()
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
            return keys.first?.displayString ?? ""
        case .chord:
            return keys.first?.displayString ?? ""
        case .sequence:
            return keys.map { $0.displayString }.joined(separator: " → ")
        }
    }

    /// Technical representation for Claude API
    public var technicalDescription: String {
        let keyDescriptions = keys.map { $0.technicalDescription }.joined(separator: ", ")
        return "CaptureMode: \(captureMode), Keys: [\(keyDescriptions)]"
    }

    /// Check if sequence is empty
    public var isEmpty: Bool {
        return keys.isEmpty
    }
}

/// Individual key press with modifiers and timing
public struct KeyPress: Codable, Equatable {
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

    /// Display string with macOS symbols
    public var displayString: String {
        var result = ""

        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        result += baseKey
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
        } else {
            let modifierPart = parts.dropLast().joined(separator: "+")
            return "\(modifierPart)+\(parts.last!)"
        }
    }
}

/// Set of modifier keys
public struct ModifierSet: OptionSet, Codable {
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
        return !isEmpty
    }
}

/// Capture mode for key sequences
public enum CaptureMode: String, CaseIterable, Codable {
    case single // Single key press
    case chord // Simultaneous key combination (e.g., Cmd+S)
    case sequence // Sequential key presses (e.g., g,g or Cmd+K Cmd+C)

    public var displayName: String {
        switch self {
        case .single: return "Single"
        case .chord: return "Combos"
        case .sequence: return "Sequence"
        }
    }

    public var symbol: String {
        switch self {
        case .single: return "●" // Single dot for single key
        case .chord: return "⌘" // Command symbol for combinations
        case .sequence: return "→" // Arrow for sequences
        }
    }

    public var description: String {
        switch self {
        case .single: return "Capture a single key"
        case .chord: return "Capture key combinations (e.g., Cmd+S)"
        case .sequence: return "Capture key sequences (e.g., g,g)"
        }
    }
}
