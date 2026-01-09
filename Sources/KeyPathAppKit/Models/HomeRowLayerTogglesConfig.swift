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

    public init(
        enabledKeys: Set<String> = ["a", "s", "d", "f", "j", "k", "l", ";"],
        layerAssignments: [String: String] = HomeRowLayerTogglesConfig.defaultLayerAssignments,
        timing: TimingConfig = .default,
        keySelection: KeySelection = .both,
        toggleMode: LayerToggleMode = .whileHeld,
        showAdvanced: Bool = false
    ) {
        self.enabledKeys = enabledKeys
        self.layerAssignments = layerAssignments
        self.timing = timing
        self.keySelection = keySelection
        self.toggleMode = toggleMode
        self.showAdvanced = showAdvanced
    }

    /// Default layer assignments (commonly used layers from Ben Vallack's config)
    /// Left hand: num, sys1, sys2, nav
    /// Right hand: nav, sys2, sys1, num (mirrored)
    public static let defaultLayerAssignments: [String: String] = [
        "a": "num", "s": "sys1", "d": "sys2", "f": "nav",
        "j": "nav", "k": "sys2", "l": "sys1", ";": "num"
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
