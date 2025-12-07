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

    /// Human-readable description of what this mapping does
    public let description: String?

    /// If true, a visual separator row should appear before this mapping in table display
    public let sectionBreak: Bool

    /// Advanced behavior (dual-role, tap-dance). Nil means simple remap using `output`.
    public let behavior: MappingBehavior?

    /// How the input keys should be interpreted (single key, chord, or sequence)
    public let inputType: InputType

    public init(
        id: UUID = UUID(),
        input: String,
        output: String,
        shiftedOutput: String? = nil,
        ctrlOutput: String? = nil,
        description: String? = nil,
        sectionBreak: Bool = false,
        behavior: MappingBehavior? = nil,
        inputType: InputType = .single
    ) {
        self.id = id
        self.input = input
        self.output = output
        self.shiftedOutput = shiftedOutput
        self.ctrlOutput = ctrlOutput
        self.description = description
        self.sectionBreak = sectionBreak
        self.behavior = behavior
        self.inputType = inputType
    }

    /// Whether this mapping requires fork for modifier detection
    public var requiresFork: Bool {
        shiftedOutput != nil || ctrlOutput != nil
    }

    /// Validation errors for this mapping (input/output and optional modifier outputs)
    public func validationErrors(
        existingMappings: [KeyMapping] = []
    ) -> [CustomRuleValidator.ValidationError] {
        var errors = CustomRuleValidator.validateKeys(input: input, output: output)

        if let shiftedOutput {
            errors.append(contentsOf: CustomRuleValidator.validateKeys(input: input, output: shiftedOutput)
                .filter { $0 != .emptyInput }) // Avoid duplicate empty-input error
        }

        if let ctrlOutput {
            errors.append(contentsOf: CustomRuleValidator.validateKeys(input: input, output: ctrlOutput)
                .filter { $0 != .emptyInput })
        }

        // Check for conflicts on input key
        let normalizedInput = CustomRuleValidator.normalizeKey(input)
        if let conflict = existingMappings.first(
            where: { $0.id != id && CustomRuleValidator.normalizeKey($0.input) == normalizedInput }
        ) {
            errors.append(.conflict(with: conflict.description ?? "existing mapping", key: normalizedInput))
        }

        return errors
    }

    /// Backwards-compatible check used in UI
    public func isValid() -> Bool {
        validationErrors().isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, input, output, shiftedOutput, ctrlOutput, description, sectionBreak, behavior, inputType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        input = try container.decode(String.self, forKey: .input)
        output = try container.decode(String.self, forKey: .output)
        shiftedOutput = try container.decodeIfPresent(String.self, forKey: .shiftedOutput)
        ctrlOutput = try container.decodeIfPresent(String.self, forKey: .ctrlOutput)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        sectionBreak = (try? container.decode(Bool.self, forKey: .sectionBreak)) ?? false
        behavior = try container.decodeIfPresent(MappingBehavior.self, forKey: .behavior)
        // Default to .single for legacy JSON without inputType
        inputType = try container.decodeIfPresent(InputType.self, forKey: .inputType) ?? .single
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(input, forKey: .input)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(shiftedOutput, forKey: .shiftedOutput)
        try container.encodeIfPresent(ctrlOutput, forKey: .ctrlOutput)
        try container.encodeIfPresent(description, forKey: .description)
        if sectionBreak {
            try container.encode(sectionBreak, forKey: .sectionBreak)
        }
        try container.encodeIfPresent(behavior, forKey: .behavior)
        try container.encode(inputType, forKey: .inputType)
    }
}
