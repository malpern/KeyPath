import Foundation

/// Abstraction for privileged operations needed by KeyPath.
///
/// This is the seam we'll later swap from the legacy (osascript/launchctl)
/// implementation to an SMAppService/XPC-backed privileged helper.
public protocol PrivilegedOperations: Sendable {
    /// Start the Kanata LaunchDaemon service.
    func startKanataService() async -> Bool

    /// Restart the Kanata LaunchDaemon service.
    func restartKanataService() async -> Bool

    /// Stop the Kanata LaunchDaemon service.
    func stopKanataService() async -> Bool
}
