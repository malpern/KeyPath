import Foundation

public enum KanataRuntimeBackend: String, Codable, Sendable {
    case driverKit
    case session

    /// This experimental build always uses the unprivileged session runtime.
    /// `driverKit` remains decodable for historical snapshots and explicit test fixtures;
    /// neither legacy environment variables nor command-line flags can select it.
    public static var selected: Self {
        .session
    }

    public var requiresPrivilegedServices: Bool {
        self == .driverKit
    }
}
