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
        modifierAssignments: [String: String] = [
            "a": "lmet", "s": "lalt", "d": "lctl", "f": "lsft",
            "j": "rsft", "k": "rctl", "l": "ralt", ";": "rmet"
        ],
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
    
    /// Standard QWERTY modifier assignments
    /// Left hand: Cmd, Alt, Ctrl, Shift
    /// Right hand: Shift, Ctrl, Alt, Cmd
    public static let qwertyStandard: [String: String] = [
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
            return Set(HomeRowModsConfig.allKeys)
        case .leftOnly:
            return Set(HomeRowModsConfig.leftHandKeys)
        case .rightOnly:
            return Set(HomeRowModsConfig.rightHandKeys)
        case .custom:
            return [] // User selects individually
        }
    }
}

/// Timing configuration for home row mods
public struct TimingConfig: Codable, Equatable, Sendable {
    public var tapWindow: Int
    public var holdDelay: Int
    
    public init(tapWindow: Int = 200, holdDelay: Int = 150) {
        self.tapWindow = tapWindow
        self.holdDelay = holdDelay
    }
    
    public static let `default` = TimingConfig()
}

