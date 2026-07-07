import KeyPathCore

/// Lightweight POSIX TCP probe for checking if a localhost port is accepting connections.
///
/// Compatibility wrapper for older AppKit call sites while Phase 1 migrates TCP
/// readiness consumers to `SystemStateProvider`.
public enum TCPProbe: Sendable {
    /// Probe a TCP port on localhost. Blocking call — use from a detached task.
    ///
    /// Uses non-blocking `connect()` + `poll()` to avoid indefinite hangs.
    ///
    /// - Parameters:
    ///   - port: TCP port to probe on 127.0.0.1
    ///   - timeoutMs: Connection timeout in milliseconds (default 300)
    /// - Returns: `true` if the port accepted the connection
    public nonisolated static func probe(port: Int, timeoutMs: Int = 300) -> Bool {
        SystemStateProvider.probeTCPPort(port: port, timeoutMs: timeoutMs)
    }
}
