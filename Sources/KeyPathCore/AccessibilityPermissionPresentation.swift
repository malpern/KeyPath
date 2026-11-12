import Foundation

/// User-visible naming for the permission APIs and TCC call "Accessibility".
/// macOS 27, KeyPath's minimum, shows it as "Device Control and Data Access".
/// This does not change AX APIs, TCC identifiers, readiness policy, or the
/// System Settings deep link.
public struct AccessibilityPermissionPresentation: Sendable {
    public static let current = Self()

    public let name = String(localized: "Device Control and Data Access", comment: "macOS System Settings privacy pane name (Accessibility); use Apple's localized pane name")
    public let openButtonTitle = String(localized: "Open Settings")

    public init() {}

    public func displayName(for canonicalPermission: String) -> String {
        switch canonicalPermission {
        case "Accessibility": name
        case "Accessibility / effective input access": String(localized: "\(name) / effective input access")
        default: canonicalPermission
        }
    }

    public var settingsPath: String {
        String(localized: "System Settings > Privacy & Security > \(name)")
    }

    public var enableTitle: String {
        String(localized: "Enable \(name)")
    }

    public var enabledTitle: String {
        String(localized: "\(name) enabled")
    }

    public var openTitle: String {
        String(localized: "Open \(name)")
    }

    public var turnOnInstruction: String {
        String(localized: "Turn on KeyPath under \(name).")
    }

    public var grantInstruction: String {
        String(localized: "Open KeyPath.app and grant \(name) in \(settingsPath)")
    }
}
