import Foundation

/// Represents a group of related key mappings that can be toggled together.
public struct RuleCollection: Identifiable, Codable, Equatable, Sendable {
    // MARK: - Identity

    public let id: UUID
    public var name: String

    // MARK: - Metadata

    public var summary: String
    public var category: RuleCollectionCategory
    public var icon: String?
    public var tags: [String]
    public var activationHint: String?

    // MARK: - State

    public var isEnabled: Bool
    public var isSystemDefault: Bool

    // MARK: - Core Behavior

    public var mappings: [KeyMapping]
    public var targetLayer: RuleCollectionLayer
    public var momentaryActivator: MomentaryActivator?

    // MARK: - Display Style Configuration

    /// Type-safe configuration for display-style-specific settings.
    ///
    /// This is the primary storage for display style and its associated data.
    /// Use pattern matching to access style-specific configuration:
    ///
    /// ```swift
    /// switch collection.configuration {
    /// case .list, .table:
    ///     // Simple display - no additional config
    /// case .singleKeyPicker(let config):
    ///     // Access config.inputKey, config.presetOptions, config.selectedOutput
    /// case .tapHoldPicker(let config):
    ///     // Access config.tapOptions, config.holdOptions, etc.
    /// case .homeRowMods(let config):
    ///     // Access config.enabledKeys, config.modifierAssignments, etc.
    /// case .layerPresetPicker(let config):
    ///     // Access config.presets, config.selectedPresetId
    /// }
    /// ```
    public var configuration: RuleCollectionConfiguration

    // MARK: - Style-Specific Options (not part of configuration)

    /// For windowSnapping: which key convention to use (standard mnemonic vs vim)
    public var windowKeyConvention: WindowKeyConvention?

    /// For macFunctionKeys: media keys (default Mac) or standard F-keys
    public var functionKeyMode: FunctionKeyMode?

    // MARK: - Computed Properties

    /// The display style (derived from configuration for convenience)
    public var displayStyle: RuleCollectionDisplayStyle {
        configuration.displayStyle
    }

    // MARK: - Initializer

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
        configuration: RuleCollectionConfiguration = .list,
        windowKeyConvention: WindowKeyConvention? = nil,
        functionKeyMode: FunctionKeyMode? = nil
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
        self.configuration = configuration
        self.windowKeyConvention = windowKeyConvention
        self.functionKeyMode = functionKeyMode
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, summary, category, mappings, isEnabled, isSystemDefault
        case icon, tags, targetLayer, momentaryActivator, activationHint
        case configuration, windowKeyConvention, functionKeyMode
        // Legacy keys for migration
        case displayStyle, pickerInputKey, presetOptions, selectedOutput
        case homeRowModsConfig, tapHoldOptions, selectedTapOutput, selectedHoldOutput
        case layerPresets, selectedLayerPreset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Core fields
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
        windowKeyConvention = try container.decodeIfPresent(WindowKeyConvention.self, forKey: .windowKeyConvention)
        functionKeyMode = try container.decodeIfPresent(FunctionKeyMode.self, forKey: .functionKeyMode)

        // Try new format first (configuration object)
        if let config = try? container.decode(RuleCollectionConfiguration.self, forKey: .configuration) {
            configuration = config
        } else {
            // Fall back to legacy format migration
            let legacyDisplayStyle = try container.decodeIfPresent(RuleCollectionDisplayStyle.self, forKey: .displayStyle) ?? .list

            switch legacyDisplayStyle {
            case .list:
                configuration = .list
            case .table:
                configuration = .table
            case .singleKeyPicker:
                let inputKey = try container.decodeIfPresent(String.self, forKey: .pickerInputKey) ?? ""
                let presetOptions = try container.decodeIfPresent([SingleKeyPreset].self, forKey: .presetOptions) ?? []
                let selectedOutput = try container.decodeIfPresent(String.self, forKey: .selectedOutput)
                configuration = .singleKeyPicker(SingleKeyPickerConfig(
                    inputKey: inputKey,
                    presetOptions: presetOptions,
                    selectedOutput: selectedOutput
                ))
            case .homeRowMods:
                let config = try container.decodeIfPresent(HomeRowModsConfig.self, forKey: .homeRowModsConfig) ?? HomeRowModsConfig()
                configuration = .homeRowMods(config)
            case .tapHoldPicker:
                let inputKey = try container.decodeIfPresent(String.self, forKey: .pickerInputKey) ?? ""
                let tapHoldOptions = try container.decodeIfPresent(TapHoldPresetOptions.self, forKey: .tapHoldOptions)
                let selectedTapOutput = try container.decodeIfPresent(String.self, forKey: .selectedTapOutput)
                let selectedHoldOutput = try container.decodeIfPresent(String.self, forKey: .selectedHoldOutput)
                configuration = .tapHoldPicker(TapHoldPickerConfig(
                    inputKey: inputKey,
                    tapOptions: tapHoldOptions?.tapOptions ?? [],
                    holdOptions: tapHoldOptions?.holdOptions ?? [],
                    selectedTapOutput: selectedTapOutput,
                    selectedHoldOutput: selectedHoldOutput
                ))
            case .layerPresetPicker:
                let presets = try container.decodeIfPresent([LayerPreset].self, forKey: .layerPresets) ?? []
                let selectedPresetId = try container.decodeIfPresent(String.self, forKey: .selectedLayerPreset)
                configuration = .layerPresetPicker(LayerPresetPickerConfig(
                    presets: presets,
                    selectedPresetId: selectedPresetId
                ))
            case .launcherGrid:
                // LauncherGrid is a new type, no legacy format to migrate
                configuration = .launcherGrid(LauncherGridConfig.defaultConfig)
            }
        }
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
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(tags, forKey: .tags)
        try container.encode(targetLayer, forKey: .targetLayer)
        try container.encodeIfPresent(momentaryActivator, forKey: .momentaryActivator)
        try container.encodeIfPresent(activationHint, forKey: .activationHint)
        try container.encode(configuration, forKey: .configuration)
        try container.encodeIfPresent(windowKeyConvention, forKey: .windowKeyConvention)
        try container.encodeIfPresent(functionKeyMode, forKey: .functionKeyMode)
    }
}

// MARK: - Sequence Extension

public extension Sequence<RuleCollection> {
    /// Returns only the mappings belonging to enabled collections.
    func enabledMappings() -> [KeyMapping] {
        flatMap { collection in
            collection.isEnabled ? collection.mappings : []
        }
    }
}

// MARK: - Array Extension

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

// MARK: - Supporting Types

/// Key convention for window snapping shortcuts
public enum WindowKeyConvention: String, Codable, CaseIterable, Sendable {
    case standard
    case vim

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .vim: "Vim"
        }
    }

    public var description: String {
        switch self {
        case .standard: "L=Left, R=Right, U/I/J/K corners"
        case .vim: "H=Left, L=Right, Y/U/B/N corners"
        }
    }
}

/// Function key mode: media keys (default Mac behavior) or standard F-keys
public enum FunctionKeyMode: String, Codable, CaseIterable, Sendable {
    case media
    case function

    public var displayName: String {
        switch self {
        case .media: "Media Keys"
        case .function: "Function Keys"
        }
    }

    public var description: String {
        switch self {
        case .media: "Shows brightness, volume, and media controls (default Mac behavior)"
        case .function: "Shows F1-F12 for apps that use function keys"
        }
    }

    /// Convert from Bool (true = media, false = function) for backwards compatibility
    public init(preferMediaKeys: Bool) {
        self = preferMediaKeys ? .media : .function
    }

    /// Convert to Bool for UI binding
    public var preferMediaKeys: Bool {
        self == .media
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
    public static let leaderKey = UUID(uuidString: "A1B2C3D4-5E6F-7A8B-9C0D-1E2F3A4B5C6D")!
    public static let customMappings = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let homeRowMods = UUID(uuidString: "B3E5F7A9-1C2D-4E5F-6A7B-8C9D0E1F2A3B")!
    public static let backupCapsLock = UUID(uuidString: "C4D6E8F0-2A3B-5C7D-9E1F-3A5B7C9D1E3F")!
    public static let numpadLayer = UUID(uuidString: "D5E7F9A1-3B4C-6D8E-0F2A-4B6C8D0E2F4A")!
    public static let symbolLayer = UUID(uuidString: "E6F8A0B2-4C5D-7E9F-1A3B-5C7D9E1F3A5B")!
    public static let windowSnapping = UUID(uuidString: "F7A9B1C3-5D6E-8F0A-2B4C-6D8E0F2A4B6C")!
    public static let launcher = UUID(uuidString: "A8B9C0D1-2E3F-4A5B-6C7D-8E9F0A1B2C3D")!
    public static let typingSounds = UUID(uuidString: "B9C0D1E2-3F4A-5B6C-7D8E-9F0A1B2C3D4E")!
    public static let keycapColorway = UUID(uuidString: "C0D1E2F3-4A5B-6C7D-8E9F-0A1B2C3D4E5F")!
}

public enum RuleCollectionLayer: Codable, Equatable, Sendable, Hashable {
    case base
    case navigation
    case custom(String)

    public var kanataName: String {
        switch self {
        case .base: "base"
        case .navigation: "nav"
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
        case "nav", "navigation": self = .navigation
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
    /// The layer where this activator should be placed. Defaults to `.base`.
    /// Use `.navigation` to create chained layers (e.g., leader → nav → window).
    public let sourceLayer: RuleCollectionLayer

    public init(input: String, targetLayer: RuleCollectionLayer, sourceLayer: RuleCollectionLayer = .base) {
        self.input = input
        self.targetLayer = targetLayer
        self.sourceLayer = sourceLayer
    }

    // MARK: - Custom Codable Implementation

    /// Custom decoding to handle backward compatibility with saved configurations
    /// that lack the `sourceLayer` field (defaults to `.base` when missing)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decode(String.self, forKey: .input)
        targetLayer = try container.decode(RuleCollectionLayer.self, forKey: .targetLayer)
        // Use decodeIfPresent to handle missing sourceLayer in old saved files
        sourceLayer = try container.decodeIfPresent(RuleCollectionLayer.self, forKey: .sourceLayer) ?? .base
    }

    /// Custom encoding to ensure sourceLayer is always written (for consistency)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(input, forKey: .input)
        try container.encode(targetLayer, forKey: .targetLayer)
        try container.encode(sourceLayer, forKey: .sourceLayer)
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case targetLayer
        case sourceLayer
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
    /// Home Row Mods: visual keyboard with interactive customization
    case homeRowMods
    /// Tap-hold picker: separate preset options for tap and hold actions
    case tapHoldPicker
    /// Layer preset picker: choose from predefined layer configurations (e.g., Symbol Layer presets)
    case layerPresetPicker
    /// Launcher grid: quick app/website launching via keyboard shortcuts
    case launcherGrid
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

/// Preset options for tap-hold picker collections
public struct TapHoldPresetOptions: Codable, Equatable, Sendable {
    public let tapOptions: [SingleKeyPreset]
    public let holdOptions: [SingleKeyPreset]

    public init(tapOptions: [SingleKeyPreset], holdOptions: [SingleKeyPreset]) {
        self.tapOptions = tapOptions
        self.holdOptions = holdOptions
    }
}

/// A preset configuration for layer-based rules (e.g., Symbol Layer presets)
public struct LayerPreset: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let description: String
    public let icon: String?
    public let mappings: [KeyMapping]

    public init(id: String, label: String, description: String, icon: String? = nil, mappings: [KeyMapping]) {
        self.id = id
        self.label = label
        self.description = description
        self.icon = icon
        self.mappings = mappings
    }
}
