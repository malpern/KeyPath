import Foundation

public enum KanataRuntimeBackend: String, Codable, Sendable {
    case driverKit
    case session

    /// Remains opt-in until final signed-app and hardware acceptance passes.
    public static var selected: Self {
        ProcessInfo.processInfo.environment["KEYPATH_EXPERIMENTAL_SESSION_RUNTIME"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--driverless") ? .session : .driverKit
    }

    public var requiresPrivilegedServices: Bool {
        self == .driverKit
    }
}
