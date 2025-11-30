import Foundation

// MARK: - Input Models

/// A key tap event to simulate (press + delay + release)
struct SimulatorKeyTap: Identifiable, Equatable, Hashable {
    let id = UUID()
    let kanataKey: String       // e.g., "a", "lctl", "spc", "lsft"
    let displayLabel: String    // e.g., "A", "Ctrl", "Space", "Shift"
    let delayAfterMs: UInt64    // Default: 200ms for tap, 400ms for hold
    let isHold: Bool            // Whether this is a long-press (hold) vs tap

    init(kanataKey: String, displayLabel: String, delayAfterMs: UInt64, isHold: Bool = false) {
        self.kanataKey = kanataKey
        self.displayLabel = displayLabel
        self.delayAfterMs = delayAfterMs
        self.isHold = isHold
    }

    static func == (lhs: SimulatorKeyTap, rhs: SimulatorKeyTap) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Output Models (matching Kanata JSON schema)

/// Complete simulation result from kanata-simulator --json
struct SimulationResult: Codable, Equatable {
    let events: [SimEvent]
    let finalLayer: String?
    let durationMs: UInt64

    enum CodingKeys: String, CodingKey {
        case events
        case finalLayer
        case durationMs = "duration_ms"
    }
}

/// Structured simulation event from Kanata
/// Uses internally-tagged enum format: {"type": "input", "t": 0, ...}
enum SimEvent: Codable, Equatable {
    case input(t: UInt64, action: SimKeyAction, key: String)
    case output(t: UInt64, action: SimKeyAction, key: String)
    case layer(t: UInt64, from: String, to: String)
    case unicode(t: UInt64, char: String)
    case mouse(t: UInt64, action: SimMouseAction, data: String)

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case type, t, action, key, from, to, char, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "input":
            let t = try container.decode(UInt64.self, forKey: .t)
            let action = try container.decode(SimKeyAction.self, forKey: .action)
            let key = try container.decode(String.self, forKey: .key)
            self = .input(t: t, action: action, key: key)

        case "output":
            let t = try container.decode(UInt64.self, forKey: .t)
            let action = try container.decode(SimKeyAction.self, forKey: .action)
            let key = try container.decode(String.self, forKey: .key)
            self = .output(t: t, action: action, key: key)

        case "layer":
            let t = try container.decode(UInt64.self, forKey: .t)
            let from = try container.decode(String.self, forKey: .from)
            let to = try container.decode(String.self, forKey: .to)
            self = .layer(t: t, from: from, to: to)

        case "unicode":
            let t = try container.decode(UInt64.self, forKey: .t)
            let char = try container.decode(String.self, forKey: .char)
            self = .unicode(t: t, char: char)

        case "mouse":
            let t = try container.decode(UInt64.self, forKey: .t)
            let action = try container.decode(SimMouseAction.self, forKey: .action)
            let data = try container.decode(String.self, forKey: .data)
            self = .mouse(t: t, action: action, data: data)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown event type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .input(t, action, key):
            try container.encode("input", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(action, forKey: .action)
            try container.encode(key, forKey: .key)

        case let .output(t, action, key):
            try container.encode("output", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(action, forKey: .action)
            try container.encode(key, forKey: .key)

        case let .layer(t, from, to):
            try container.encode("layer", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)

        case let .unicode(t, char):
            try container.encode("unicode", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(char, forKey: .char)

        case let .mouse(t, action, data):
            try container.encode("mouse", forKey: .type)
            try container.encode(t, forKey: .t)
            try container.encode(action, forKey: .action)
            try container.encode(data, forKey: .data)
        }
    }

    // MARK: - Convenience

    /// Timestamp in milliseconds from simulation start
    var timestamp: UInt64 {
        switch self {
        case let .input(t, _, _): t
        case let .output(t, _, _): t
        case let .layer(t, _, _): t
        case let .unicode(t, _): t
        case let .mouse(t, _, _): t
        }
    }

    /// Human-readable description for display
    var displayDescription: String {
        switch self {
        case let .input(_, action, key):
            "\(action.symbol)\(key)"
        case let .output(_, action, key):
            "\(action.symbol)\(key)"
        case let .layer(_, from, to):
            "\(from) → \(to)"
        case let .unicode(_, char):
            "'\(char)'"
        case let .mouse(_, action, data):
            "\(action.rawValue): \(data)"
        }
    }

    /// Whether this is an input event (user pressed)
    var isInput: Bool {
        if case .input = self { return true }
        return false
    }

    /// Whether this is an output event (Kanata would emit)
    var isOutput: Bool {
        if case .output = self { return true }
        return false
    }

    /// Whether this is a layer change
    var isLayerChange: Bool {
        if case .layer = self { return true }
        return false
    }
}

/// Key action type matching Kanata's SimKeyAction
enum SimKeyAction: String, Codable, Equatable {
    case press
    case release
    case `repeat`

    /// Symbol for display (↓ for press, ↑ for release, ⟳ for repeat)
    var symbol: String {
        switch self {
        case .press: "↓"
        case .release: "↑"
        case .repeat: "⟳"
        }
    }
}

/// Mouse action type matching Kanata's SimMouseAction
enum SimMouseAction: String, Codable, Equatable {
    case click
    case release
    case move
    case scroll
}

// MARK: - Errors

enum SimulatorError: Error, LocalizedError {
    case simulatorNotFound
    case configNotFound(String)
    case processFailedWithCode(Int, String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .simulatorNotFound:
            "Simulator binary not found in app bundle"
        case let .configNotFound(path):
            "Config not found: \(path)"
        case let .processFailedWithCode(code, msg):
            "Simulator failed (\(code)): \(msg)"
        case let .invalidJSON(msg):
            "Invalid JSON output: \(msg)"
        }
    }
}
