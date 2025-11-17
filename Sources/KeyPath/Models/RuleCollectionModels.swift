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
    public var targetLayer: RuleCollectionLayer
    public var momentaryActivator: MomentaryActivator?
    public var activationHint: String?

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        category: RuleCollectionCategory,
        mappings: [KeyMapping],
        isEnabled: Bool = true,
        isSystemDefault: Bool = false,
        icon: String? = nil,
        tags: [String] = [],
        targetLayer: RuleCollectionLayer = .base,
        momentaryActivator: MomentaryActivator? = nil,
        activationHint: String? = nil
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
        self.targetLayer = targetLayer
        self.momentaryActivator = momentaryActivator
        self.activationHint = activationHint
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, category, mappings, isEnabled, isSystemDefault, icon, tags, targetLayer, momentaryActivator, activationHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        category = try container.decode(RuleCollectionCategory.self, forKey: .category)
        mappings = try container.decode([KeyMapping].self, forKey: .mappings)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isSystemDefault = try container.decode(Bool.self, forKey: .isSystemDefault)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        targetLayer = try container.decodeIfPresent(RuleCollectionLayer.self, forKey: .targetLayer) ?? .base
        momentaryActivator = try container.decodeIfPresent(MomentaryActivator.self, forKey: .momentaryActivator)
        activationHint = try container.decodeIfPresent(String.self, forKey: .activationHint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(summary, forKey: .summary)
        try container.encode(category, forKey: .category)
        try container.encode(mappings, forKey: .mappings)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isSystemDefault, forKey: .isSystemDefault)
        try container.encode(icon, forKey: .icon)
        try container.encode(tags, forKey: .tags)
        try container.encode(targetLayer, forKey: .targetLayer)
        try container.encode(momentaryActivator, forKey: .momentaryActivator)
        try container.encode(activationHint, forKey: .activationHint)
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

public enum RuleCollectionLayer: Codable, Equatable, Sendable, Hashable {
    case base
    case navigation
    case custom(String)

    public var kanataName: String {
        switch self {
        case .base: "base"
        case .navigation: "navigation"
        case .custom(let name): name.lowercased()
        }
    }

    public var displayName: String {
        switch self {
        case .base: "Base"
        case .navigation: "Navigation"
        case .custom(let name): name.capitalized
        }
    }

    // Custom Codable implementation to handle both old and new formats
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "base": self = .base
        case "navigation": self = .navigation
        default: self = .custom(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(kanataName)
    }
}

public struct MomentaryActivator: Codable, Equatable, Sendable {
    public let input: String
    public let targetLayer: RuleCollectionLayer

    public init(input: String, targetLayer: RuleCollectionLayer) {
        self.input = input
        self.targetLayer = targetLayer
    }
}
