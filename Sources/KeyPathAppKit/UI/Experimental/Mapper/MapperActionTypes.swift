import AppKit
import Foundation

// MARK: - App Launch Info

/// Info about a selected app for launch action
public struct AppLaunchInfo: Equatable {
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

// MARK: - Device Condition Info

/// Info about a selected keyboard device for precondition (rule only applies on this device)
public struct DeviceConditionInfo: Equatable, Identifiable {
    public let deviceHash: String
    public let displayName: String
    public let sfSymbolName: String
    public var id: String { deviceHash }

    public init(deviceHash: String, displayName: String, sfSymbolName: String) {
        self.deviceHash = deviceHash
        self.displayName = displayName
        self.sfSymbolName = sfSymbolName
    }
}

// MARK: - App Condition Info

/// Info about a selected app for precondition (rule only applies when this app is frontmost)
public struct AppConditionInfo: Equatable, Identifiable {
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
public struct SystemActionInfo: Equatable, Hashable, Identifiable, Sendable {
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

    private static let editingShortcutIDs: Set<String> = [
        "cut", "copy", "paste", "undo", "redo", "select-all", "save", "find"
    ]

    /// Whether this is a media key (direct keycode like pp, next, mute)
    public var isMediaKey: Bool {
        kanataKeycode != nil && !Self.editingShortcutIDs.contains(id)
    }

    /// Whether this is an editing shortcut (modifier combo like C-x, C-c)
    public var isEditingShortcut: Bool {
        Self.editingShortcutIDs.contains(id)
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
        SystemActionInfo(id: "brightness-down", name: "Brightness Down", sfSymbol: "sun.min", kanataKeycode: "brdown", simulatorName: "BrightnessDown"),
        // Editing shortcuts (modifier combos exposed as named actions)
        SystemActionInfo(id: "cut", name: "Cut", sfSymbol: "scissors", kanataKeycode: "C-x"),
        SystemActionInfo(id: "copy", name: "Copy", sfSymbol: "doc.on.doc", kanataKeycode: "C-c"),
        SystemActionInfo(id: "paste", name: "Paste", sfSymbol: "doc.on.clipboard", kanataKeycode: "C-v"),
        SystemActionInfo(id: "undo", name: "Undo", sfSymbol: "arrow.uturn.backward", kanataKeycode: "C-z"),
        SystemActionInfo(id: "redo", name: "Redo", sfSymbol: "arrow.uturn.forward", kanataKeycode: "C-S-z"),
        SystemActionInfo(id: "select-all", name: "Select All", sfSymbol: "selection.pin.in.out", kanataKeycode: "C-a"),
        SystemActionInfo(id: "save", name: "Save", sfSymbol: "square.and.arrow.down", kanataKeycode: "C-s"),
        SystemActionInfo(id: "find", name: "Find", sfSymbol: "magnifyingglass", kanataKeycode: "C-f"),
    ]

    /// Look up a SystemActionInfo by its kanata output (keycode, display name, or simulator name)
    public static func find(byOutput output: String) -> SystemActionInfo? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let normalizedDashed = lower
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let normalizedCompact = normalizedDashed.replacingOccurrences(of: "-", with: "")

        // Handle raw push-msg strings: (push-msg "system:notification-center")
        if let regex = try? NSRegularExpression(pattern: #"\(push-msg\s+\"system:([^\"]+)\"\)"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed)
        {
            let extracted = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let action = allActions.first(where: { $0.id.lowercased() == extracted }) {
                return action
            }
        }

        // Check by id and common id variants.
        if let action = allActions.first(where: {
            let actionIdLower = $0.id.lowercased()
            let actionIdCompact = actionIdLower.replacingOccurrences(of: "-", with: "")
            return actionIdLower == lower || actionIdLower == normalizedDashed || actionIdCompact == normalizedCompact
        }) {
            return action
        }

        // Check by display name (case-insensitive).
        if let action = allActions.first(where: { $0.name.lowercased() == lower }) {
            return action
        }

        // Check by kanata keycode (for direct key outputs like "pp", "next").
        if let action = allActions.first(where: { $0.kanataKeycode?.lowercased() == lower }) {
            return action
        }

        // Check by simulator canonical name (e.g., "MediaPreviousSong", "MediaPlayPause").
        if let action = allActions.first(where: { $0.simulatorName?.lowercased() == lower }) {
            return action
        }

        return nil
    }
}
