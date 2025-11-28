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
    public var displayStyle: RuleCollectionDisplayStyle
    /// For singleKeyPicker style: the input key being remapped (e.g., "caps")
    public var pickerInputKey: String?
    /// For singleKeyPicker style: available preset output options
    public var presetOptions: [SingleKeyPreset]
    /// For singleKeyPicker style: currently selected output (can be preset or custom)
    public var selectedOutput: String?

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
        activationHint: String? = nil,
        displayStyle: RuleCollectionDisplayStyle = .list,
        pickerInputKey: String? = nil,
        presetOptions: [SingleKeyPreset] = [],
        selectedOutput: String? = nil
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
        self.displayStyle = displayStyle
        self.pickerInputKey = pickerInputKey
        self.presetOptions = presetOptions
        self.selectedOutput = selectedOutput
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, category, mappings, isEnabled, isSystemDefault, icon, tags, targetLayer,
             momentaryActivator, activationHint, displayStyle, pickerInputKey, presetOptions, selectedOutput
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
        targetLayer =
            try container.decodeIfPresent(RuleCollectionLayer.self, forKey: .targetLayer) ?? .base
        momentaryActivator = try container.decodeIfPresent(
            MomentaryActivator.self, forKey: .momentaryActivator
        )
        activationHint = try container.decodeIfPresent(String.self, forKey: .activationHint)
        displayStyle =
            try container.decodeIfPresent(RuleCollectionDisplayStyle.self, forKey: .displayStyle) ?? .list
        pickerInputKey = try container.decodeIfPresent(String.self, forKey: .pickerInputKey)
        presetOptions = try container.decodeIfPresent([SingleKeyPreset].self, forKey: .presetOptions) ?? []
        selectedOutput = try container.decodeIfPresent(String.self, forKey: .selectedOutput)
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
        try container.encode(displayStyle, forKey: .displayStyle)
        try container.encodeIfPresent(pickerInputKey, forKey: .pickerInputKey)
        try container.encode(presetOptions, forKey: .presetOptions)
        try container.encodeIfPresent(selectedOutput, forKey: .selectedOutput)
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
    public static let capsLockHyperKey = UUID(uuidString: "F4A2E8D1-9C3B-4E7A-B5F6-2D8C9A3E1B4F")!
    public static let capsLockRemap = UUID(uuidString: "D2B4F6A8-1C3E-5D7F-9A2B-4C6E8F0A2B4D")!
    public static let escapeRemap = UUID(uuidString: "E7C9A3B5-2F4D-6E8A-B1C3-5D7F9A2B4C6E")!
    public static let deleteRemap = UUID(uuidString: "F8D0B4C6-3A5E-7F9B-C2D4-6E8A0B2C4D6F")!
    public static let customMappings = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

public extension Sequence<RuleCollection> {
    /// Returns only the mappings belonging to enabled collections.
    func enabledMappings() -> [KeyMapping] {
        flatMap { collection in
            collection.isEnabled ? collection.mappings : []
        }
    }
}

extension [RuleCollection] {
    /// Convenience helper to find and update a collection in-place.
    mutating func updateCollection(_ collection: RuleCollection) {
        if let index = firstIndex(where: { $0.id == collection.id }) {
            self[index] = collection
        }
    }

    /// Wraps raw mappings into a single synthetic collection (used for migration/compat).
    static func collection(
        named name: String, mappings: [KeyMapping], category: RuleCollectionCategory = .custom
    ) -> [RuleCollection] {
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
        case let .custom(name): name.lowercased()
        }
    }

    public var displayName: String {
        switch self {
        case .base: "Base"
        case .navigation: "Navigation"
        case let .custom(name): name.capitalized
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

/// Controls how a rule collection's mappings are displayed in the UI.
public enum RuleCollectionDisplayStyle: String, Codable, Sendable {
    /// Simple list with input → output pairs (default)
    case list
    /// Table with columns for Key, Action, +Shift, +Ctrl (for complex mappings)
    case table
    /// Segmented picker for single-key remapping with preset options (e.g., Caps Lock → X)
    case singleKeyPicker
}

/// A preset option for single-key picker collections
public struct SingleKeyPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: String { output }
    public let output: String
    public let label: String
    public let description: String
    public let icon: String?

    public init(output: String, label: String, description: String, icon: String? = nil) {
        self.output = output
        self.label = label
        self.description = description
        self.icon = icon
    }
}
