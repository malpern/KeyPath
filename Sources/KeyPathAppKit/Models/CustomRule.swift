import Foundation

/// Represents a user-created rule that maps a single input to an output.
public struct CustomRule: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var input: String
  public var output: String
  public var isEnabled: Bool
  public var notes: String?
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    title: String = "",
    input: String,
    output: String,
    isEnabled: Bool = true,
    notes: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.input = input
    self.output = output
    self.isEnabled = isEnabled
    self.notes = notes
    self.createdAt = createdAt
  }
}

extension CustomRule {
  public var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "\(input) → \(output)"
      : title
  }

  public var summaryText: String {
    if let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmedNotes.isEmpty {
      return trimmedNotes
    }
    return "Maps \(input) to \(output)"
  }

  public func asKeyMapping() -> KeyMapping {
    KeyMapping(id: id, input: input, output: output)
  }

  public func asRuleCollection() -> RuleCollection {
    RuleCollection(
      id: id,
      name: displayTitle,
      summary: summaryText,
      category: .custom,
      mappings: [asKeyMapping()],
      isEnabled: isEnabled,
      isSystemDefault: false,
      icon: "square.and.pencil",
      targetLayer: .base
    )
  }
}

extension Sequence<CustomRule> {
  public func enabledMappings() -> [KeyMapping] {
    filter(\.isEnabled).map { $0.asKeyMapping() }
  }

  public func asRuleCollections() -> [RuleCollection] {
    map { $0.asRuleCollection() }
  }
}
