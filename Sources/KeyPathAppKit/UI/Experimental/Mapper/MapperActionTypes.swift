import AppKit
import Foundation

// MARK: - App Launch Info

/// Info about a selected app for launch action
public struct AppLaunchInfo: Equatable, Sendable {
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage

    public init(name: String, bundleIdentifier: String?, icon: NSImage) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
    }

    /// The kanata output string for this app launch
    public var kanataOutput: String {
        // Use bundle identifier if available, otherwise app name
        let appId = bundleIdentifier ?? name
        return "(push-msg \"launch:\(appId)\")"
    }
}

// MARK: - App Condition Info

/// Info about a selected app for precondition (rule only applies when this app is frontmost)
public struct AppConditionInfo: Equatable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let icon: NSImage

    public var id: String {
        bundleIdentifier
    }

    public init(bundleIdentifier: String, displayName: String, icon: NSImage) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.icon = icon
    }
}

// MARK: - System Action Info

/// Info about a selected system action or media key
public struct SystemActionInfo: Equatable, Identifiable, Sendable {
    /// The action identifier (e.g., "dnd", "spotlight", "pp" for play/pause)
    public let id: String
    /// Human-readable name
    public let name: String
    /// SF Symbol icon name
    public let sfSymbol: String
    /// If non-nil, this is a direct keycode output (e.g., "pp", "prev", "next")
    /// If nil, this is a push-msg system action
    public let kanataKeycode: String?
    /// Canonical name returned by kanata simulator (e.g., "MediaTrackPrevious", "MediaPlayPause")
    public let simulatorName: String?

    public init(id: String, name: String, sfSymbol: String, kanataKeycode: String? = nil, simulatorName: String? = nil) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.kanataKeycode = kanataKeycode
        self.simulatorName = simulatorName
    }

    /// The kanata output string for this action
    public var kanataOutput: String {
        if let keycode = kanataKeycode {
            return keycode
        }
        return "(push-msg \"system:\(id)\")"
    }

    /// Whether this is a media key (direct keycode) vs push-msg action
    public var isMediaKey: Bool {
        kanataKeycode != nil
    }

    /// All available system actions and media keys
    /// SF Symbols match macOS function key icons (non-filled variants)
    public static let allActions: [SystemActionInfo] = [
        // Push-msg system actions
        SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass"),
        SystemActionInfo(id: "mission-control", name: "Mission Control", sfSymbol: "rectangle.3.group"),
        SystemActionInfo(id: "launchpad", name: "Launchpad", sfSymbol: "square.grid.3x3"),
        SystemActionInfo(id: "dnd", name: "Do Not Disturb", sfSymbol: "moon"),
        SystemActionInfo(id: "notification-center", name: "Notification Center", sfSymbol: "bell"),
        SystemActionInfo(id: "dictation", name: "Dictation", sfSymbol: "mic"),
        SystemActionInfo(id: "siri", name: "Siri", sfSymbol: "waveform.circle"),
        // Media keys (direct keycodes)
        // simulatorName is the canonical name returned by kanata simulator (from keyberon KeyCode enum)
        SystemActionInfo(id: "play-pause", name: "Play/Pause", sfSymbol: "playpause", kanataKeycode: "pp", simulatorName: "MediaPlayPause"),
        SystemActionInfo(id: "next-track", name: "Next Track", sfSymbol: "forward", kanataKeycode: "next", simulatorName: "MediaNextSong"),
        SystemActionInfo(id: "prev-track", name: "Previous Track", sfSymbol: "backward", kanataKeycode: "prev", simulatorName: "MediaPreviousSong"),
        SystemActionInfo(id: "mute", name: "Mute", sfSymbol: "speaker.slash", kanataKeycode: "mute", simulatorName: "Mute"),
        SystemActionInfo(id: "volume-up", name: "Volume Up", sfSymbol: "speaker.wave.3", kanataKeycode: "volu", simulatorName: "VolUp"),
        SystemActionInfo(id: "volume-down", name: "Volume Down", sfSymbol: "speaker.wave.1", kanataKeycode: "voldwn", simulatorName: "VolDown"),
        SystemActionInfo(id: "brightness-up", name: "Brightness Up", sfSymbol: "sun.max", kanataKeycode: "brup", simulatorName: "BrightnessUp"),
        SystemActionInfo(id: "brightness-down", name: "Brightness Down", sfSymbol: "sun.min", kanataKeycode: "brdown", simulatorName: "BrightnessDown")
    ]

    /// Look up a SystemActionInfo by its kanata output (keycode, display name, or simulator name)
    public static func find(byOutput output: String) -> SystemActionInfo? {
        // Check by id (system action identifier)
        if let action = allActions.first(where: { $0.id == output }) {
            return action
        }
        // Check by name first (for display labels from overlay)
        if let action = allActions.first(where: { $0.name == output }) {
            return action
        }
        // Check by kanata keycode (for direct key outputs like "pp", "next")
        if let action = allActions.first(where: { $0.kanataKeycode == output }) {
            return action
        }
        // Check by simulator canonical name (e.g., "MediaTrackPrevious", "MediaPlayPause")
        if let action = allActions.first(where: { $0.simulatorName == output }) {
            return action
        }
        return nil
    }
}
