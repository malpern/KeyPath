import Foundation

/// Represents a simple key mapping from input to output
/// Used throughout the codebase for representing user-configured key remappings
public struct KeyMapping: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let input: String
    public let output: String

    public init(id: UUID = UUID(), input: String, output: String) {
        self.id = id
        self.input = input
        self.output = output
    }

    private enum CodingKeys: String, CodingKey { case id, input, output }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        input = try container.decode(String.self, forKey: .input)
        output = try container.decode(String.self, forKey: .output)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(input, forKey: .input)
        try container.encode(output, forKey: .output)
    }
}
