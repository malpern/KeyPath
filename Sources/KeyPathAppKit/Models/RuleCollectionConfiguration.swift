import Foundation

// MARK: - Display Style Configuration

/// Type-safe configuration for different rule collection display styles.
///
/// This enum replaces the previous flat structure where many optional fields
/// existed on RuleCollection but only applied to specific display styles.
/// Now each display style carries exactly the data it needs.
///
/// ## JSON Format
/// The configuration is encoded as a discriminated union with a `type` field:
/// ```json
/// {
///   "type": "singleKeyPicker",
///   "inputKey": "caps",
///   "presetOptions": [...],
///   "selectedOutput": "esc"
/// }
/// ```
public enum RuleCollectionConfiguration: Codable, Equatable, Sendable {
    /// Simple list with input → output pairs (default)
    case list

    /// Table with columns for Key, Action, +Shift, +Ctrl (for complex mappings)
    case table

    /// Segmented picker for single-key remapping with preset options (e.g., Caps Lock → X)
    case singleKeyPicker(SingleKeyPickerConfig)

    /// Home Row Mods: visual keyboard with interactive customization
    case homeRowMods(HomeRowModsConfig)

    /// Tap-hold picker: separate preset options for tap and hold actions
    case tapHoldPicker(TapHoldPickerConfig)

    /// Layer preset picker: choose from predefined layer configurations
    case layerPresetPicker(LayerPresetPickerConfig)

    /// Launcher grid: quick app/website launching via keyboard shortcuts
    case launcherGrid(LauncherGridConfig)

    // MARK: - Convenience Accessors

    /// The display style enum value (for compatibility with existing UI code)
    public var displayStyle: RuleCollectionDisplayStyle {
        switch self {
        case .list: .list
        case .table: .table
        case .singleKeyPicker: .singleKeyPicker
        case .homeRowMods: .homeRowMods
        case .tapHoldPicker: .tapHoldPicker
        case .layerPresetPicker: .layerPresetPicker
        case .launcherGrid: .launcherGrid
        }
    }

    /// Extract single key picker config if this is a `.singleKeyPicker` case
    public var singleKeyPickerConfig: SingleKeyPickerConfig? {
        if case let .singleKeyPicker(config) = self { return config }
        return nil
    }

    /// Extract tap-hold picker config if this is a `.tapHoldPicker` case
    public var tapHoldPickerConfig: TapHoldPickerConfig? {
        if case let .tapHoldPicker(config) = self { return config }
        return nil
    }

    /// Extract home row mods config if this is a `.homeRowMods` case
    public var homeRowModsConfig: HomeRowModsConfig? {
        if case let .homeRowMods(config) = self { return config }
        return nil
    }

    /// Extract layer preset picker config if this is a `.layerPresetPicker` case
    public var layerPresetPickerConfig: LayerPresetPickerConfig? {
        if case let .layerPresetPicker(config) = self { return config }
        return nil
    }

    /// Extract launcher grid config if this is a `.launcherGrid` case
    public var launcherGridConfig: LauncherGridConfig? {
        if case let .launcherGrid(config) = self { return config }
        return nil
    }

    // MARK: - Mutating Helpers

    /// Update the selected output for single key picker configuration
    public mutating func updateSelectedOutput(_ output: String) {
        if case let .singleKeyPicker(config) = self {
            var updated = config
            updated.selectedOutput = output
            self = .singleKeyPicker(updated)
        }
    }

    /// Update the selected tap output for tap-hold picker configuration
    public mutating func updateSelectedTapOutput(_ output: String) {
        if case let .tapHoldPicker(config) = self {
            var updated = config
            updated.selectedTapOutput = output
            self = .tapHoldPicker(updated)
        }
    }

    /// Update the selected hold output for tap-hold picker configuration
    public mutating func updateSelectedHoldOutput(_ output: String) {
        if case let .tapHoldPicker(config) = self {
            var updated = config
            updated.selectedHoldOutput = output
            self = .tapHoldPicker(updated)
        }
    }

    /// Update the home row mods config
    public mutating func updateHomeRowModsConfig(_ newConfig: HomeRowModsConfig) {
        if case .homeRowMods = self {
            self = .homeRowMods(newConfig)
        }
    }

    /// Update the selected preset for layer preset picker configuration
    public mutating func updateSelectedPreset(_ presetId: String) {
        if case let .layerPresetPicker(config) = self {
            var updated = config
            updated.selectedPresetId = presetId
            self = .layerPresetPicker(updated)
        }
    }

    /// Update the launcher grid config
    public mutating func updateLauncherGridConfig(_ newConfig: LauncherGridConfig) {
        if case .launcherGrid = self {
            self = .launcherGrid(newConfig)
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ConfigType: String, Codable {
        case list
        case table
        case singleKeyPicker
        case homeRowMods
        case tapHoldPicker
        case layerPresetPicker
        case launcherGrid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ConfigType.self, forKey: .type)

        switch type {
        case .list:
            self = .list
        case .table:
            self = .table
        case .singleKeyPicker:
            let config = try SingleKeyPickerConfig(from: decoder)
            self = .singleKeyPicker(config)
        case .homeRowMods:
            let config = try HomeRowModsConfig(from: decoder)
            self = .homeRowMods(config)
        case .tapHoldPicker:
            let config = try TapHoldPickerConfig(from: decoder)
            self = .tapHoldPicker(config)
        case .layerPresetPicker:
            let config = try LayerPresetPickerConfig(from: decoder)
            self = .layerPresetPicker(config)
        case .launcherGrid:
            let config = try LauncherGridConfig(from: decoder)
            self = .launcherGrid(config)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .list:
            try container.encode(ConfigType.list, forKey: .type)
        case .table:
            try container.encode(ConfigType.table, forKey: .type)
        case let .singleKeyPicker(config):
            try container.encode(ConfigType.singleKeyPicker, forKey: .type)
            try config.encode(to: encoder)
        case let .homeRowMods(config):
            try container.encode(ConfigType.homeRowMods, forKey: .type)
            try config.encode(to: encoder)
        case let .tapHoldPicker(config):
            try container.encode(ConfigType.tapHoldPicker, forKey: .type)
            try config.encode(to: encoder)
        case let .layerPresetPicker(config):
            try container.encode(ConfigType.layerPresetPicker, forKey: .type)
            try config.encode(to: encoder)
        case let .launcherGrid(config):
            try container.encode(ConfigType.launcherGrid, forKey: .type)
            try config.encode(to: encoder)
        }
    }
}

// MARK: - Single Key Picker Configuration

/// Configuration for single-key remapping picker.
///
/// Used when a single input key (e.g., Caps Lock, Escape) can be remapped
/// to one of several preset output options.
public struct SingleKeyPickerConfig: Codable, Equatable, Sendable {
    /// The input key being remapped (e.g., "caps", "esc")
    public let inputKey: String

    /// Available preset output options
    public let presetOptions: [SingleKeyPreset]

    /// Currently selected output (can be preset or custom)
    public var selectedOutput: String?

    public init(
        inputKey: String,
        presetOptions: [SingleKeyPreset],
        selectedOutput: String? = nil
    ) {
        self.inputKey = inputKey
        self.presetOptions = presetOptions
        self.selectedOutput = selectedOutput
    }
}

// MARK: - Tap-Hold Picker Configuration

/// Configuration for tap-hold key remapping picker.
///
/// Used when a key has separate actions for tap (quick press) and hold.
/// For example, Caps Lock: tap → Escape, hold → Hyper.
public struct TapHoldPickerConfig: Codable, Equatable, Sendable {
    /// The input key being remapped (e.g., "caps")
    public let inputKey: String

    /// Available preset options for tap action
    public let tapOptions: [SingleKeyPreset]

    /// Available preset options for hold action
    public let holdOptions: [SingleKeyPreset]

    /// Currently selected tap action
    public var selectedTapOutput: String?

    /// Currently selected hold action
    public var selectedHoldOutput: String?

    public init(
        inputKey: String,
        tapOptions: [SingleKeyPreset],
        holdOptions: [SingleKeyPreset],
        selectedTapOutput: String? = nil,
        selectedHoldOutput: String? = nil
    ) {
        self.inputKey = inputKey
        self.tapOptions = tapOptions
        self.holdOptions = holdOptions
        self.selectedTapOutput = selectedTapOutput
        self.selectedHoldOutput = selectedHoldOutput
    }
}

// MARK: - Layer Preset Picker Configuration

/// Configuration for layer preset picker.
///
/// Used when a layer has multiple predefined configurations the user can choose from.
/// For example, Symbol Layer with "Mirrored", "Paired Brackets", "Programmer" presets.
public struct LayerPresetPickerConfig: Codable, Equatable, Sendable {
    /// Available layer configuration presets
    public let presets: [LayerPreset]

    /// Currently selected preset ID
    public var selectedPresetId: String?

    public init(
        presets: [LayerPreset],
        selectedPresetId: String? = nil
    ) {
        self.presets = presets
        self.selectedPresetId = selectedPresetId
    }

    /// Get the currently selected preset, if any
    public var selectedPreset: LayerPreset? {
        guard let id = selectedPresetId else { return nil }
        return presets.first { $0.id == id }
    }

    /// Get mappings from the selected preset, or empty if none selected
    public var selectedMappings: [KeyMapping] {
        selectedPreset?.mappings ?? []
    }
}

// MARK: - Launcher Grid Configuration

/// Activation mode for the launcher layer
public enum LauncherActivationMode: String, Codable, Equatable, Sendable {
    /// Hold Hyper key to activate launcher layer
    case holdHyper
    /// Leader → L sequence to activate launcher layer
    case leaderSequence
}

/// Target for a launcher mapping - either an app or a URL
public enum LauncherTarget: Codable, Equatable, Sendable {
    case app(name: String, bundleId: String?)
    case url(String)

    /// Display name for the target
    public var displayName: String {
        switch self {
        case let .app(name, _):
            name
        case let .url(urlString):
            urlString
        }
    }

    /// Whether this target is an app (vs URL)
    public var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    /// Generate the Kanata output string for this target
    public var kanataOutput: String {
        switch self {
        case let .app(name, _):
            "(push-msg \"launch:\(name.lowercased())\")"
        case let .url(urlString):
            "(push-msg \"open:\(urlString)\")"
        }
    }
}

/// A single mapping in the launcher grid
public struct LauncherMapping: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var key: String
    public var target: LauncherTarget
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        key: String,
        target: LauncherTarget,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.target = target
        self.isEnabled = isEnabled
    }
}

/// Configuration for the launcher grid display style
public struct LauncherGridConfig: Codable, Equatable, Sendable {
    public var activationMode: LauncherActivationMode
    public var mappings: [LauncherMapping]
    /// Whether the user has seen the welcome dialog
    public var hasSeenWelcome: Bool

    public init(
        activationMode: LauncherActivationMode = .holdHyper,
        mappings: [LauncherMapping] = LauncherGridConfig.defaultMappings,
        hasSeenWelcome: Bool = false
    ) {
        self.activationMode = activationMode
        self.mappings = mappings
        self.hasSeenWelcome = hasSeenWelcome
    }

    /// Default configuration with preset app and website mappings
    public static var defaultConfig: LauncherGridConfig {
        LauncherGridConfig(activationMode: .holdHyper, mappings: defaultMappings, hasSeenWelcome: false)
    }

    /// Available number keys for website shortcuts (used when adding from browser history)
    public static let availableNumberKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// Default app and website mappings
    public static var defaultMappings: [LauncherMapping] {
        // Apps (letters)
        let appMappings: [LauncherMapping] = [
            LauncherMapping(key: "s", target: .app(name: "Safari", bundleId: "com.apple.Safari")),
            LauncherMapping(key: "t", target: .app(name: "Terminal", bundleId: "com.apple.Terminal")),
            LauncherMapping(key: "f", target: .app(name: "Finder", bundleId: "com.apple.finder")),
            LauncherMapping(key: "m", target: .app(name: "Messages", bundleId: "com.apple.MobileSMS")),
            LauncherMapping(key: "e", target: .app(name: "Mail", bundleId: "com.apple.mail")),
            LauncherMapping(key: "c", target: .app(name: "Calendar", bundleId: "com.apple.iCal")),
            LauncherMapping(key: "n", target: .app(name: "Notes", bundleId: "com.apple.Notes")),
            LauncherMapping(key: "u", target: .app(name: "Music", bundleId: "com.apple.Music")),
            LauncherMapping(key: "p", target: .app(name: "Photos", bundleId: "com.apple.Photos")),
            LauncherMapping(key: "a", target: .app(name: "App Store", bundleId: "com.apple.AppStore")),
            LauncherMapping(key: "v", target: .app(name: "VS Code", bundleId: "com.microsoft.VSCode")),
            LauncherMapping(key: "o", target: .app(name: "Obsidian", bundleId: "md.obsidian")),
            LauncherMapping(key: "d", target: .app(name: "Discord", bundleId: "com.hnc.Discord")),
            LauncherMapping(key: "k", target: .app(name: "Slack", bundleId: "com.tinyspeck.slackmacgap")),
            LauncherMapping(key: "z", target: .app(name: "Zoom", bundleId: "us.zoom.xos"))
        ]

        // Websites (numbers)
        let websiteMappings: [LauncherMapping] = [
            LauncherMapping(key: "1", target: .url("github.com")),
            LauncherMapping(key: "2", target: .url("google.com")),
            LauncherMapping(key: "3", target: .url("youtube.com")),
            LauncherMapping(key: "4", target: .url("x.com")),
            LauncherMapping(key: "5", target: .url("reddit.com")),
            LauncherMapping(key: "6", target: .url("chatgpt.com")),
            LauncherMapping(key: "7", target: .url("claude.ai")),
            LauncherMapping(key: "8", target: .url("stackoverflow.com")),
            LauncherMapping(key: "9", target: .url("linkedin.com")),
            LauncherMapping(key: "0", target: .url("notion.so"))
        ]

        return appMappings + websiteMappings
    }
}
