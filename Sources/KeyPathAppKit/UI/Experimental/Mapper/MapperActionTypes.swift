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

/// How a `SystemActionInfo` produces its kanata output string.
///
/// Distinguishing the three output mechanisms avoids overloading `kanataKeycode`
/// with values it was never meant to hold (e.g., modifier combos like `C-x`),
/// and lets callers classify actions without relying on which fields are nil.
public enum ActionOutputType: Equatable, Hashable, Sendable {
    /// Push-message system action — emitted as `(push-msg "system:<id>")`.
    case pushMessage
    /// Direct HID keycode (media keys). `simulatorName` is the canonical
    /// keyberon `KeyCode` enum case returned by the kanata simulator
    /// (e.g., `MediaPlayPause`), used for round-trip lookups.
    case hidKeycode(String, simulatorName: String?)
    /// Modifier-combo shortcut (e.g., `C-x`, `C-S-z`) — emitted verbatim.
    case modifierCombo(String)
}

/// Info about a selected system action, media key, or editing shortcut.
public struct SystemActionInfo: Equatable, Hashable, Identifiable, Sendable {
    /// The action identifier (e.g., "dnd", "spotlight", "play-pause")
    public let id: String
    /// Human-readable name
    public let name: String
    /// SF Symbol icon name
    public let sfSymbol: String
    /// How this action produces its kanata output string.
    public let output: ActionOutputType

    public init(id: String, name: String, sfSymbol: String, output: ActionOutputType = .pushMessage) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.output = output
    }

    /// The kanata output string for this action
    public var kanataOutput: String {
        switch output {
        case .pushMessage:
            return "(push-msg \"system:\(id)\")"
        case .hidKeycode(let keycode, _):
            return keycode
        case .modifierCombo(let combo):
            return combo
        }
    }

    /// True if this action is a push-message system action (Spotlight, DnD, etc.).
    public var isSystemAction: Bool {
        if case .pushMessage = output { return true }
        return false
    }

    /// True if this action is a direct HID media key (Play/Pause, Mute, etc.).
    public var isMediaKey: Bool {
        if case .hidKeycode = output { return true }
        return false
    }

    /// True if this action is a modifier-combo editing shortcut (Cut, Copy, etc.).
    public var isEditingShortcut: Bool {
        if case .modifierCombo = output { return true }
        return false
    }

    /// The HID keycode for media-key actions (e.g., `pp`, `mute`). Nil otherwise.
    public var kanataKeycode: String? {
        if case .hidKeycode(let keycode, _) = output { return keycode }
        return nil
    }

    /// Canonical simulator name for media keys (e.g., `MediaPlayPause`). Nil otherwise.
    public var simulatorName: String? {
        if case .hidKeycode(_, let name) = output { return name }
        return nil
    }

    /// All available system actions, media keys, and editing shortcuts.
    /// SF Symbols match macOS function key icons (non-filled variants).
    public static let allActions: [SystemActionInfo] = [
        // Push-msg system actions
        SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass"),
        SystemActionInfo(id: "mission-control", name: "Mission Control", sfSymbol: "rectangle.3.group"),
        SystemActionInfo(id: "launchpad", name: "Launchpad", sfSymbol: "square.grid.3x3"),
        SystemActionInfo(id: "dnd", name: "Do Not Disturb", sfSymbol: "moon"),
        SystemActionInfo(id: "notification-center", name: "Notification Center", sfSymbol: "bell"),
        SystemActionInfo(id: "dictation", name: "Dictation", sfSymbol: "mic"),
        SystemActionInfo(id: "siri", name: "Siri", sfSymbol: "waveform.circle"),
        // Media keys (direct HID keycodes)
        SystemActionInfo(id: "play-pause", name: "Play/Pause", sfSymbol: "playpause",
                         output: .hidKeycode("pp", simulatorName: "MediaPlayPause")),
        SystemActionInfo(id: "next-track", name: "Next Track", sfSymbol: "forward",
                         output: .hidKeycode("next", simulatorName: "MediaNextSong")),
        SystemActionInfo(id: "prev-track", name: "Previous Track", sfSymbol: "backward",
                         output: .hidKeycode("prev", simulatorName: "MediaPreviousSong")),
        SystemActionInfo(id: "mute", name: "Mute", sfSymbol: "speaker.slash",
                         output: .hidKeycode("mute", simulatorName: "Mute")),
        SystemActionInfo(id: "volume-up", name: "Volume Up", sfSymbol: "speaker.wave.3",
                         output: .hidKeycode("volu", simulatorName: "VolUp")),
        SystemActionInfo(id: "volume-down", name: "Volume Down", sfSymbol: "speaker.wave.1",
                         output: .hidKeycode("voldwn", simulatorName: "VolDown")),
        SystemActionInfo(id: "brightness-up", name: "Brightness Up", sfSymbol: "sun.max",
                         output: .hidKeycode("brup", simulatorName: "BrightnessUp")),
        SystemActionInfo(id: "brightness-down", name: "Brightness Down", sfSymbol: "sun.min",
                         output: .hidKeycode("brdown", simulatorName: "BrightnessDown")),
        // Editing shortcuts (modifier combos exposed as named actions)
        SystemActionInfo(id: "cut", name: "Cut", sfSymbol: "scissors", output: .modifierCombo("C-x")),
        SystemActionInfo(id: "copy", name: "Copy", sfSymbol: "doc.on.doc", output: .modifierCombo("C-c")),
        SystemActionInfo(id: "paste", name: "Paste", sfSymbol: "doc.on.clipboard", output: .modifierCombo("C-v")),
        SystemActionInfo(id: "undo", name: "Undo", sfSymbol: "arrow.uturn.backward", output: .modifierCombo("C-z")),
        SystemActionInfo(id: "redo", name: "Redo", sfSymbol: "arrow.uturn.forward", output: .modifierCombo("C-S-z")),
        SystemActionInfo(id: "select-all", name: "Select All", sfSymbol: "selection.pin.in.out", output: .modifierCombo("C-a")),
        SystemActionInfo(id: "save", name: "Save", sfSymbol: "square.and.arrow.down", output: .modifierCombo("C-s")),
        SystemActionInfo(id: "find", name: "Find", sfSymbol: "magnifyingglass", output: .modifierCombo("C-f")),
        // Cursor movement
        SystemActionInfo(id: "word-left", name: "Word Left", sfSymbol: "arrow.left.to.line",
                         output: .modifierCombo("A-left")),
        SystemActionInfo(id: "word-right", name: "Word Right", sfSymbol: "arrow.right.to.line",
                         output: .modifierCombo("A-right")),
        SystemActionInfo(id: "line-start", name: "Line Start", sfSymbol: "arrow.backward.to.line",
                         output: .hidKeycode("home", simulatorName: nil)),
        SystemActionInfo(id: "line-end", name: "Line End", sfSymbol: "arrow.forward.to.line",
                         output: .hidKeycode("end", simulatorName: nil)),
        // Deletion
        SystemActionInfo(id: "delete-word", name: "Delete Word", sfSymbol: "delete.backward",
                         output: .modifierCombo("A-bspc")),
        SystemActionInfo(id: "kill-line", name: "Kill Line", sfSymbol: "strikethrough",
                         output: .modifierCombo("C-k")),
        // Selection
        SystemActionInfo(id: "select-word-left", name: "Select Word Left", sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-A-left")),
        SystemActionInfo(id: "select-word-right", name: "Select Word Right", sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-A-right")),
        SystemActionInfo(id: "select-to-line-start", name: "Select to Line Start", sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-M-left")),
        SystemActionInfo(id: "select-to-line-end", name: "Select to Line End", sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-M-right")),
        // Tab/Window management
        SystemActionInfo(id: "prev-tab", name: "Previous Tab", sfSymbol: "arrow.left.square",
                         output: .modifierCombo("C-S-tab")),
        SystemActionInfo(id: "next-tab", name: "Next Tab", sfSymbol: "arrow.right.square",
                         output: .modifierCombo("C-tab")),
        SystemActionInfo(id: "app-switcher", name: "App Switcher", sfSymbol: "rectangle.stack",
                         output: .modifierCombo("M-tab")),
        SystemActionInfo(id: "window-switcher", name: "Window Switcher", sfSymbol: "macwindow.on.rectangle",
                         output: .modifierCombo("M-grave")),
        // System
        SystemActionInfo(id: "screenshot", name: "Screenshot", sfSymbol: "camera",
                         output: .modifierCombo("C-M-S-4")),
        // Additional editing
        SystemActionInfo(id: "forward-delete", name: "Forward Delete", sfSymbol: "delete.forward",
                         output: .hidKeycode("del", simulatorName: nil)),
        SystemActionInfo(id: "close-tab", name: "Close Tab", sfSymbol: "xmark.square",
                         output: .modifierCombo("M-w")),
    ]

    /// Look up a SystemActionInfo by its kanata output (id, display name, keycode,
    /// simulator name, modifier combo, or raw `(push-msg "system:...")` string).
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

        // Check by output payload: HID keycode, simulator name, or modifier combo.
        if let action = allActions.first(where: { action in
            switch action.output {
            case .pushMessage:
                return false
            case .hidKeycode(let keycode, let simulator):
                return keycode.lowercased() == lower || simulator?.lowercased() == lower
            case .modifierCombo(let combo):
                return combo.lowercased() == lower
            }
        }) {
            return action
        }

        return nil
    }
}
