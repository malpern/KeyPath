import Foundation

/// Configuration for Home Row Mods collection
public struct HomeRowModsConfig: Codable, Equatable, Sendable {
    /// Which keys are enabled for home row mods
    public var enabledKeys: Set<String>

    /// Modifier assignment for each key
    public var modifierAssignments: [String: String]

    /// Timing configuration
    public var timing: TimingConfig

    /// Key selection mode
    public var keySelection: KeySelection

    /// Whether advanced options are shown
    public var showAdvanced: Bool

    public init(
        enabledKeys: Set<String> = ["a", "s", "d", "f", "j", "k", "l", ";"],
        modifierAssignments: [String: String] = HomeRowModsConfig.cagsMacDefault,
        timing: TimingConfig = .default,
        keySelection: KeySelection = .both,
        showAdvanced: Bool = false
    ) {
        self.enabledKeys = enabledKeys
        self.modifierAssignments = modifierAssignments
        self.timing = timing
        self.keySelection = keySelection
        self.showAdvanced = showAdvanced
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

    /// Left hand keys
    public static let leftHandKeys = ["a", "s", "d", "f"]

    /// Right hand keys
    public static let rightHandKeys = ["j", "k", "l", ";"]

    /// All home row keys
    public static let allKeys = leftHandKeys + rightHandKeys
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

    public init(
        tapWindow: Int = 200,
        holdDelay: Int = 150,
        quickTapEnabled: Bool = false,
        quickTapTermMs: Int = 0,
        tapOffsets: [String: Int] = [:]
    ) {
        self.tapWindow = tapWindow
        self.holdDelay = holdDelay
        self.quickTapEnabled = quickTapEnabled
        self.quickTapTermMs = quickTapTermMs
        self.tapOffsets = tapOffsets
    }

    private enum CodingKeys: String, CodingKey {
        case tapWindow
        case holdDelay
        case quickTapEnabled
        case quickTapTermMs
        case tapOffsets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tapWindow = try container.decodeIfPresent(Int.self, forKey: .tapWindow) ?? 200
        holdDelay = try container.decodeIfPresent(Int.self, forKey: .holdDelay) ?? 150
        quickTapEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickTapEnabled) ?? false
        quickTapTermMs = try container.decodeIfPresent(Int.self, forKey: .quickTapTermMs) ?? 0
        tapOffsets = try container.decodeIfPresent([String: Int].self, forKey: .tapOffsets) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tapWindow, forKey: .tapWindow)
        try container.encode(holdDelay, forKey: .holdDelay)
        try container.encode(quickTapEnabled, forKey: .quickTapEnabled)
        try container.encode(quickTapTermMs, forKey: .quickTapTermMs)
        try container.encode(tapOffsets, forKey: .tapOffsets)
    }

    public static let `default` = TimingConfig()
}
