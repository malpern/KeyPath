import Foundation

/// User-visible naming for the permission APIs and TCC call "Accessibility".
/// macOS 27, KeyPath's minimum, shows it as "Device Control and Data Access".
/// This does not change AX APIs, TCC identifiers, readiness policy, or the
/// System Settings deep link.
public struct AccessibilityPermissionPresentation: Sendable {
    public static let current = Self()

    public let name = "Device Control and Data Access"
    public let openButtonTitle = "Open Settings"

    public init() {}

    public func displayName(for canonicalPermission: String) -> String {
        switch canonicalPermission {
        case "Accessibility": name
        case "Accessibility / effective input access": "\(name) / effective input access"
        default: canonicalPermission
        }
    }

    public var settingsPath: String {
        "System Settings > Privacy & Security > \(name)"
    }

    public var enableTitle: String {
        "Enable \(name)"
    }

    public var enabledTitle: String {
        "\(name) enabled"
    }

    public var openTitle: String {
        "Open \(name)"
    }

    public var turnOnInstruction: String {
        "Turn on KeyPath under \(name)."
    }

    public var grantInstruction: String {
        "Open KeyPath.app and grant \(name) in \(settingsPath)"
    }
}
