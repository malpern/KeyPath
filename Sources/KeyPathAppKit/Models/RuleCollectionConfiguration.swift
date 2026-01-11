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

    /// Home Row Layer Toggles: visual keyboard with layer assignments
    case homeRowLayerToggles(HomeRowLayerTogglesConfig)

    /// Chord Groups: Ben Vallack-style multi-key combinations (defchords)
    case chordGroups(ChordGroupsConfig)

    /// Sequences: Leader key sequences that activate layers (defseq)
    case sequences(SequencesConfig)

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
        case .homeRowLayerToggles: .homeRowLayerToggles
        case .chordGroups: .chordGroups
        case .sequences: .sequences
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

    /// Extract home row layer toggles config if this is a `.homeRowLayerToggles` case
    public var homeRowLayerTogglesConfig: HomeRowLayerTogglesConfig? {
        if case let .homeRowLayerToggles(config) = self { return config }
        return nil
    }

    /// Extract chord groups config if this is a `.chordGroups` case
    public var chordGroupsConfig: ChordGroupsConfig? {
        if case let .chordGroups(config) = self { return config }
        return nil
    }

    /// Extract sequences config if this is a `.sequences` case
    public var sequencesConfig: SequencesConfig? {
        if case let .sequences(config) = self { return config }
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

    /// Update the home row layer toggles config
    public mutating func updateHomeRowLayerTogglesConfig(_ newConfig: HomeRowLayerTogglesConfig) {
        if case .homeRowLayerToggles = self {
            self = .homeRowLayerToggles(newConfig)
        }
    }

    /// Update the chord groups config
    public mutating func updateChordGroupsConfig(_ newConfig: ChordGroupsConfig) {
        if case .chordGroups = self {
            self = .chordGroups(newConfig)
        }
    }

    /// Update the sequences config
    public mutating func updateSequencesConfig(_ newConfig: SequencesConfig) {
        if case .sequences = self {
            self = .sequences(newConfig)
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
        case homeRowLayerToggles
        case chordGroups
        case sequences
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
        case .homeRowLayerToggles:
            let config = try HomeRowLayerTogglesConfig(from: decoder)
            self = .homeRowLayerToggles(config)
        case .chordGroups:
            let config = try ChordGroupsConfig(from: decoder)
            self = .chordGroups(config)
        case .sequences:
            let config = try SequencesConfig(from: decoder)
            self = .sequences(config)
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
        case let .homeRowLayerToggles(config):
            try container.encode(ConfigType.homeRowLayerToggles, forKey: .type)
            try config.encode(to: encoder)
        case let .chordGroups(config):
            try container.encode(ConfigType.chordGroups, forKey: .type)
            try config.encode(to: encoder)
        case let .sequences(config):
            try container.encode(ConfigType.sequences, forKey: .type)
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
    /// Hyper key to activate launcher layer (tap or hold based on hyperTriggerMode)
    case holdHyper // Keep name for backward compatibility
    /// Leader → L sequence to activate launcher layer
    case leaderSequence

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .holdHyper: "Hyper"
        case .leaderSequence: "Leader → L"
        }
    }
}

/// How the Hyper key triggers the launcher layer
public enum HyperTriggerMode: String, Codable, Equatable, Sendable {
    /// Tap Hyper to toggle launcher layer
    case tap
    /// Hold Hyper to activate launcher layer (releases on key up)
    case hold

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        }
    }

    /// Description for UI
    public var description: String {
        switch self {
        case .tap: "Tap Hyper to toggle the launcher on/off"
        case .hold: "Hold Hyper to show launcher, release to hide"
        }
    }
}

/// Target for a launcher mapping - app, URL, folder, or script
public enum LauncherTarget: Codable, Equatable, Sendable {
    case app(name: String, bundleId: String?)
    case url(String)
    case folder(path: String, name: String?)
    case script(path: String, name: String?)

    /// Display name for the target
    public var displayName: String {
        switch self {
        case let .app(name, _):
            name
        case let .url(urlString):
            urlString
        case let .folder(path, name):
            name ?? URL(fileURLWithPath: path).lastPathComponent
        case let .script(path, name):
            name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    /// Whether this target is an app
    public var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    /// Whether this target is a URL
    public var isURL: Bool {
        if case .url = self { return true }
        return false
    }

    /// Whether this target is a folder
    public var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    /// Whether this target is a script
    public var isScript: Bool {
        if case .script = self { return true }
        return false
    }

    /// Generate the Kanata output string for this target
    public var kanataOutput: String {
        switch self {
        case let .app(name, _):
            "(push-msg \"launch:\(name.lowercased())\")"
        case let .url(urlString):
            "(push-msg \"open:\(urlString)\")"
        case let .folder(path, _):
            "(push-msg \"folder:\(path)\")"
        case let .script(path, _):
            "(push-msg \"script:\(path)\")"
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
    /// How Hyper key triggers the launcher (only used when activationMode is .holdHyper)
    public var hyperTriggerMode: HyperTriggerMode
    public var mappings: [LauncherMapping]
    /// Whether the user has seen the welcome dialog
    public var hasSeenWelcome: Bool

    public init(
        activationMode: LauncherActivationMode = .holdHyper,
        hyperTriggerMode: HyperTriggerMode = .hold,
        mappings: [LauncherMapping] = LauncherGridConfig.defaultMappings,
        hasSeenWelcome: Bool = false
    ) {
        self.activationMode = activationMode
        self.hyperTriggerMode = hyperTriggerMode
        self.mappings = mappings
        self.hasSeenWelcome = hasSeenWelcome
    }

    /// Default configuration with preset app and website mappings
    public static var defaultConfig: LauncherGridConfig {
        LauncherGridConfig(activationMode: .holdHyper, hyperTriggerMode: .hold, mappings: defaultMappings, hasSeenWelcome: false)
    }

    // Custom decoding to handle missing hyperTriggerMode in existing configs
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationMode = try container.decode(LauncherActivationMode.self, forKey: .activationMode)
        hyperTriggerMode = try container.decodeIfPresent(HyperTriggerMode.self, forKey: .hyperTriggerMode) ?? .hold
        mappings = try container.decode([LauncherMapping].self, forKey: .mappings)
        hasSeenWelcome = try container.decode(Bool.self, forKey: .hasSeenWelcome)
    }

    private enum CodingKeys: String, CodingKey {
        case activationMode, hyperTriggerMode, mappings, hasSeenWelcome
    }

    /// Available number keys for website shortcuts (used when adding from browser history)
    public static let availableNumberKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// Default app and website mappings
    /// Home row prioritized for most-used apps and sites
    public static var defaultMappings: [LauncherMapping] {
        // Home row - most used (asdfghjkl)
        let homeRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "a", target: .app(name: "Calendar", bundleId: "com.apple.iCal")),
            LauncherMapping(key: "s", target: .app(name: "Safari", bundleId: "com.apple.Safari")),
            LauncherMapping(key: "d", target: .app(name: "Terminal", bundleId: "com.apple.Terminal")),
            LauncherMapping(key: "f", target: .app(name: "Finder", bundleId: "com.apple.finder")),
            LauncherMapping(key: "g", target: .url("chatgpt.com")),
            LauncherMapping(key: "h", target: .url("youtube.com")),
            LauncherMapping(key: "j", target: .url("x.com")),
            LauncherMapping(key: "k", target: .app(name: "Messages", bundleId: "com.apple.MobileSMS")),
            LauncherMapping(key: "l", target: .url("linkedin.com"))
        ]

        // Top row (qwertyuiop)
        let topRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "e", target: .app(name: "Mail", bundleId: "com.apple.mail")),
            LauncherMapping(key: "r", target: .url("reddit.com")),
            LauncherMapping(key: "u", target: .app(name: "Music", bundleId: "com.apple.Music")),
            LauncherMapping(key: "i", target: .url("claude.ai")),
            LauncherMapping(key: "o", target: .app(name: "Obsidian", bundleId: "md.obsidian")),
            LauncherMapping(key: "p", target: .app(name: "Photos", bundleId: "com.apple.Photos"))
        ]

        // Bottom row (zxcvbnm)
        let bottomRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "z", target: .app(name: "Zoom", bundleId: "us.zoom.xos")),
            LauncherMapping(key: "x", target: .app(name: "Slack", bundleId: "com.tinyspeck.slackmacgap")),
            LauncherMapping(key: "c", target: .app(name: "Discord", bundleId: "com.hnc.Discord")),
            LauncherMapping(key: "v", target: .app(name: "VS Code", bundleId: "com.microsoft.VSCode")),
            LauncherMapping(key: "n", target: .app(name: "Notes", bundleId: "com.apple.Notes"))
        ]

        // Number row (websites + folders + scripts)
        let numberRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "1", target: .url("github.com")),
            LauncherMapping(key: "2", target: .url("google.com")),
            LauncherMapping(key: "3", target: .url("notion.so")),
            LauncherMapping(key: "4", target: .url("stackoverflow.com")),
            LauncherMapping(key: "5", target: .folder(path: "~/Documents", name: "Documents")),
            LauncherMapping(key: "6", target: .folder(path: "~/Downloads", name: "Downloads")),
            LauncherMapping(key: "7", target: .folder(path: "~/Desktop", name: "Desktop"))
        ]

        // Note: Script examples are not included by default since script execution requires
        // explicit user opt-in via Settings > Security. Users can add scripts manually.

        return homeRowMappings + topRowMappings + bottomRowMappings + numberRowMappings
    }
}
