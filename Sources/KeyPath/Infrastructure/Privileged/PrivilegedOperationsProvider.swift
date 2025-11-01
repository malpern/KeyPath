import Foundation

/// Central access point for acquiring the app-wide PrivilegedOperations implementation.
///
/// Initially backed by the legacy implementation; later will be swapped to the
/// SMAppService/XPC-backed implementation without touching call sites.
public enum PrivilegedOperationsProvider: Sendable {
    public static let shared: PrivilegedOperations = {
        if TestEnvironment.isTestMode {
            return MockPrivilegedOperations()
        }
        return HelperBackedPrivilegedOperations()
    }()
}
