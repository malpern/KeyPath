import Foundation

/// Represents a group of related key mappings that can be toggled together.
public struct RuleCollection: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var summary: String
    public var category: RuleCollectionCategory
    public var mappings: [KeyMapping]
    public var isEnabled: Bool
    public var isSystemDefault: Bool
    public var icon: String?
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        category: RuleCollectionCategory,
        mappings: [KeyMapping],
        isEnabled: Bool = true,
        isSystemDefault: Bool = false,
        icon: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.mappings = mappings
        self.isEnabled = isEnabled
        self.isSystemDefault = isSystemDefault
        self.icon = icon
        self.tags = tags
    }
}

/// High-level grouping for rule collections. Used for UI filtering and catalog presentation.
public enum RuleCollectionCategory: String, Codable, CaseIterable, Sendable {
    case system
    case navigation
    case productivity
    case accessibility
    case custom
    case experimental

    public var displayName: String {
        switch self {
        case .system: "System"
        case .navigation: "Navigation"
        case .productivity: "Productivity"
        case .accessibility: "Accessibility"
        case .custom: "Custom"
        case .experimental: "Experimental"
        }
    }
}

/// Deterministic identifiers for built-in collections so we can safely update them.
public enum RuleCollectionIdentifier {
    public static let macFunctionKeys = UUID(uuidString: "B8D6C8E4-2269-4C21-8C86-77D7A1722E01")!
    public static let vimNavigation = UUID(uuidString: "A1E0744C-66C1-4E69-8E68-DA2643765429")!
    public static let customMappings = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

public extension Sequence where Element == RuleCollection {
    /// Returns only the mappings belonging to enabled collections.
    func enabledMappings() -> [KeyMapping] {
        self.flatMap { collection in
            collection.isEnabled ? collection.mappings : []
        }
    }
}

extension Array where Element == RuleCollection {
    /// Convenience helper to find and update a collection in-place.
    mutating func updateCollection(_ collection: RuleCollection) {
        if let index = firstIndex(where: { $0.id == collection.id }) {
            self[index] = collection
        }
    }

    /// Wraps raw mappings into a single synthetic collection (used for migration/compat).
    static func collection(named name: String, mappings: [KeyMapping], category: RuleCollectionCategory = .custom) -> [RuleCollection] {
        guard !mappings.isEmpty else { return [] }
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.customMappings,
            name: name,
            summary: "Automatically generated from existing mappings",
            category: category,
            mappings: mappings,
            isEnabled: true,
            isSystemDefault: false,
            icon: "square.stack"
        )
        return [collection]
    }
}
