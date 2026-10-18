import Foundation

/// User-visible macOS permission naming. This does not change AX APIs, TCC
/// identifiers, readiness policy, or the existing System Settings deep link.
public struct AccessibilityPermissionPresentation: Sendable {
    public static var current: Self {
        Self(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    public let name: String
    public let openButtonTitle: String

    public init(macOSMajorVersion: Int) {
        openButtonTitle = macOSMajorVersion >= 27 ? "Open Settings" : "Open Accessibility"
        name = macOSMajorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    public func displayName(for canonicalPermission: String) -> String {
        switch canonicalPermission {
        case "Accessibility": name
        case "Accessibility / effective input access": "\(name) / effective input access"
        default: canonicalPermission
        }
    }

    public var settingsPath: String { "System Settings > Privacy & Security > \(name)" }
    public var enableTitle: String { "Enable \(name)" }
    public var enabledTitle: String { "\(name) enabled" }
    public var openTitle: String { "Open \(name)" }
    public var turnOnInstruction: String { "Turn on KeyPath under \(name)." }
    public var grantInstruction: String { "Open KeyPath.app and grant \(name) in \(settingsPath)" }
}
