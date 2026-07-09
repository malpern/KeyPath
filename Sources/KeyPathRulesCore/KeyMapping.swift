import Foundation

/// Per-device output override for a single key mapping.
/// When a user has multiple keyboards and wants different behavior per device,
/// each override specifies the output for a particular device (identified by hash).
public struct DeviceKeyOverride: Codable, Equatable, Sendable {
    /// Device hash from kanata --list (e.g., "0x1234ABCD")
    public let deviceHash: String
    /// Output action for this device (replaces the default output)
    public let output: KeyAction
    /// Optional advanced behavior override for this device
    public let behavior: MappingBehavior?

    public init(deviceHash: String, output: KeyAction, behavior: MappingBehavior? = nil) {
        self.deviceHash = deviceHash
        self.output = output
        self.behavior = behavior
    }
}

/// Represents a key mapping from input to output action.
/// Used throughout the codebase for representing user-configured key remappings.
public struct KeyMapping: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let input: String
    public let action: KeyAction

    /// Optional output when Shift modifier is held (uses Kanata fork)
    public let shiftedOutput: String?

    /// Optional output when Ctrl modifier is held (uses Kanata fork)
    public let ctrlOutput: String?

    /// Human-readable description of what this mapping does
    public let description: String?

    /// If true, a visual separator row should appear before this mapping in table display
    public let sectionBreak: Bool

    /// Optional label shown as a section header before this mapping (e.g., "✋ Left hand")
    public let sectionLabel: String?

    /// Advanced behavior (dual-role, tap-dance, macro). Nil means simple remap using `action`.
    public let behavior: MappingBehavior?

    /// Per-device output overrides. When present, the config generator wraps
    /// the key output in a `(switch ((device N)) ...)` block.
    public let deviceOverrides: [DeviceKeyOverride]?

    public init(
        id: UUID = UUID(),
        input: String,
        action: KeyAction,
        shiftedOutput: String? = nil,
        ctrlOutput: String? = nil,
        description: String? = nil,
        sectionBreak: Bool = false,
        sectionLabel: String? = nil,
        behavior: MappingBehavior? = nil,
        deviceOverrides: [DeviceKeyOverride]? = nil
    ) {
        self.id = id
        self.input = input
        self.action = action
        self.shiftedOutput = shiftedOutput
        self.ctrlOutput = ctrlOutput
        self.description = description
        self.sectionBreak = sectionBreak
        self.sectionLabel = sectionLabel
        self.behavior = behavior
        self.deviceOverrides = deviceOverrides
    }

    /// Whether this mapping requires fork for modifier detection
    public var requiresFork: Bool {
        shiftedOutput != nil || ctrlOutput != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, input, action, shiftedOutput, ctrlOutput, description, sectionBreak, sectionLabel, behavior, deviceOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        input = try container.decode(String.self, forKey: .input)
        action = try container.decode(KeyAction.self, forKey: .action)
        shiftedOutput = try container.decodeIfPresent(String.self, forKey: .shiftedOutput)
        ctrlOutput = try container.decodeIfPresent(String.self, forKey: .ctrlOutput)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        sectionBreak = (try? container.decode(Bool.self, forKey: .sectionBreak)) ?? false
        sectionLabel = try container.decodeIfPresent(String.self, forKey: .sectionLabel)
        behavior = try container.decodeIfPresent(MappingBehavior.self, forKey: .behavior)
        deviceOverrides = try container.decodeIfPresent([DeviceKeyOverride].self, forKey: .deviceOverrides)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(input, forKey: .input)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(shiftedOutput, forKey: .shiftedOutput)
        try container.encodeIfPresent(ctrlOutput, forKey: .ctrlOutput)
        try container.encodeIfPresent(description, forKey: .description)
        if sectionBreak {
            try container.encode(sectionBreak, forKey: .sectionBreak)
        }
        try container.encodeIfPresent(sectionLabel, forKey: .sectionLabel)
        try container.encodeIfPresent(behavior, forKey: .behavior)
        try container.encodeIfPresent(deviceOverrides, forKey: .deviceOverrides)
    }
}
