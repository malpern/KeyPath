import Foundation

/// Configuration for Home Row Layer Toggles collection
public struct HomeRowLayerTogglesConfig: Codable, Equatable, Sendable {
    /// Which keys are enabled for layer toggles
    public var enabledKeys: Set<String>

    /// Layer assignment for each key
    public var layerAssignments: [String: String]

    /// Timing configuration
    public var timing: TimingConfig

    /// Key selection mode
    public var keySelection: KeySelection

    /// Toggle mode: layer-while-held (temporary) or layer-toggle (sticky)
    public var toggleMode: LayerToggleMode

    /// Whether advanced options are shown
    public var showAdvanced: Bool

    /// How opposite-hand detection behaves.
    public var oppositeHandMode: OppositeHandMode

    public init(
        enabledKeys: Set<String> = ["a", "s", "d", "f", "j", "k", "l", ";"],
        layerAssignments: [String: String] = HomeRowLayerTogglesConfig.defaultLayerAssignments,
        timing: TimingConfig = .default,
        keySelection: KeySelection = .both,
        toggleMode: LayerToggleMode = .whileHeld,
        showAdvanced: Bool = false,
        oppositeHandMode: OppositeHandMode = .press
    ) {
        self.enabledKeys = enabledKeys
        self.layerAssignments = layerAssignments
        self.timing = timing
        self.keySelection = keySelection
        self.toggleMode = toggleMode
        self.showAdvanced = showAdvanced
        self.oppositeHandMode = oppositeHandMode
    }

    /// Backward-compatible accessor for code that just needs to know if opposite-hand is enabled.
    public var oppositeHandActivation: Bool {
        get { oppositeHandMode.isEnabled }
        set { oppositeHandMode = newValue ? .press : .off }
    }

    private enum CodingKeys: String, CodingKey {
        case enabledKeys
        case layerAssignments
        case timing
        case keySelection
        case toggleMode
        case showAdvanced
        case oppositeHandMode
        case oppositeHandActivation // legacy Bool key for backward-compatible decoding
        case splitHandDetection // legacy key for backward-compatible decoding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledKeys = try container.decodeIfPresent(Set<String>.self, forKey: .enabledKeys) ?? Set(Self.allKeys)
        layerAssignments = try container.decodeIfPresent([String: String].self, forKey: .layerAssignments) ?? Self.defaultLayerAssignments
        timing = try container.decodeIfPresent(TimingConfig.self, forKey: .timing) ?? .default
        keySelection = try container.decodeIfPresent(KeySelection.self, forKey: .keySelection) ?? .both
        toggleMode = try container.decodeIfPresent(LayerToggleMode.self, forKey: .toggleMode) ?? .whileHeld
        showAdvanced = try container.decodeIfPresent(Bool.self, forKey: .showAdvanced) ?? false
        if let mode = try container.decodeIfPresent(OppositeHandMode.self, forKey: .oppositeHandMode) {
            oppositeHandMode = mode
        } else {
            let legacyNew = try container.decodeIfPresent(Bool.self, forKey: .oppositeHandActivation)
            let legacyOld = try container.decodeIfPresent(Bool.self, forKey: .splitHandDetection)
            let enabled = legacyNew ?? legacyOld ?? true
            oppositeHandMode = enabled ? .press : .off
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledKeys, forKey: .enabledKeys)
        try container.encode(layerAssignments, forKey: .layerAssignments)
        try container.encode(timing, forKey: .timing)
        try container.encode(keySelection, forKey: .keySelection)
        try container.encode(toggleMode, forKey: .toggleMode)
        try container.encode(showAdvanced, forKey: .showAdvanced)
        try container.encode(oppositeHandMode, forKey: .oppositeHandMode)
    }

    /// Default layer assignments (community standard mirror setup)
    /// Left hand: fun, num, sym, nav
    /// Right hand: nav, sym, num, fun (mirrored)
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
}

/// Layer toggle mode
public enum LayerToggleMode: String, Codable, Sendable {
    /// layer-while-held: Layer activates while key is held, deactivates on release
    case whileHeld
    /// layer-toggle: Layer toggles on/off with each key press (sticky)
    case toggle

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .whileHeld: "While Held"
        case .toggle: "Toggle"
        }
    }

    /// Description for UI
    public var description: String {
        switch self {
        case .whileHeld: "Layer activates while holding the key"
        case .toggle: "Layer toggles on/off (sticky)"
        }
    }

    /// Kanata action name
    public var kanataAction: String {
        switch self {
        case .whileHeld: "layer-while-held"
        case .toggle: "layer-toggle"
        }
    }
}
