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
    public var id: String {
        deviceHash
    }

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
