import Darwin
import Foundation
import KeyPathCore
import Network

extension LaunchDaemonInstaller {
    /// Unified kanata service health: launchctl PID check + TCP probe.
    nonisolated func checkKanataServiceHealth(
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataServiceHealth {
        let isRunning = await Task.detached {
            // 1) launchctl check for PID
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["print", "system/\(Self.kanataServiceID)"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            var pid: Int?
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if task.terminationStatus == 0 {
                    for line in output.components(separatedBy: "\n") where line.contains("pid =") {
                        let comps = line.components(separatedBy: "=")
                        if comps.count == 2, let p = Int(comps[1].trimmingCharacters(in: .whitespaces)) {
                            pid = p
                            break
                        }
                    }
                }
            } catch {
                AppLogger.shared.warn("⚠️ [Health] launchctl check failed: \(error)")
            }
            return pid != nil
        }.value

        // 2) TCP probe (Hello/Status)
        // probeTCP uses socket syscalls which are blocking but very fast with non-blocking connect/poll.
        // However, to be safe, we can run it on the detached task too or just keep it here since it uses O_NONBLOCK.
        // Given it uses O_NONBLOCK and poll, it suspends? No, poll blocks the thread.
        // We should wrap TCP probe in detached task too.

        let tcpOK = await Task.detached {
            if let portEnv = ProcessInfo.processInfo.environment["KEYPATH_TCP_PORT"],
               let overridePort = Int(portEnv)
            {
                return self.probeTCP(port: overridePort, timeoutMs: timeoutMs)
            }
            return self.probeTCP(port: tcpPort, timeoutMs: timeoutMs)
        }.value

        return KanataServiceHealth(
            isRunning: isRunning,
            isResponding: tcpOK
        )
    }

    private nonisolated func probeTCP(port: Int, timeoutMs: Int) -> Bool {
        // Simple POSIX connect with timeout to avoid Sendable/atomic issues
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
