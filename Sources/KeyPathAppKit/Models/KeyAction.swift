import Foundation

/// Unified output type for all key mappings.
/// Replaces string-based outputs and `LauncherTarget` with a single typed enum
/// that represents every kind of action a key can trigger.
public enum KeyAction: Codable, Equatable, Sendable, Hashable {
    /// Emit a different key (simple remap)
    case keystroke(key: String)

    /// Launch an application
    case launchApp(name: String, bundleId: String?)

    /// Open a URL in the default browser
    case openURL(String)

    /// Open a folder in Finder
    case openFolder(path: String, name: String?)

    /// Run a script
    case runScript(path: String, name: String?)

    /// Trigger a system action (Mission Control, volume, brightness, etc.)
    case systemAction(id: String)

    /// Switch to or activate a layer
    case activateLayer(name: String)

    /// Raw kanata expression (escape hatch for power users and internal use)
    case rawKanata(String)
}

// MARK: - Kanata Output

public extension KeyAction {
    /// Generate the kanata expression for this action.
    /// Used by the config generator to produce valid kanata syntax.
    var kanataOutput: String {
        switch self {
        case let .keystroke(key):
            return key
        case let .launchApp(name, bundleId):
            let identifier = bundleId?.isEmpty == false ? bundleId! : name
            return "(push-msg \"launch:\(identifier)\")"
        case let .openURL(urlString):
            let encoded = URLMappingFormatter.encodeForPushMessage(urlString)
            return "(push-msg \"open:\(encoded)\")"
        case let .openFolder(path, _):
            return "(push-msg \"folder:\(path)\")"
        case let .runScript(path, _):
            return "(push-msg \"script:\(path)\")"
        case let .systemAction(id):
            return "(push-msg \"system:\(id)\")"
        case let .activateLayer(name):
            return "(layer-switch \(name))"
        case let .rawKanata(expr):
            return expr
        }
    }
}

// MARK: - Display

public extension KeyAction {
    /// Human-readable display name for UI labels.
    var displayName: String {
        switch self {
        case let .keystroke(key):
            return key
        case let .launchApp(name, _):
            return name
        case let .openURL(urlString):
            return URLMappingFormatter.displayDomain(for: urlString)
        case let .openFolder(_, name):
            return name ?? "Folder"
        case let .runScript(path, name):
            return name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case let .systemAction(id):
            return id
        case let .activateLayer(name):
            return name
        case let .rawKanata(expr):
            return expr
        }
    }

    /// Description for tooltips.
    var autoDescription: String {
        switch self {
        case let .keystroke(key):
            return "Remap to \(key)"
        case let .launchApp(name, _):
            return "Open \(name)"
        case let .openURL(urlString):
            return "Open \(URLMappingFormatter.displayDomain(for: urlString))"
        case let .openFolder(_, name):
            return "Open \(name ?? "folder")"
        case let .runScript(_, name):
            return "Run \(name ?? "script")"
        case let .systemAction(id):
            return "System: \(id)"
        case let .activateLayer(name):
            return "Activate \(name) layer"
        case let .rawKanata(expr):
            return expr
        }
    }
}

// MARK: - Display Info with Icons

public extension KeyAction {
    struct DisplayInfo {
        public let label: String
        public let icon: String?
    }

    var commonDisplayInfo: DisplayInfo? {
        switch self {
        case let .keystroke(key):
            return Self.resolveKeystroke(key)
        case let .launchApp(name, _):
            return DisplayInfo(label: name, icon: "app.fill")
        case .openURL:
            return DisplayInfo(label: displayName, icon: "link")
        case let .openFolder(_, name):
            return DisplayInfo(label: name ?? "Folder", icon: "folder.fill")
        case let .runScript(_, name):
            return DisplayInfo(label: name ?? "Script", icon: "terminal.fill")
        case let .systemAction(id):
            if let action = SystemActionInfo.find(byOutput: id) {
                return DisplayInfo(label: action.name, icon: action.sfSymbol)
            }
            return DisplayInfo(label: id, icon: "gearshape")
        case let .activateLayer(name):
            return DisplayInfo(label: name, icon: "square.stack.3d.up")
        case let .rawKanata(expr):
            return Self.resolveRawKanata(expr)
        }
    }

    private static func resolveKeystroke(_ key: String) -> DisplayInfo? {
        switch key.lowercased() {
        case "esc": return DisplayInfo(label: "Esc", icon: "escape")
        case "enter", "ret": return DisplayInfo(label: "Return", icon: "return")
        case "bspc": return DisplayInfo(label: "Backspace", icon: "delete.backward")
        case "del": return DisplayInfo(label: "Delete", icon: "delete.forward")
        case "tab": return DisplayInfo(label: "Tab", icon: "arrow.right.to.line")
        case "spc": return DisplayInfo(label: "Space", icon: nil)
        case "up": return DisplayInfo(label: "↑", icon: "arrow.up")
        case "down": return DisplayInfo(label: "↓", icon: "arrow.down")
        case "left": return DisplayInfo(label: "←", icon: "arrow.left")
        case "right": return DisplayInfo(label: "→", icon: "arrow.right")
        case "pp": return DisplayInfo(label: "Play/Pause", icon: "playpause")
        case "next": return DisplayInfo(label: "Next", icon: "forward")
        case "prev": return DisplayInfo(label: "Previous", icon: "backward")
        default: return nil
        }
    }

    private static func resolveRawKanata(_ expr: String) -> DisplayInfo? {
        switch expr.lowercased() {
        case "c-x": return DisplayInfo(label: "Cut", icon: "scissors")
        case "c-c": return DisplayInfo(label: "Copy", icon: "doc.on.doc")
        case "c-v": return DisplayInfo(label: "Paste", icon: "doc.on.clipboard")
        case "c-z": return DisplayInfo(label: "Undo", icon: "arrow.uturn.backward")
        case "c-y", "c-s-z": return DisplayInfo(label: "Redo", icon: "arrow.uturn.forward")
        case "c-a": return DisplayInfo(label: "Select All", icon: "selection.pin.in.out")
        case "c-s": return DisplayInfo(label: "Save", icon: "square.and.arrow.down")
        default:
            if let action = SystemActionInfo.find(byOutput: expr) {
                return DisplayInfo(label: action.name, icon: action.sfSymbol)
            }
            return nil
        }
    }
}

// MARK: - Type Checks

public extension KeyAction {
    var isKeystroke: Bool {
        if case .keystroke = self { return true }
        return false
    }

    var isLaunchApp: Bool {
        if case .launchApp = self { return true }
        return false
    }

    var isOpenURL: Bool {
        if case .openURL = self { return true }
        return false
    }

    var isOpenFolder: Bool {
        if case .openFolder = self { return true }
        return false
    }

    var isRunScript: Bool {
        if case .runScript = self { return true }
        return false
    }

    var isSystemAction: Bool {
        if case .systemAction = self { return true }
        return false
    }

    var isActivateLayer: Bool {
        if case .activateLayer = self { return true }
        return false
    }

    var isRawKanata: Bool {
        if case .rawKanata = self { return true }
        return false
    }
}

// MARK: - Convenience Factories

public extension KeyAction {
    /// Create from a LauncherTarget-style app entry.
    static func app(_ name: String, bundleId: String? = nil) -> KeyAction {
        .launchApp(name: name, bundleId: bundleId)
    }

    /// Create from a URL string.
    static func url(_ urlString: String) -> KeyAction {
        .openURL(urlString)
    }

    /// Create from a folder path.
    static func folder(_ path: String, name: String? = nil) -> KeyAction {
        .openFolder(path: path, name: name)
    }

    /// Create from a script path.
    static func script(_ path: String, name: String? = nil) -> KeyAction {
        .runScript(path: path, name: name)
    }

    /// The key string for keystroke actions, or the kanata output for other types.
    /// Useful as a backward-compatible accessor where code previously used `output: String`.
    var outputString: String {
        switch self {
        case let .keystroke(key):
            return key
        default:
            return kanataOutput
        }
    }
}
