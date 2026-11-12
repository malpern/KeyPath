import Foundation
import KeyPathCore

/// How a `SystemActionInfo` produces its kanata output string.
///
/// Distinguishing the three output mechanisms avoids overloading `kanataKeycode`
/// with values it was never meant to hold, and lets callers classify actions
/// without relying on which fields are nil.
public enum ActionOutputType: Equatable, Hashable, Sendable {
    /// Push-message system action, emitted as `(push-msg "system:<id>")`.
    case pushMessage
    /// Direct HID keycode. `simulatorName` is the canonical keyberon `KeyCode`
    /// enum case returned by the kanata simulator.
    case hidKeycode(String, simulatorName: String?)
    /// Modifier-combo shortcut, emitted verbatim.
    case modifierCombo(String)
}

/// Info about a selected system action, media key, or editing shortcut.
public struct SystemActionInfo: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sfSymbol: String
    public let output: ActionOutputType

    public init(id: String, name: String, sfSymbol: String, output: ActionOutputType = .pushMessage) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.output = output
    }

    public var kanataOutput: String {
        switch output {
        case .pushMessage:
            "(push-msg \"system:\(id)\")"
        case let .hidKeycode(keycode, _):
            keycode
        case let .modifierCombo(combo):
            combo
        }
    }

    /// Whether the active backend can emit this action. Push-message and modifier
    /// actions always can; a HID keycode asks the backend's capability profile
    /// (the driverless session refuses consumer-page keys such as media keys).
    public var isSupportedInDriverlessSession: Bool {
        guard let keycode = kanataKeycode else { return true }
        return BackendCapabilityProfile.shared.canEmit(kanataKey: keycode)
    }

    public static let driverlessMediaUnavailableReason =
        String(localized: "Media and brightness remapping is not supported in driverless mode.")

    public var isSystemAction: Bool {
        if case .pushMessage = output { return true }
        return false
    }

    public var isMediaKey: Bool {
        if case .hidKeycode = output { return true }
        return false
    }

    public var isEditingShortcut: Bool {
        if case .modifierCombo = output { return true }
        return false
    }

    public var kanataKeycode: String? {
        if case let .hidKeycode(keycode, _) = output { return keycode }
        return nil
    }

    public var simulatorName: String? {
        if case let .hidKeycode(_, name) = output { return name }
        return nil
    }

    /// All available system actions, media keys, and editing shortcuts.
    public static let allActions: [SystemActionInfo] = [
        SystemActionInfo(id: "spotlight", name: String(localized: "Spotlight", comment: "System action or shortcut name"), sfSymbol: "magnifyingglass"),
        SystemActionInfo(id: "mission-control", name: String(localized: "Mission Control", comment: "System action or shortcut name"), sfSymbol: "rectangle.3.group"),
        SystemActionInfo(id: "launchpad", name: String(localized: "Launchpad", comment: "System action or shortcut name"), sfSymbol: "square.grid.3x3"),
        SystemActionInfo(id: "dnd", name: String(localized: "Do Not Disturb", comment: "System action or shortcut name"), sfSymbol: "moon"),
        SystemActionInfo(id: "notification-center", name: String(localized: "Notification Center", comment: "System action or shortcut name"), sfSymbol: "bell"),
        SystemActionInfo(id: "dictation", name: String(localized: "Dictation", comment: "System action or shortcut name"), sfSymbol: "mic"),
        SystemActionInfo(id: "siri", name: String(localized: "Siri", comment: "System action or shortcut name"), sfSymbol: "waveform.circle"),

        SystemActionInfo(id: "play-pause", name: String(localized: "Play/Pause", comment: "System action or shortcut name"), sfSymbol: "playpause",
                         output: .hidKeycode("pp", simulatorName: "MediaPlayPause")),
        SystemActionInfo(id: "next-track", name: String(localized: "Next Track", comment: "System action or shortcut name"), sfSymbol: "forward",
                         output: .hidKeycode("next", simulatorName: "MediaNextSong")),
        SystemActionInfo(id: "prev-track", name: String(localized: "Previous Track", comment: "System action or shortcut name"), sfSymbol: "backward",
                         output: .hidKeycode("prev", simulatorName: "MediaPreviousSong")),
        SystemActionInfo(id: "mute", name: String(localized: "Mute", comment: "System action or shortcut name"), sfSymbol: "speaker.slash",
                         output: .hidKeycode("mute", simulatorName: "Mute")),
        SystemActionInfo(id: "volume-up", name: String(localized: "Volume Up", comment: "System action or shortcut name"), sfSymbol: "speaker.wave.3",
                         output: .hidKeycode("volu", simulatorName: "VolUp")),
        SystemActionInfo(id: "volume-down", name: String(localized: "Volume Down", comment: "System action or shortcut name"), sfSymbol: "speaker.wave.1",
                         output: .hidKeycode("voldwn", simulatorName: "VolDown")),
        SystemActionInfo(id: "brightness-up", name: String(localized: "Brightness Up", comment: "System action or shortcut name"), sfSymbol: "sun.max",
                         output: .hidKeycode("brup", simulatorName: "BrightnessUp")),
        SystemActionInfo(id: "brightness-down", name: String(localized: "Brightness Down", comment: "System action or shortcut name"), sfSymbol: "sun.min",
                         output: .hidKeycode("brdown", simulatorName: "BrightnessDown")),

        SystemActionInfo(id: "cut", name: String(localized: "Cut", comment: "System action or shortcut name"), sfSymbol: "scissors", output: .modifierCombo("C-x")),
        SystemActionInfo(id: "copy", name: String(localized: "Copy", comment: "System action or shortcut name"), sfSymbol: "doc.on.doc", output: .modifierCombo("C-c")),
        SystemActionInfo(id: "paste", name: String(localized: "Paste", comment: "System action or shortcut name"), sfSymbol: "doc.on.clipboard", output: .modifierCombo("C-v")),
        SystemActionInfo(id: "undo", name: String(localized: "Undo", comment: "System action or shortcut name"), sfSymbol: "arrow.uturn.backward", output: .modifierCombo("C-z")),
        SystemActionInfo(id: "redo", name: String(localized: "Redo", comment: "System action or shortcut name"), sfSymbol: "arrow.uturn.forward", output: .modifierCombo("C-S-z")),
        SystemActionInfo(id: "select-all", name: String(localized: "Select All", comment: "System action or shortcut name"), sfSymbol: "selection.pin.in.out", output: .modifierCombo("C-a")),
        SystemActionInfo(id: "save", name: String(localized: "Save", comment: "System action or shortcut name"), sfSymbol: "square.and.arrow.down", output: .modifierCombo("C-s")),
        SystemActionInfo(id: "find", name: String(localized: "Find", comment: "System action or shortcut name"), sfSymbol: "magnifyingglass", output: .modifierCombo("C-f")),

        SystemActionInfo(id: "word-left", name: String(localized: "Word Left", comment: "System action or shortcut name"), sfSymbol: "arrow.left.to.line",
                         output: .modifierCombo("A-left")),
        SystemActionInfo(id: "word-right", name: String(localized: "Word Right", comment: "System action or shortcut name"), sfSymbol: "arrow.right.to.line",
                         output: .modifierCombo("A-right")),
        SystemActionInfo(id: "line-start", name: String(localized: "Line Start", comment: "System action or shortcut name"), sfSymbol: "arrow.backward.to.line",
                         output: .hidKeycode("home", simulatorName: nil)),
        SystemActionInfo(id: "line-end", name: String(localized: "Line End", comment: "System action or shortcut name"), sfSymbol: "arrow.forward.to.line",
                         output: .hidKeycode("end", simulatorName: nil)),

        SystemActionInfo(id: "delete-word", name: String(localized: "Delete Word", comment: "System action or shortcut name"), sfSymbol: "delete.backward",
                         output: .modifierCombo("A-bspc")),
        SystemActionInfo(id: "kill-line", name: String(localized: "Kill Line", comment: "System action or shortcut name"), sfSymbol: "strikethrough",
                         output: .modifierCombo("C-k")),

        SystemActionInfo(id: "select-word-left", name: String(localized: "Select Word Left", comment: "System action or shortcut name"), sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-A-left")),
        SystemActionInfo(id: "select-word-right", name: String(localized: "Select Word Right", comment: "System action or shortcut name"), sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-A-right")),
        SystemActionInfo(id: "select-to-line-start", name: String(localized: "Select to Line Start", comment: "System action or shortcut name"), sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-M-left")),
        SystemActionInfo(id: "select-to-line-end", name: String(localized: "Select to Line End", comment: "System action or shortcut name"), sfSymbol: "text.badge.checkmark",
                         output: .modifierCombo("S-M-right")),

        SystemActionInfo(id: "prev-tab", name: String(localized: "Previous Tab", comment: "System action or shortcut name"), sfSymbol: "arrow.left.square",
                         output: .modifierCombo("C-S-tab")),
        SystemActionInfo(id: "next-tab", name: String(localized: "Next Tab", comment: "System action or shortcut name"), sfSymbol: "arrow.right.square",
                         output: .modifierCombo("C-tab")),
        SystemActionInfo(id: "app-switcher", name: String(localized: "App Switcher", comment: "System action or shortcut name"), sfSymbol: "rectangle.stack",
                         output: .modifierCombo("M-tab")),
        SystemActionInfo(id: "window-switcher", name: String(localized: "Window Switcher", comment: "System action or shortcut name"), sfSymbol: "macwindow.on.rectangle",
                         output: .modifierCombo("M-grave")),

        SystemActionInfo(id: "screenshot", name: String(localized: "Screenshot", comment: "System action or shortcut name"), sfSymbol: "camera",
                         output: .modifierCombo("C-M-S-4")),
        SystemActionInfo(id: "forward-delete", name: String(localized: "Forward Delete", comment: "System action or shortcut name"), sfSymbol: "delete.forward",
                         output: .hidKeycode("del", simulatorName: nil)),
        SystemActionInfo(id: "close-tab", name: String(localized: "Close Tab", comment: "System action or shortcut name"), sfSymbol: "xmark.square",
                         output: .modifierCombo("M-w")),
    ]

    /// Look up a SystemActionInfo by its kanata output, id, display name,
    /// simulator name, modifier combo, or raw `(push-msg "system:...")` string.
    public static func find(byOutput output: String) -> SystemActionInfo? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let normalizedDashed = lower
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let normalizedCompact = normalizedDashed.replacingOccurrences(of: "-", with: "")

        if let regex = try? NSRegularExpression(pattern: #"\(push-msg\s+\"system:([^\"]+)\"\)"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed)
        {
            let extracted = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let action = allActions.first(where: { $0.id.lowercased() == extracted }) {
                return action
            }
        }

        if let action = allActions.first(where: {
            let actionIdLower = $0.id.lowercased()
            let actionIdCompact = actionIdLower.replacingOccurrences(of: "-", with: "")
            return actionIdLower == lower || actionIdLower == normalizedDashed || actionIdCompact == normalizedCompact
        }) {
            return action
        }

        if let action = allActions.first(where: { $0.name.lowercased() == lower }) {
            return action
        }

        return allActions.first { action in
            switch action.output {
            case .pushMessage:
                false
            case let .hidKeycode(keycode, simulator):
                keycode.lowercased() == lower || simulator?.lowercased() == lower
            case let .modifierCombo(combo):
                combo.lowercased() == lower
            }
        }
    }
}
