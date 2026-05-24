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

    /// Auto Shift Symbols: hold symbol keys slightly longer for shifted output
    case autoShiftSymbols(AutoShiftSymbolsConfig)

    /// Key Repeat Control: kanata-managed key repeat with per-key overrides
    case keyRepeatControl(KeyRepeatControlConfig)

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
        case .autoShiftSymbols: .autoShiftSymbols
        case .keyRepeatControl: .keyRepeatControl
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

    /// Extract auto shift symbols config if this is a `.autoShiftSymbols` case
    public var autoShiftSymbolsConfig: AutoShiftSymbolsConfig? {
        if case let .autoShiftSymbols(config) = self { return config }
        return nil
    }

    /// Extract key repeat control config if this is a `.keyRepeatControl` case
    public var keyRepeatControlConfig: KeyRepeatControlConfig? {
        if case let .keyRepeatControl(config) = self { return config }
        return nil
    }

    // MARK: - Display Settings (for comparison dialogs)

    struct DisplaySetting: Equatable {
        let label: String
        let value: String
    }

    struct SettingDiff {
        let label: String
        let current: String
        let proposed: String
    }

    var displaySettings: [DisplaySetting] {
        switch self {
        case let .tapHoldPicker(config):
            var settings: [DisplaySetting] = []
            if let tap = config.selectedTapOutput {
                let label = config.tapOptions.first { $0.output == tap }?.label ?? tap
                settings.append(DisplaySetting(label: "Tap Action", value: label))
            }
            if let hold = config.selectedHoldOutput {
                let label = config.holdOptions.first { $0.output == hold }?.label ?? hold
                settings.append(DisplaySetting(label: "Hold Action", value: label))
            }
            return settings

        case let .homeRowMods(config):
            var settings: [DisplaySetting] = []
            let sortedKeys = config.enabledKeys.sorted()
            settings.append(DisplaySetting(
                label: "Modifier Keys",
                value: sortedKeys.isEmpty ? "None" : sortedKeys.joined(separator: ", ").uppercased()
            ))
            let modSummary = sortedKeys.compactMap { key in
                config.modifierAssignments[key].map { mod in
                    "\(key.uppercased())=\(Self.modifierDisplayName(mod))"
                }
            }.joined(separator: ", ")
            if !modSummary.isEmpty {
                settings.append(DisplaySetting(label: "Layout", value: modSummary))
            }
            settings.append(DisplaySetting(
                label: "Hold Timing",
                value: "\(config.timing.tapWindow) ms"
            ))
            return settings

        case let .homeRowLayerToggles(config):
            var settings: [DisplaySetting] = []
            let sortedKeys = config.enabledKeys.sorted()
            settings.append(DisplaySetting(
                label: "Toggle Keys",
                value: sortedKeys.isEmpty ? "None" : sortedKeys.joined(separator: ", ").uppercased()
            ))
            let layerSummary = sortedKeys.compactMap { key in
                config.layerAssignments[key].map { "\(key.uppercased())→\($0)" }
            }.joined(separator: ", ")
            if !layerSummary.isEmpty {
                settings.append(DisplaySetting(label: "Layers", value: layerSummary))
            }
            return settings

        default:
            return []
        }
    }

    static func diffSettings(
        current: RuleCollectionConfiguration,
        proposed: RuleCollectionConfiguration
    ) -> [SettingDiff] {
        let currentSettings = current.displaySettings
        let proposedSettings = proposed.displaySettings

        var diffs: [SettingDiff] = []
        for proposed in proposedSettings {
            let currentMatch = currentSettings.first { $0.label == proposed.label }
            let currentValue = currentMatch?.value ?? "—"
            if currentValue != proposed.value {
                diffs.append(SettingDiff(
                    label: proposed.label,
                    current: currentValue,
                    proposed: proposed.value
                ))
            }
        }
        return diffs
    }

    private static func modifierDisplayName(_ mod: String) -> String {
        switch mod {
        case "lctl", "rctl": "⌃"
        case "lalt", "ralt": "⌥"
        case "lsft", "rsft": "⇧"
        case "lmet", "rmet": "⌘"
        default: mod
        }
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

    /// Update the auto shift symbols config
    public mutating func updateAutoShiftSymbolsConfig(_ newConfig: AutoShiftSymbolsConfig) {
        if case .autoShiftSymbols = self {
            self = .autoShiftSymbols(newConfig)
        }
    }

    /// Update the key repeat control config
    public mutating func updateKeyRepeatControlConfig(_ newConfig: KeyRepeatControlConfig) {
        if case .keyRepeatControl = self {
            self = .keyRepeatControl(newConfig)
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
        case autoShiftSymbols
        case keyRepeatControl
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
        case .autoShiftSymbols:
            let config = try AutoShiftSymbolsConfig(from: decoder)
            self = .autoShiftSymbols(config)
        case .keyRepeatControl:
            let config = try KeyRepeatControlConfig(from: decoder)
            self = .keyRepeatControl(config)
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
        case let .autoShiftSymbols(config):
            try container.encode(ConfigType.autoShiftSymbols, forKey: .type)
            try config.encode(to: encoder)
        case let .keyRepeatControl(config):
            try container.encode(ConfigType.keyRepeatControl, forKey: .type)
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

/// A single mapping in the launcher grid
public struct LauncherMapping: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var key: String
    public var action: KeyAction
    public var isEnabled: Bool
    public var customIconPath: String?
    public var userDescription: String?

    public init(
        id: UUID = UUID(),
        key: String,
        action: KeyAction,
        isEnabled: Bool = true,
        customIconPath: String? = nil,
        userDescription: String? = nil
    ) {
        self.id = id
        self.key = key
        self.action = action
        self.isEnabled = isEnabled
        self.customIconPath = customIconPath
        self.userDescription = userDescription
    }

    public var tooltip: String {
        userDescription ?? action.autoDescription
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

    /// Custom decoding to handle missing hyperTriggerMode in existing configs
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

    /// Suggested key order for auto-adding launcher mappings (home row first, then numbers, then punctuation).
    public static let suggestionKeyOrder: [String] = {
        let lettersAndNumbers = Array("asdfghjklqwertyuiopzxcvbnm1234567890").map { String($0) }
        return lettersAndNumbers + punctuationKeyOrder
    }()

    /// Full set of supported launcher keys in canonical (Kanata) form.
    /// Includes suggestion keys plus additional manually-assignable keys (enter, tab, space, backspace).
    public static let allowedKeyOrder: [String] = suggestionKeyOrder + manualOnlyKeys

    private static let manualOnlyKeys: [String] = [
        "enter", "tab", "space", "backspace",
        "rightshift"
    ]

    private static let allowedKeySet = Set(allowedKeyOrder)

    private static let punctuationKeyOrder: [String] = [
        "semicolon",
        "apostrophe",
        "comma",
        "dot",
        "slash",
        "minus",
        "equal",
        "grave",
        "leftbrace",
        "rightbrace",
        "backslash"
    ]

    private static let punctuationAliases: [String: String] = [
        ";": "semicolon",
        "'": "apostrophe",
        ",": "comma",
        ".": "dot",
        "/": "slash",
        "-": "minus",
        "=": "equal",
        "`": "grave",
        "[": "leftbrace",
        "]": "rightbrace",
        "\\": "backslash"
    ]

    /// Normalize a key for launcher mappings (lowercased, canonical).
    public static func normalizeKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "" }
        if let canonical = punctuationAliases[trimmed] {
            return canonical
        }
        if allowedKeySet.contains(trimmed) {
            return trimmed
        }
        return String(trimmed.prefix(1))
    }

    /// Validate that a launcher key is supported (canonical or punctuation alias).
    public static func isValidKey(_ key: String) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let canonical = punctuationAliases[normalized] {
            return allowedKeySet.contains(canonical)
        }
        return allowedKeySet.contains(normalized)
    }

    /// Default app and website mappings
    /// Minimal set — additional suggestions come from activity tracking and browser history
    public static var defaultMappings: [LauncherMapping] {
        let homeRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "a", action: .launchApp(name: "Calendar", bundleId: "com.apple.iCal")),
            LauncherMapping(key: "f", action: .launchApp(name: "Finder", bundleId: "com.apple.finder")),
            LauncherMapping(key: "h", action: .openURL("youtube.com")),
            LauncherMapping(key: "j", action: .openURL("x.com")),
            LauncherMapping(key: "k", action: .launchApp(name: "Messages", bundleId: "com.apple.MobileSMS")),
            LauncherMapping(key: "l", action: .openURL("linkedin.com")),
        ]

        let topRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "r", action: .openURL("reddit.com")),
        ]

        let bottomRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "z", action: .launchApp(name: "Zoom", bundleId: "us.zoom.xos")),
            LauncherMapping(key: "x", action: .launchApp(name: "Slack", bundleId: "com.tinyspeck.slackmacgap")),
            LauncherMapping(key: "c", action: .launchApp(name: "Discord", bundleId: "com.hnc.Discord")),
        ]

        let numberRowMappings: [LauncherMapping] = [
            LauncherMapping(key: "1", action: .openURL("github.com")),
            LauncherMapping(key: "2", action: .openURL("google.com")),
        ]

        return homeRowMappings + topRowMappings + bottomRowMappings + numberRowMappings
    }
}

// MARK: - Auto Shift Symbols Configuration

/// Configuration for Auto Shift Symbols collection.
///
/// Generates tap-hold behaviors where tap produces the base key
/// and hold produces the shifted variant (e.g., tap `.` → `.`, hold `.` → `>`).
public struct AutoShiftSymbolsConfig: Codable, Equatable, Sendable {
    /// Timeout in milliseconds — hold longer than this to get shifted output
    public var timeoutMs: Int

    /// When true, contributes to global require-prior-idle to prevent accidental shifts during fast typing
    public var protectFastTyping: Bool

    /// Which keys are enabled for auto-shift behavior
    public var enabledKeys: Set<String>

    /// Default timeout for auto-shift (milliseconds)
    public static let defaultTimeoutMs = 180

    /// The full set of symbol keys eligible for auto-shift
    public static let allSymbolKeys: [String] = [
        "grv", "min", "eql", "lbrc", "rbrc", "bsls", "scln", "apos", "comm", "dot", "slsh"
    ]

    /// Display labels for symbol keys: kanata key → (normal, shifted)
    public static let shiftedLabels: [String: (normal: String, shifted: String)] = [
        "grv": ("`", "~"),
        "min": ("-", "_"),
        "eql": ("=", "+"),
        "lbrc": ("[", "{"),
        "rbrc": ("]", "}"),
        "bsls": ("\\", "|"),
        "scln": (";", ":"),
        "apos": ("'", "\""),
        "comm": (",", "<"),
        "dot": (".", ">"),
        "slsh": ("/", "?")
    ]

    public init(
        timeoutMs: Int = AutoShiftSymbolsConfig.defaultTimeoutMs,
        protectFastTyping: Bool = true,
        enabledKeys: Set<String>? = nil
    ) {
        self.timeoutMs = timeoutMs
        self.protectFastTyping = protectFastTyping
        self.enabledKeys = enabledKeys ?? Set(AutoShiftSymbolsConfig.allSymbolKeys)
    }
}

// MARK: - Key Repeat Control Configuration

/// A per-key repeat rate override within the managed-repeat system.
public struct KeyRepeatOverride: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        key
    }

    public let key: String
    public var delayMs: Int
    public var intervalMs: Int

    public init(key: String, delayMs: Int, intervalMs: Int) {
        self.key = key
        self.delayMs = delayMs
        self.intervalMs = intervalMs
    }

    /// Display label for UI (e.g. "bspc" → "⌫ Delete")
    public static let displayLabels: [String: String] = [
        "bspc": "⌫ Delete",
        "del": "⌦ Fwd Delete",
        "left": "← Left",
        "right": "→ Right",
        "up": "↑ Up",
        "down": "↓ Down",
    ]

    public var displayLabel: String {
        Self.displayLabels[key] ?? key
    }
}

/// Configuration for kanata-managed key repeat (defcfg managed-repeat + defrepeat).
///
/// When enabled, kanata takes over key repeat from the OS, eliminating the macOS
/// bug that causes duplicated characters under CPU load. Per-key overrides let
/// users set faster repeat for arrows/delete and slower repeat for alphas.
public struct KeyRepeatControlConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var globalDelayMs: Int
    public var globalIntervalMs: Int
    public var perKeyOverrides: [KeyRepeatOverride]

    public static let defaultGlobalDelayMs = 500
    public static let defaultGlobalIntervalMs = 30

    public static let defaultPerKeyOverrides: [KeyRepeatOverride] = [
        KeyRepeatOverride(key: "left", delayMs: 150, intervalMs: 20),
        KeyRepeatOverride(key: "right", delayMs: 150, intervalMs: 20),
        KeyRepeatOverride(key: "up", delayMs: 150, intervalMs: 20),
        KeyRepeatOverride(key: "down", delayMs: 150, intervalMs: 20),
        KeyRepeatOverride(key: "bspc", delayMs: 210, intervalMs: 20),
        KeyRepeatOverride(key: "del", delayMs: 210, intervalMs: 20),
    ]

    public init(
        isEnabled: Bool = true,
        globalDelayMs: Int = KeyRepeatControlConfig.defaultGlobalDelayMs,
        globalIntervalMs: Int = KeyRepeatControlConfig.defaultGlobalIntervalMs,
        perKeyOverrides: [KeyRepeatOverride] = KeyRepeatControlConfig.defaultPerKeyOverrides
    ) {
        self.isEnabled = isEnabled
        self.globalDelayMs = globalDelayMs
        self.globalIntervalMs = globalIntervalMs
        self.perKeyOverrides = perKeyOverrides
    }

    /// Human-readable repeat speed (keys per second) from interval in ms
    public static func keysPerSecond(fromIntervalMs ms: Int) -> String {
        guard ms > 0 else { return "—" }
        let kps = 1000.0 / Double(ms)
        if kps >= 10 { return "\(Int(kps))/sec" }
        return String(format: "%.1f/sec", kps)
    }

    /// Named presets for common configurations
    public enum Preset: String, CaseIterable, Identifiable {
        case balanced
        case fastNavigation
        case careful

        public var id: String {
            rawValue
        }

        public var label: String {
            switch self {
            case .balanced: "Balanced"
            case .fastNavigation: "Fast Navigation"
            case .careful: "Careful"
            }
        }

        public var description: String {
            switch self {
            case .balanced: "Default"
            case .fastNavigation: "Max speed"
            case .careful: "Prevent accidents"
            }
        }

        public var config: KeyRepeatControlConfig {
            switch self {
            case .balanced:
                KeyRepeatControlConfig()
            case .fastNavigation:
                KeyRepeatControlConfig(
                    globalDelayMs: 300,
                    globalIntervalMs: 20,
                    perKeyOverrides: [
                        KeyRepeatOverride(key: "left", delayMs: 120, intervalMs: 15),
                        KeyRepeatOverride(key: "right", delayMs: 120, intervalMs: 15),
                        KeyRepeatOverride(key: "up", delayMs: 120, intervalMs: 15),
                        KeyRepeatOverride(key: "down", delayMs: 120, intervalMs: 15),
                        KeyRepeatOverride(key: "bspc", delayMs: 150, intervalMs: 15),
                        KeyRepeatOverride(key: "del", delayMs: 150, intervalMs: 15),
                    ]
                )
            case .careful:
                KeyRepeatControlConfig(
                    globalDelayMs: 700,
                    globalIntervalMs: 40,
                    perKeyOverrides: [
                        KeyRepeatOverride(key: "left", delayMs: 300, intervalMs: 25),
                        KeyRepeatOverride(key: "right", delayMs: 300, intervalMs: 25),
                        KeyRepeatOverride(key: "up", delayMs: 300, intervalMs: 25),
                        KeyRepeatOverride(key: "down", delayMs: 300, intervalMs: 25),
                        KeyRepeatOverride(key: "bspc", delayMs: 400, intervalMs: 30),
                        KeyRepeatOverride(key: "del", delayMs: 400, intervalMs: 30),
                    ]
                )
            }
        }
    }
}
