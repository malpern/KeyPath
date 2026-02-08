import Darwin
import Foundation
import KeyPathCore
import Network
import os.lock

/// Handles health checking and status reporting for LaunchDaemon services.
///
/// This service provides comprehensive health checking capabilities extracted from
/// LaunchDaemonInstaller to support both LaunchDaemon and SMAppService paths.
///
/// ## Health Check Operations
/// - `isServiceLoaded`: Check if a service is loaded in launchd
/// - `isServiceHealthy`: Check if a service is running properly
/// - `getServiceStatus`: Get comprehensive status of all services
/// - `checkKanataServiceHealth`: Unified Kanata health check (PID + TCP)
///
/// ## Service Configuration Checks
/// - `isKanataPlistInstalled`: Check if Kanata plist exists
/// - `isVHIDDaemonConfiguredCorrectly`: Verify VHID plist configuration
final class ServiceHealthChecker: @unchecked Sendable {
    static let shared = ServiceHealthChecker()

    private init() {}

    // MARK: - Service Identifiers

    /// Service identifier for the main Kanata keyboard remapping daemon
    static let kanataServiceID = "com.keypath.kanata"

    /// Service identifier for the Karabiner Virtual HID Device daemon
    static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"

    /// Service identifier for the Karabiner Virtual HID Device manager
    static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    // MARK: - Service Loaded Check

    /// Checks if a LaunchDaemon service is currently loaded in launchd.
    ///
    /// For Kanata service, uses state determination to handle SMAppService vs LaunchDaemon.
    /// For other services, uses `launchctl print` to check system domain.
    ///
    /// - Parameter serviceID: The service identifier to check
    /// - Returns: `true` if the service is loaded
    nonisolated func isServiceLoaded(serviceID: String) async -> Bool {
        // Special handling for Kanata service: Use state determination for consistent detection
        if serviceID == Self.kanataServiceID {
            if TestEnvironment.shouldSkipAdminOperations {
                let plistPath = getPlistPath(for: serviceID)
                let exists = FileManager.default.fileExists(atPath: plistPath)
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] (test) Kanata service loaded via file existence: \(exists)"
                )
                return exists
            }

            let state = await KanataDaemonManager.shared.refreshManagementState()
            AppLogger.shared.log("🔍 [ServiceHealthChecker] Kanata service state: \(state.description)")

            switch state {
            case .legacyActive:
                // Legacy plist exists - check launchctl status
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Legacy plist exists - checking launchctl status"
                )
            // Fall through to launchctl check below
            case .smappserviceActive, .smappservicePending:
                // SMAppService is managing - consider it loaded
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Kanata service loaded via SMAppService (state: \(state.description))"
                )
                return true
            case .conflicted:
                // Both active - consider it loaded (SMAppService takes precedence)
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Conflicted state - considering loaded (SMAppService active)"
                )
                return true
            case .unknown:
                // Process running but unclear - check process, consider loaded if running
                if await checkKanataServiceHealth().isRunning {
                    AppLogger.shared.log(
                        "🔍 [ServiceHealthChecker] Unknown state but process running - considering loaded"
                    )
                    return true
                }
                return false
            case .uninstalled:
                // Not installed
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Service not installed (state: \(state.description))"
                )
                return false
            }
        }

        // For non-Kanata services or Kanata in legacy mode, use launchctl print
        if TestEnvironment.shouldSkipAdminOperations {
            let plistPath = getPlistPath(for: serviceID)
            let exists = FileManager.default.fileExists(atPath: plistPath)
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] (test) Service \(serviceID) considered loaded: \(exists)"
            )
            return exists
        }

        do {
            let result = try await SubprocessRunner.shared.launchctl("print", ["system/\(serviceID)"])
            let isLoaded = result.exitCode == 0
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] (system) Service \(serviceID) loaded: \(isLoaded)"
            )
            return isLoaded
        } catch {
            AppLogger.shared.log(
                "❌ [ServiceHealthChecker] Error checking service \(serviceID): \(error)"
            )
            return false
        }
    }

    // MARK: - Service Health Check

    /// Checks if a LaunchDaemon service is running healthily (not just loaded).
    ///
    /// Analyzes `launchctl print` output to determine if the service process is running
    /// and in a healthy state. Handles one-shot services differently from KeepAlive services.
    ///
    /// - Parameter serviceID: The service identifier to check
    /// - Returns: `true` if the service is healthy
    nonisolated func isServiceHealthy(serviceID: String) async -> Bool {
        AppLogger.shared.log(
            "🔍 [ServiceHealthChecker] isServiceHealthy() ENTRY - HEALTH CHECK (system/print) for: \(serviceID)"
        )
        let startTime = Date()

        if TestEnvironment.shouldSkipAdminOperations {
            let plistPath = getPlistPath(for: serviceID)
            let exists = FileManager.default.fileExists(atPath: plistPath)
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] (test) Service \(serviceID) considered healthy: \(exists)"
            )
            return exists
        }

        AppLogger.shared.log(
            "🔍 [ServiceHealthChecker] About to call SubprocessRunner.launchctl(\"print\", [\"system/\(serviceID)\"])..."
        )
        do {
            let result = try await SubprocessRunner.shared.launchctl("print", ["system/\(serviceID)"])
            let launchctlDuration = Date().timeIntervalSince(startTime)
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] SubprocessRunner.launchctl() returned (took \(String(format: "%.3f", launchctlDuration))s, exitCode=\(result.exitCode))"
            )

            guard result.exitCode == 0 else {
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] \(serviceID) not found in system domain"
                )
                return false
            }

            let output = result.stdout

            // Extract details from 'launchctl print' output
            let state = output.firstMatchString(pattern: #"state\s*=\s*([A-Za-z]+)"#)?.lowercased()
            let pid =
                output.firstMatchInt(pattern: #"\bpid\s*=\s*([0-9]+)"#)
                    ?? output.firstMatchInt(pattern: #""PID"\s*=\s*([0-9]+)"#)
            let lastExit =
                output.firstMatchInt(pattern: #"last exit (?:status|code)\s*=\s*(-?\d+)"#)
                    ?? output.firstMatchInt(pattern: #""LastExitStatus"\s*=\s*(-?\d+)"#)

            let isOneShot = (serviceID == Self.vhidManagerServiceID)
            let isRunningLike = (state == "running" || state == "launching")
            let hasPID = (pid != nil)
            let inWarmup = ServiceBootstrapper.wasRecentlyRestarted(serviceID)

            var healthy = false
            if isOneShot {
                // One-shot services run once and exit - this is normal behavior
                if let lastExit {
                    // If we have exit status, it must be clean (0)
                    healthy = (lastExit == 0)
                } else if isRunningLike || hasPID || inWarmup {
                    // Service currently running or starting up
                    healthy = true
                } else {
                    // No exit status and not running - assume it ran successfully
                    // This is normal for one-shot services that run at boot
                    AppLogger.shared.log(
                        "🔍 [ServiceHealthChecker] One-shot service \(serviceID) not running (normal) - assuming healthy"
                    )
                    healthy = true
                }
            } else {
                // KeepAlive jobs should be running. Allow starting states or warm-up.
                if isRunningLike || hasPID {
                    healthy = true
                } else if inWarmup {
                    healthy = true
                } // starting up
                else {
                    healthy = false
                }
            }

            AppLogger.shared.log("🔍 [ServiceHealthChecker] HEALTH ANALYSIS \(serviceID):")
            AppLogger.shared
                .log(
                    "    state=\(state ?? "nil"), pid=\(pid?.description ?? "nil"), lastExit=\(lastExit?.description ?? "nil"), oneShot=\(isOneShot), warmup=\(inWarmup), healthy=\(healthy)"
                )

            let totalDuration = Date().timeIntervalSince(startTime)
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] isServiceHealthy() EXIT - Returning \(healthy) for \(serviceID) (total: \(String(format: "%.3f", totalDuration))s)"
            )
            return healthy
        } catch {
            let totalDuration = Date().timeIntervalSince(startTime)
            AppLogger.shared.log(
                "❌ [ServiceHealthChecker] isServiceHealthy() EXIT (ERROR) - Error checking service health \(serviceID): \(error) (total: \(String(format: "%.3f", totalDuration))s)"
            )
            return false
        }
    }

    // MARK: - Comprehensive Status

    /// Gets comprehensive status of all LaunchDaemon services.
    ///
    /// Optimized for SMAppService-managed Kanata: skips expensive launchctl checks
    /// when SMAppService is managing the service.
    ///
    /// - Returns: `LaunchDaemonStatus` with loaded and healthy status for all services
    nonisolated func getServiceStatus() async -> LaunchDaemonStatus {
        // Fast path: Check Kanata state first to avoid expensive checks if SMAppService is managing it
        let kanataState = await KanataDaemonManager.shared.refreshManagementState()
        let kanataLoaded: Bool
        let kanataHealthy: Bool

        if kanataState.isSMAppServiceManaged {
            // SMAppService is managing Kanata - use fast checks
            kanataLoaded = true // SMAppService managed = loaded
            // For health, just check if process is running (faster than launchctl print)
            kanataHealthy = await checkKanataServiceHealth().isRunning
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] Kanata SMAppService-managed: loaded=true, healthy=\(kanataHealthy)"
            )
        } else {
            // Legacy or unknown - use full checks
            kanataLoaded = await isServiceLoaded(serviceID: Self.kanataServiceID)
            kanataHealthy = await isServiceHealthy(serviceID: Self.kanataServiceID)
        }

        // VHID services always use launchctl (no SMAppService option)
        let vhidDaemonLoaded = await isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerLoaded = await isServiceLoaded(serviceID: Self.vhidManagerServiceID)
        let vhidDaemonHealthy = await isServiceHealthy(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerHealthy = await isServiceHealthy(serviceID: Self.vhidManagerServiceID)

        return LaunchDaemonStatus(
            kanataServiceLoaded: kanataLoaded,
            vhidDaemonServiceLoaded: vhidDaemonLoaded,
            vhidManagerServiceLoaded: vhidManagerLoaded,
            kanataServiceHealthy: kanataHealthy,
            vhidDaemonServiceHealthy: vhidDaemonHealthy,
            vhidManagerServiceHealthy: vhidManagerHealthy
        )
    }

    // MARK: - Kanata-Specific Health Check

    /// Unified Kanata service health check: launchctl PID check + TCP probe.
    ///
    /// This provides a comprehensive health check that verifies both:
    /// 1. The process is running (via launchctl print)
    /// 2. The TCP server is responding (via socket connection)
    ///
    /// - Parameters:
    ///   - tcpPort: TCP port to probe (default: 37001)
    ///   - timeoutMs: TCP connection timeout in milliseconds (default: 300)
    /// - Returns: `KanataHealthSnapshot` with running and responding status
    nonisolated func checkKanataServiceHealth(
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataHealthSnapshot {
        // 1) launchctl check for PID using SubprocessRunner
        let isRunning: Bool
        do {
            let result = try await SubprocessRunner.shared.launchctl(
                "print", ["system/\(Self.kanataServiceID)"]
            )
            if result.exitCode == 0 {
                // Look for pid = in the output
                var foundPid = false
                for line in result.stdout.components(separatedBy: "\n") where line.contains("pid =") {
                    let comps = line.components(separatedBy: "=")
                    if comps.count == 2,
                       Int(comps[1].trimmingCharacters(in: .whitespaces)) != nil
                    {
                        foundPid = true
                        break
                    }
                }
                isRunning = foundPid
            } else {
                isRunning = false
            }
        } catch {
            AppLogger.shared.warn("⚠️ [ServiceHealthChecker] launchctl check failed: \(error)")
            isRunning = false
        }

        // 2) TCP probe (Hello/Status) - runs off MainActor via Task.detached for blocking socket ops
        let tcpOK = await Task.detached { [self] in
            if let portEnv = ProcessInfo.processInfo.environment["KEYPATH_TCP_PORT"],
               let overridePort = Int(portEnv)
            {
                return probeTCP(port: overridePort, timeoutMs: timeoutMs)
            }
            return probeTCP(port: tcpPort, timeoutMs: timeoutMs)
        }.value

        return KanataHealthSnapshot(
            isRunning: isRunning,
            isResponding: tcpOK
        )
    }

    // MARK: - Configuration Checks

    /// Check if Kanata service plist file exists (but may not be loaded).
    ///
    /// - Returns: `true` if the plist file exists
    func isKanataPlistInstalled() -> Bool {
        let plistPath = getKanataPlistPath()
        return FileManager.default.fileExists(atPath: plistPath)
    }

    /// Verifies that the installed VHID LaunchDaemon plist points to the DriverKit daemon path.
    ///
    /// - Returns: `true` if the plist is correctly configured
    func isVHIDDaemonConfiguredCorrectly() -> Bool {
        let plistPath = getPlistPath(for: Self.vhidDaemonServiceID)
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] VHID plist not found or unreadable at: \(plistPath)"
            )
            return false
        }

        let expectedPath =
            "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            let ok = first == expectedPath
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] VHID plist ProgramArguments[0]=\(first) | expected=\(expectedPath) | ok=\(ok)"
            )
            return ok
        }
        AppLogger.shared.log(
            "🔍 [ServiceHealthChecker] VHID plist ProgramArguments missing or malformed"
        )
        return false
    }

    // MARK: - Private Helpers

    /// Get the plist file path for a service
    private func getPlistPath(for serviceID: String) -> String {
        let launchDaemonsPath = getLaunchDaemonsPath()
        return "\(launchDaemonsPath)/\(serviceID).plist"
    }

    /// Get the Kanata service plist path
    private func getKanataPlistPath() -> String {
        getPlistPath(for: Self.kanataServiceID)
    }

    /// Get the launchd daemons directory path
    private func getLaunchDaemonsPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let override = env["KEYPATH_LAUNCH_DAEMONS_DIR"], !override.isEmpty {
            return override
        }
        return WizardSystemPaths.remapSystemPath("/Library/LaunchDaemons")
    }

    /// Probe TCP port to check if service is responding.
    ///
    /// Uses POSIX socket with non-blocking connect and poll for timeout handling.
    ///
    /// - Parameters:
    ///   - port: TCP port to probe
    ///   - timeoutMs: Connection timeout in milliseconds
    /// - Returns: `true` if connection succeeded
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

// MARK: - String Extensions for Pattern Matching

private extension String {
    /// Extract first integer match from regex pattern
    func firstMatchInt(pattern: String) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let match = rx.firstMatch(in: self, range: nsRange), match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return Int(self[range])
        } catch {
            return nil
        }
    }

    /// Extract first string match from regex pattern
    func firstMatchString(pattern: String) -> String? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let match = rx.firstMatch(in: self, range: nsRange), match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return String(self[range])
        } catch {
            return nil
        }
    }
}
