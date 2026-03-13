import Darwin

/// Lightweight POSIX TCP probe for checking if a localhost port is accepting connections.
///
/// Used by both `ServiceHealthChecker` (wizard health checks) and `KanataService`
/// (fallback before declaring service failure when PID detection misses).
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
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        // Set non-blocking
        _ = fcntl(sock, F_SETFL, O_NONBLOCK)

        var a = addr
        let connectResult = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            close(sock)
            return true
        }

        // EINPROGRESS is expected for non-blocking connect
        if errno != EINPROGRESS {
            close(sock)
            return false
        }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let ret = Darwin.poll(&pfd, 1, Int32(timeoutMs))
        if ret > 0, (pfd.revents & Int16(POLLOUT)) != 0 {
            var so_error: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &so_error, &len)
            close(sock)
            return so_error == 0
        }

        close(sock)
        return false
    }
}
