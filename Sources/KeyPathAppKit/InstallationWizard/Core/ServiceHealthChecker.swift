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
// SAFETY: @unchecked Sendable — singleton with no mutable instance state.
// All methods are stateless queries delegating to SubprocessRunner or file checks.
final class ServiceHealthChecker: @unchecked Sendable {
    static let shared = ServiceHealthChecker()
    private nonisolated static let launchctlNotFoundExitCode: Int32 = 113
    private nonisolated static let kanataRestartGraceWindow: TimeInterval = 12.0

    private init() {}

    struct KanataServiceRuntimeSnapshot: Sendable, Equatable {
        let managementState: KanataDaemonManager.ServiceManagementState
        let isRunning: Bool
        let isResponding: Bool
        let launchctlExitCode: Int32?
        let staleEnabledRegistration: Bool
        let recentlyRestarted: Bool
    }

    enum KanataHealthDecision: Equatable {
        case healthy
        case transient(reason: String)
        case unhealthy(reason: String)

        var isHealthy: Bool {
            switch self {
            case .healthy, .transient:
                true
            case .unhealthy:
                false
            }
        }
    }

#if DEBUG
        nonisolated(unsafe) static var runtimeSnapshotOverride:
            (() async -> KanataServiceRuntimeSnapshot)?
        nonisolated(unsafe) static var recentlyRestartedOverride:
            ((String, TimeInterval?) -> Bool)?
#endif

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
            case .smappserviceActive:
                let stale = await KanataDaemonManager.shared.isRegisteredButNotLoaded()
                let loaded = !stale
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Kanata service loaded via SMAppService active state: loaded=\(loaded), stale=\(stale)"
                )
                return loaded
            case .smappservicePending:
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Kanata service approval pending - not loaded yet"
                )
                return false
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

        // Special handling for Kanata: SMAppService-managed installs can transiently fail `launchctl print`
        // (or be in a warm-up window) even when the daemon is starting. Prefer PID/TCP probes.
        if serviceID == Self.kanataServiceID, !TestEnvironment.shouldSkipAdminOperations {
            let state = await KanataDaemonManager.shared.refreshManagementState()
            if state.isSMAppServiceManaged {
                let runtimeSnapshot = await checkKanataServiceRuntimeSnapshot()
                let decision = Self.decideKanataHealth(for: runtimeSnapshot)
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Kanata SMAppService decision: \(decision), running=\(runtimeSnapshot.isRunning), responding=\(runtimeSnapshot.isResponding), stale=\(runtimeSnapshot.staleEnabledRegistration), state=\(state.description)"
                )
                return decision.isHealthy
            }
        }

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
            let runtimeSnapshot = await checkKanataServiceRuntimeSnapshot()
            kanataLoaded = runtimeSnapshot.managementState == .smappserviceActive
                && !runtimeSnapshot.staleEnabledRegistration
            kanataHealthy = Self.decideKanataHealth(for: runtimeSnapshot).isHealthy
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] Kanata SMAppService-managed: loaded=\(kanataLoaded), healthy=\(kanataHealthy), stale=\(runtimeSnapshot.staleEnabledRegistration), launchctlExit=\(runtimeSnapshot.launchctlExitCode?.description ?? "nil")"
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
        if TestEnvironment.shouldSkipAdminOperations {
            // Keep tests hermetic: avoid probing launchctl and real TCP sockets.
            return KanataHealthSnapshot(isRunning: false, isResponding: false)
        }

        // 1) launchctl check for PID using SubprocessRunner
        let runningState = await evaluateKanataLaunchctlRunningState()
        let isRunning = runningState.isRunning

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

    nonisolated func checkKanataServiceRuntimeSnapshot(
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataServiceRuntimeSnapshot {
#if DEBUG
        if let override = Self.runtimeSnapshotOverride {
            return await override()
        }
#endif

        let managementState = await KanataDaemonManager.shared.refreshManagementState()
        let staleEnabledRegistration: Bool = if managementState == .smappserviceActive {
            await KanataDaemonManager.shared.isRegisteredButNotLoaded()
        } else {
            false
        }

        return await checkKanataServiceRuntimeSnapshot(
            managementState: managementState,
            staleEnabledRegistration: staleEnabledRegistration,
            tcpPort: tcpPort,
            timeoutMs: timeoutMs
        )
    }

    /// Fast runtime probe using pre-fetched service-management metadata.
    ///
    /// This avoids repeated `SMAppService.status` checks in tight polling loops.
    nonisolated func checkKanataServiceRuntimeSnapshot(
        managementState: KanataDaemonManager.ServiceManagementState,
        staleEnabledRegistration: Bool,
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataServiceRuntimeSnapshot {
#if DEBUG
        if let override = Self.runtimeSnapshotOverride {
            return await override()
        }
#endif

        let runningState = await evaluateKanataLaunchctlRunningState()
        let tcpOK = await Task.detached { [self] in
            if let portEnv = ProcessInfo.processInfo.environment["KEYPATH_TCP_PORT"],
               let overridePort = Int(portEnv)
            {
                return probeTCP(port: overridePort, timeoutMs: timeoutMs)
            }
            return probeTCP(port: tcpPort, timeoutMs: timeoutMs)
        }.value

        return KanataServiceRuntimeSnapshot(
            managementState: managementState,
            isRunning: runningState.isRunning,
            isResponding: tcpOK,
            launchctlExitCode: runningState.exitCode,
            staleEnabledRegistration: staleEnabledRegistration,
            recentlyRestarted: Self.wasRecentlyRestarted(
                Self.kanataServiceID,
                within: Self.kanataRestartGraceWindow
            )
        )
    }

    private nonisolated func evaluateKanataLaunchctlRunningState() async
        -> (isRunning: Bool, exitCode: Int32?)
    {
        do {
            let result = try await SubprocessRunner.shared.launchctl(
                "print", ["system/\(Self.kanataServiceID)"]
            )
            if result.exitCode != 0 {
                return (false, result.exitCode)
            }

            for line in result.stdout.components(separatedBy: "\n") where line.contains("pid =") {
                let components = line.components(separatedBy: "=")
                if components.count == 2,
                   Int(components[1].trimmingCharacters(in: .whitespaces)) != nil
                {
                    return (true, result.exitCode)
                }
            }
            return (false, result.exitCode)
        } catch {
            AppLogger.shared.warn("⚠️ [ServiceHealthChecker] launchctl check failed: \(error)")
            return (false, nil)
        }
    }

    nonisolated static func decideKanataHealth(
        for runtimeSnapshot: KanataServiceRuntimeSnapshot
    ) -> KanataHealthDecision {
        if runtimeSnapshot.isRunning, runtimeSnapshot.isResponding {
            return .healthy
        }

        if runtimeSnapshot.staleEnabledRegistration {
            return .unhealthy(reason: "stale-enabled-registration")
        }

        if runtimeSnapshot.launchctlExitCode == Self.launchctlNotFoundExitCode,
           !runtimeSnapshot.isRunning,
           !runtimeSnapshot.isResponding
        {
            return .unhealthy(reason: "launchctl-not-found-without-runtime")
        }

        if runtimeSnapshot.isRunning,
           !runtimeSnapshot.isResponding,
           runtimeSnapshot.recentlyRestarted
        {
            return .transient(reason: "tcp-warmup-after-restart")
        }

        return .unhealthy(reason: "runtime-not-ready")
    }

    private nonisolated static func wasRecentlyRestarted(
        _ serviceID: String,
        within window: TimeInterval
    ) -> Bool {
#if DEBUG
        if let override = recentlyRestartedOverride {
            return override(serviceID, window)
        }
#endif
        return ServiceBootstrapper.wasRecentlyRestarted(serviceID, within: window)
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
        TCPProbe.probe(port: port, timeoutMs: timeoutMs)
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
