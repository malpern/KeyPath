import Foundation

/// Represents a simple key mapping from input to output
/// Used throughout the codebase for representing user-configured key remappings
public struct KeyMapping: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let input: String
    public let output: String

    /// Optional output when Shift modifier is held (uses Kanata fork)
    public let shiftedOutput: String?

    /// Optional output when Ctrl modifier is held (uses Kanata fork)
    public let ctrlOutput: String?

    public init(
        id: UUID = UUID(),
        input: String,
        output: String,
        shiftedOutput: String? = nil,
        ctrlOutput: String? = nil
    ) {
        self.id = id
        self.input = input
        self.output = output
        self.shiftedOutput = shiftedOutput
        self.ctrlOutput = ctrlOutput
    }

    /// Whether this mapping requires fork for modifier detection
    public var requiresFork: Bool {
        shiftedOutput != nil || ctrlOutput != nil
    }

    private enum CodingKeys: String, CodingKey { case id, input, output, shiftedOutput, ctrlOutput }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        input = try container.decode(String.self, forKey: .input)
        output = try container.decode(String.self, forKey: .output)
        shiftedOutput = try container.decodeIfPresent(String.self, forKey: .shiftedOutput)
        ctrlOutput = try container.decodeIfPresent(String.self, forKey: .ctrlOutput)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(input, forKey: .input)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(shiftedOutput, forKey: .shiftedOutput)
        try container.encodeIfPresent(ctrlOutput, forKey: .ctrlOutput)
    }
}
