import Foundation

/// Timing UI complexity level for home row mods
public enum TimingMode: String, Codable, Sendable {
    case basic // Shared timing, no per-finger sliders
    case precision // Per-finger sensitivity visible
}

/// Configuration for Home Row Mods collection
public struct HomeRowModsConfig: Codable, Equatable, Sendable {
    /// Which keys are enabled for home row mods
    public var enabledKeys: Set<String>

    /// Modifier assignment for each key
    public var modifierAssignments: [String: String]

    /// Layer assignment for each key when hold mode is `.layers`
    public var layerAssignments: [String: String]

    /// Hold behavior mode
    public var holdMode: HomeRowHoldMode

    /// True once the user has explicitly selected a hold mode in the UI.
    /// Used to keep new/legacy configs defaulting to modifiers until user opts into layers.
    public var hasUserSelectedHoldMode: Bool

    /// Layer activation mode used when `holdMode == .layers`
    public var layerToggleMode: LayerToggleMode

    /// Timing configuration
    public var timing: TimingConfig

    /// Key selection mode
    public var keySelection: KeySelection

    /// Whether advanced options are shown
    public var showAdvanced: Bool

    /// Timing UI complexity level
    public var timingMode: TimingMode

    /// Whether expert raw timing fields are expanded
    public var showExpertTiming: Bool

    public init(
        enabledKeys: Set<String> = ["a", "s", "d", "f", "j", "k", "l", ";"],
        modifierAssignments: [String: String] = HomeRowModsConfig.cagsMacDefault,
        layerAssignments: [String: String] = HomeRowModsConfig.defaultLayerAssignments,
        holdMode: HomeRowHoldMode = .modifiers,
        hasUserSelectedHoldMode: Bool = false,
        layerToggleMode: LayerToggleMode = .whileHeld,
        timing: TimingConfig = .default,
        keySelection: KeySelection = .both,
        showAdvanced: Bool = false,
        timingMode: TimingMode = .basic,
        showExpertTiming: Bool = false
    ) {
        self.enabledKeys = enabledKeys
        self.modifierAssignments = modifierAssignments
        self.layerAssignments = layerAssignments
        self.holdMode = holdMode
        self.hasUserSelectedHoldMode = hasUserSelectedHoldMode
        self.layerToggleMode = layerToggleMode
        self.timing = timing
        self.keySelection = keySelection
        self.showAdvanced = showAdvanced
        self.timingMode = timingMode
        self.showExpertTiming = showExpertTiming
    }

    /// Mac-first CAGS mapping
    /// Left hand: Shift (pinky), Control (ring), Option (middle), Command (index)
    /// Right hand: Command (index), Option (middle), Control (ring), Shift (pinky)
    public static let cagsMacDefault: [String: String] = [
        "a": "lsft", "s": "lctl", "d": "lalt", "f": "lmet",
        "j": "rmet", "k": "ralt", "l": "rctl", ";": "rsft"
    ]

    /// Windows/Linux oriented GACS mapping (Super/GUI on pinky)
    public static let gacsWindows: [String: String] = [
        "a": "lmet", "s": "lalt", "d": "lctl", "f": "lsft",
        "j": "rsft", "k": "rctl", "l": "ralt", ";": "rmet"
    ]

    /// Default layer assignments (community standard mirror setup)
    public static let defaultLayerAssignments: [String: String] = [
        "a": "fun", "s": "num", "d": "sym", "f": "nav",
        "j": "nav", "k": "sym", "l": "num", ";": "fun"
    ]

    /// Left hand keys
    public static let leftHandKeys = ["a", "s", "d", "f"]

    /// Right hand keys
    public static let rightHandKeys = ["j", "k", "l", ";"]

    /// All home row keys
    public static let allKeys = leftHandKeys + rightHandKeys

    private enum CodingKeys: String, CodingKey {
        case enabledKeys
        case modifierAssignments
        case layerAssignments
        case holdMode
        case hasUserSelectedHoldMode
        case layerToggleMode
        case timing
        case keySelection
        case showAdvanced
        case timingMode
        case showExpertTiming
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledKeys = try container.decodeIfPresent(Set<String>.self, forKey: .enabledKeys) ?? Set(Self.allKeys)
        modifierAssignments = try container.decodeIfPresent([String: String].self, forKey: .modifierAssignments) ?? Self.cagsMacDefault
        var decoded = try container.decodeIfPresent([String: String].self, forKey: .layerAssignments) ?? Self.defaultLayerAssignments
        // Migrate legacy layer names to community standard names
        for (key, value) in decoded {
            switch value {
            case "sys1": decoded[key] = "num"
            case "sys2": decoded[key] = "sym"
            default: break
            }
        }
        layerAssignments = decoded
        holdMode = try container.decodeIfPresent(HomeRowHoldMode.self, forKey: .holdMode) ?? .modifiers
        hasUserSelectedHoldMode = try container.decodeIfPresent(Bool.self, forKey: .hasUserSelectedHoldMode) ?? false
        layerToggleMode = try container.decodeIfPresent(LayerToggleMode.self, forKey: .layerToggleMode) ?? .whileHeld
        timing = try container.decodeIfPresent(TimingConfig.self, forKey: .timing) ?? .default
        keySelection = try container.decodeIfPresent(KeySelection.self, forKey: .keySelection) ?? .both
        showAdvanced = try container.decodeIfPresent(Bool.self, forKey: .showAdvanced) ?? false
        timingMode = try container.decodeIfPresent(TimingMode.self, forKey: .timingMode) ?? .basic
        showExpertTiming = try container.decodeIfPresent(Bool.self, forKey: .showExpertTiming) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledKeys, forKey: .enabledKeys)
        try container.encode(modifierAssignments, forKey: .modifierAssignments)
        try container.encode(layerAssignments, forKey: .layerAssignments)
        try container.encode(holdMode, forKey: .holdMode)
        try container.encode(hasUserSelectedHoldMode, forKey: .hasUserSelectedHoldMode)
        try container.encode(layerToggleMode, forKey: .layerToggleMode)
        try container.encode(timing, forKey: .timing)
        try container.encode(keySelection, forKey: .keySelection)
        try container.encode(showAdvanced, forKey: .showAdvanced)
        try container.encode(timingMode, forKey: .timingMode)
        try container.encode(showExpertTiming, forKey: .showExpertTiming)
    }
}

/// Hold behavior for Home Row Mods
public enum HomeRowHoldMode: String, Codable, Sendable {
    case modifiers
    case layers

    public var displayName: String {
        switch self {
        case .modifiers: "Modifiers"
        case .layers: "Layers"
        }
    }
}

/// Key selection mode for home row mods
public enum KeySelection: String, Codable, Sendable {
    case both
    case leftOnly
    case rightOnly
    case custom

    public var enabledKeys: Set<String> {
        switch self {
        case .both:
            Set(HomeRowModsConfig.allKeys)
        case .leftOnly:
            Set(HomeRowModsConfig.leftHandKeys)
        case .rightOnly:
            Set(HomeRowModsConfig.rightHandKeys)
        case .custom:
            [] // User selects individually
        }
    }
}

/// Timing configuration for home row mods
public struct TimingConfig: Codable, Equatable, Sendable {
    public var tapWindow: Int
    public var holdDelay: Int
    public var quickTapEnabled: Bool
    /// Extra ms added to tap window when quick tap is enabled (helps prevent accidental holds)
    public var quickTapTermMs: Int
    /// Optional per-key tap offsets (ms). Positive values extend the tap window for that key.
    public var tapOffsets: [String: Int]
    /// Optional per-key hold offsets (ms). Positive values extend the hold delay for that key.
    public var holdOffsets: [String: Int]

    public init(
        tapWindow: Int = 200,
        holdDelay: Int = 150,
        quickTapEnabled: Bool = false,
        quickTapTermMs: Int = 0,
        tapOffsets: [String: Int] = [:],
        holdOffsets: [String: Int] = [:]
    ) {
        self.tapWindow = tapWindow
        self.holdDelay = holdDelay
        self.quickTapEnabled = quickTapEnabled
        self.quickTapTermMs = quickTapTermMs
        self.tapOffsets = tapOffsets
        self.holdOffsets = holdOffsets
    }

    private enum CodingKeys: String, CodingKey {
        case tapWindow
        case holdDelay
        case quickTapEnabled
        case quickTapTermMs
        case tapOffsets
        case holdOffsets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tapWindow = try container.decodeIfPresent(Int.self, forKey: .tapWindow) ?? 200
        holdDelay = try container.decodeIfPresent(Int.self, forKey: .holdDelay) ?? 150
        quickTapEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickTapEnabled) ?? false
        quickTapTermMs = try container.decodeIfPresent(Int.self, forKey: .quickTapTermMs) ?? 0
        tapOffsets = try container.decodeIfPresent([String: Int].self, forKey: .tapOffsets) ?? [:]
        holdOffsets = try container.decodeIfPresent([String: Int].self, forKey: .holdOffsets) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tapWindow, forKey: .tapWindow)
        try container.encode(holdDelay, forKey: .holdDelay)
        try container.encode(quickTapEnabled, forKey: .quickTapEnabled)
        try container.encode(quickTapTermMs, forKey: .quickTapTermMs)
        try container.encode(tapOffsets, forKey: .tapOffsets)
        try container.encode(holdOffsets, forKey: .holdOffsets)
    }

    public static let `default` = TimingConfig()
}
