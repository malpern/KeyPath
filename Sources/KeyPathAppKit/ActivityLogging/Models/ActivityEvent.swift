import Foundation

/// Types of activity events that can be logged
public enum ActivityEventType: String, Codable, Sendable {
    case appLaunch // App was launched
    case appSwitch // User switched to app (became frontmost)
    case keyboardShortcut // Modifier+key combo detected
    case keyPathAction // URI-based KeyPath action executed
}

/// Core activity event structure
public struct ActivityEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let type: ActivityEventType
    public let payload: ActivityPayload

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: ActivityEventType,
        payload: ActivityPayload
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.payload = payload
    }
}

/// Type-safe payload union for different event types
public enum ActivityPayload: Codable, Sendable {
    case app(AppEventData)
    case shortcut(ShortcutEventData)
    case action(ActionEventData)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum PayloadType: String, Codable {
        case app, shortcut, action
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .app(data):
            try container.encode(PayloadType.app, forKey: .type)
            try container.encode(data, forKey: .data)
        case let .shortcut(data):
            try container.encode(PayloadType.shortcut, forKey: .type)
            try container.encode(data, forKey: .data)
        case let .action(data):
            try container.encode(PayloadType.action, forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .app:
            self = try .app(container.decode(AppEventData.self, forKey: .data))
        case .shortcut:
            self = try .shortcut(container.decode(ShortcutEventData.self, forKey: .data))
        case .action:
            self = try .action(container.decode(ActionEventData.self, forKey: .data))
        }
    }
}

/// Data for app launch/switch events
public struct AppEventData: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let appName: String
    public let isLaunch: Bool // true = launch, false = switch

    public init(bundleIdentifier: String, appName: String, isLaunch: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.isLaunch = isLaunch
    }
}

/// Data for keyboard shortcut events
public struct ShortcutEventData: Codable, Sendable, Equatable {
    public let modifiers: ShortcutModifiers
    public let key: String
    public let keyCode: Int64

    public init(modifiers: ShortcutModifiers, key: String, keyCode: Int64) {
        self.modifiers = modifiers
        self.key = key
        self.keyCode = keyCode
    }

    /// Display string with macOS symbols (e.g., "⌘S")
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += key
        return result
    }
}

/// Modifier keys for shortcut events (mirrors ModifierSet but self-contained)
public struct ShortcutModifiers: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// Check if any modifiers are present
    public var hasModifiers: Bool {
        !isEmpty
    }

    /// Create from existing ModifierSet
    public init(from modifierSet: ModifierSet) {
        var mods: ShortcutModifiers = []
        if modifierSet.contains(.control) { mods.insert(.control) }
        if modifierSet.contains(.option) { mods.insert(.option) }
        if modifierSet.contains(.shift) { mods.insert(.shift) }
        if modifierSet.contains(.command) { mods.insert(.command) }
        self = mods
    }
}

/// Data for KeyPath action events (URI-based)
public struct ActionEventData: Codable, Sendable, Equatable {
    public let action: String // e.g., "launch", "layer", "notify"
    public let target: String? // e.g., "Obsidian", "nav"
    public let uri: String // Full URI for reference

    public init(action: String, target: String?, uri: String) {
        self.action = action
        self.target = target
        self.uri = uri
    }
}
