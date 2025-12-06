import Foundation

/// Represents a user-created rule that maps a single input to an output.
public struct CustomRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var input: String
    public var output: String
    public var isEnabled: Bool
    public var notes: String?
    public var createdAt: Date
    /// Advanced behavior (tap-hold, tap-dance). Nil means simple remap.
    public var behavior: MappingBehavior?
    /// Target layer for this rule (defaults to base)
    public var targetLayer: RuleCollectionLayer

    public init(
        id: UUID = UUID(),
        title: String = "",
        input: String,
        output: String,
        isEnabled: Bool = true,
        notes: String? = nil,
        createdAt: Date = Date(),
        behavior: MappingBehavior? = nil,
        targetLayer: RuleCollectionLayer = .base
    ) {
        self.id = id
        self.title = title
        self.input = input
        self.output = output
        self.isEnabled = isEnabled
        self.notes = notes
        self.createdAt = createdAt
        self.behavior = behavior
        self.targetLayer = targetLayer
    }
}

// MARK: - Codable (with backwards compatibility for legacy JSON without targetLayer)

extension CustomRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, input, output, isEnabled, notes, createdAt, behavior, targetLayer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        input = try container.decode(String.self, forKey: .input)
        output = try container.decode(String.self, forKey: .output)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        behavior = try container.decodeIfPresent(MappingBehavior.self, forKey: .behavior)
        // Default to .base for legacy JSON without targetLayer
        targetLayer = try container.decodeIfPresent(RuleCollectionLayer.self, forKey: .targetLayer) ?? .base
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(input, forKey: .input)
        try container.encode(output, forKey: .output)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(behavior, forKey: .behavior)
        try container.encode(targetLayer, forKey: .targetLayer)
    }
}

public extension CustomRule {
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(input) → \(output)"
            : title
    }

    var summaryText: String {
        if let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedNotes.isEmpty
        {
            return trimmedNotes
        }
        return "Maps \(input) to \(output)"
    }

    func asKeyMapping() -> KeyMapping {
        KeyMapping(id: id, input: input, output: output, behavior: behavior)
    }

    func asRuleCollection() -> RuleCollection {
        RuleCollection(
            id: id,
            name: displayTitle,
            summary: summaryText,
            category: .custom,
            mappings: [asKeyMapping()],
            isEnabled: isEnabled,
            isSystemDefault: false,
            icon: "square.and.pencil",
            targetLayer: targetLayer
        )
    }

    /// Inline validation helper for UI/forms
    func validationErrors(existingRules: [CustomRule] = []) -> [CustomRuleValidator.ValidationError] {
        var errors = CustomRuleValidator.validate(self)
        if let conflict = CustomRuleValidator.checkConflict(for: self, against: existingRules) {
            errors.append(conflict)
        }
        return errors
    }
}

public extension Sequence<CustomRule> {
    func enabledMappings() -> [KeyMapping] {
        filter(\.isEnabled).map { $0.asKeyMapping() }
    }

    func asRuleCollections() -> [RuleCollection] {
        map { $0.asRuleCollection() }
    }
}
