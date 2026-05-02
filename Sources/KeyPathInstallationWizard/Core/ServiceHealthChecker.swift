import Darwin
import Foundation
import KeyPathCore
import KeyPathWizardCore
import Network
import os.lock
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
// SAFETY: @unchecked Sendable — singleton with mutable state protected by OSAllocatedUnfairLock.
// The healthCache provides short-lived deduplication (~2s TTL) so that parallel validation tasks
// (e.g. checkHealth + checkComponents in SystemValidator) don't spawn redundant launchctl calls.
public final class ServiceHealthChecker: @unchecked Sendable {
    @MainActor public static let shared = ServiceHealthChecker()
    private nonisolated static let launchctlNotFoundExitCode: Int32 = 113
    private nonisolated static let kanataRestartGraceWindow: TimeInterval = 12.0

    // MARK: - Short-lived health cache

    private struct HealthCacheEntry {
        let result: Bool
        let timestamp: Date
        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    private nonisolated static let healthCacheTTL: TimeInterval = 2.0

    private let healthCache = OSAllocatedUnfairLock(initialState: [String: HealthCacheEntry]())

    /// Clear cached health results. Useful in tests or after service state changes.
    public nonisolated func invalidateHealthCache() {
        healthCache.withLock { $0.removeAll() }
    }

    // MARK: - Dependencies

    private let subprocessRunner: SubprocessRunner

    @MainActor
    public init(
        subprocessRunner: SubprocessRunner = .shared
    ) {
        self.subprocessRunner = subprocessRunner
    }

    /// Access daemon manager via WizardDependencies (async to allow actor hop).
    /// Returns nil when WizardDependencies is not configured (e.g. in tests without DI setup).
    private nonisolated func getDaemonManager() async -> (any WizardDaemonManaging)? {
        await MainActor.run { WizardDependencies.daemonManager }
    }

    /// Fallback management state used when daemon manager is unavailable.
    private static let fallbackManagementState: WizardServiceManagementState = .uninstalled

    public struct KanataServiceRuntimeSnapshot: Sendable, Equatable {
        public let managementState: WizardServiceManagementState
        public let isRunning: Bool
        public let isResponding: Bool
        public let inputCaptureReady: Bool
        public let inputCaptureIssue: String?
        public let launchctlExitCode: Int32?
        public let staleEnabledRegistration: Bool
        public let recentlyRestarted: Bool
    }

    public struct KanataInputCaptureStatus: Sendable, Equatable {
        public let isReady: Bool
        public let issue: String?

        public static let ready = KanataInputCaptureStatus(isReady: true, issue: nil)
    }

    /// Unified diagnosis from a single read of the kanata daemon stderr log.
    /// Replaces the separate `checkDaemonStderrForPermissionFailure()` and
    /// `checkKanataInputCaptureStatus()` parsers that read the same file
    /// with different tail sizes and overlapping patterns.
    public struct KanataDaemonDiagnosis: Sendable, Equatable {
        /// True when stderr contains an Accessibility permission rejection
        public let permissionRejected: Bool
        /// Input capture status (keyboard open failure)
        public let inputCapture: KanataInputCaptureStatus

        public static let clear = KanataDaemonDiagnosis(
            permissionRejected: false,
            inputCapture: .ready
        )
    }

    public enum KanataHealthDecision: Equatable {
        case healthy
        case transient(reason: String)
        case unhealthy(reason: String)

        public var isHealthy: Bool {
            switch self {
            case .healthy, .transient:
                true
            case .unhealthy:
                false
            }
        }
    }

    #if DEBUG
        public nonisolated(unsafe) static var runtimeSnapshotOverride:
            (() async -> KanataServiceRuntimeSnapshot)?
        public nonisolated(unsafe) static var recentlyRestartedOverride:
            ((String, TimeInterval?) -> Bool)?
        public nonisolated(unsafe) static var inputCaptureStatusOverride:
            (() async -> KanataInputCaptureStatus)?
    #endif

    // MARK: - Service Identifiers

    /// Service identifier for the main Kanata keyboard remapping daemon
    public static let kanataServiceID = "com.keypath.kanata"

    /// Service identifier for the Karabiner Virtual HID Device daemon
    public static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"

    /// Service identifier for the Karabiner Virtual HID Device manager
    public static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    // MARK: - Service Loaded Check

    /// Checks if a LaunchDaemon service is currently loaded in launchd.
    ///
    /// For Kanata service, uses state determination to handle SMAppService vs LaunchDaemon.
    /// For other services, uses `launchctl print` to check system domain.
    ///
    /// - Parameter serviceID: The service identifier to check
    /// - Returns: `true` if the service is loaded
    public nonisolated func isServiceLoaded(serviceID: String) async -> Bool {
        // Special handling for Kanata service: Use state determination for consistent detection
        if serviceID == Self.kanataServiceID {
            if TestEnvironment.shouldSkipAdminOperations {
                let plistPath = getPlistPath(for: serviceID)
                let exists = Foundation.FileManager().fileExists(atPath: plistPath)
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] (test) Kanata service loaded via file existence: \(exists)"
                )
                return exists
            }

            let state = await getDaemonManager()?.refreshManagementState() ?? Self.fallbackManagementState
            AppLogger.shared.log("🔍 [ServiceHealthChecker] Kanata service state: \(state.description)")

            switch state {
            case .legacyActive:
                // Legacy plist exists - check launchctl status
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] Legacy plist exists - checking launchctl status"
                )
            // Fall through to launchctl check below
            case .smappserviceActive:
                let stale = await getDaemonManager()?.isRegisteredButNotLoaded() ?? false
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
            let exists = Foundation.FileManager().fileExists(atPath: plistPath)
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] (test) Service \(serviceID) considered loaded: \(exists)"
            )
            return exists
        }

        do {
            let result = try await subprocessRunner.launchctl("print", ["system/\(serviceID)"])
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
    public nonisolated func isServiceHealthy(serviceID: String) async -> Bool {
        // Check short-lived cache first — avoids redundant launchctl calls within the same
        // validation cycle when multiple parallel tasks query the same service.
        if let cached = healthCache.withLock({ $0[serviceID] }),
           cached.isValid(ttl: Self.healthCacheTTL)
        {
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] isServiceHealthy() CACHE HIT for: \(serviceID) → \(cached.result)"
            )
            return cached.result
        }

        let result = await _isServiceHealthyUncached(serviceID: serviceID)

        healthCache.withLock {
            $0[serviceID] = HealthCacheEntry(result: result, timestamp: Date())
        }

        return result
    }

    private nonisolated func _isServiceHealthyUncached(serviceID: String) async -> Bool {
        AppLogger.shared.log(
            "🔍 [ServiceHealthChecker] isServiceHealthy() ENTRY - HEALTH CHECK (system/print) for: \(serviceID)"
        )
        let startTime = Date()

        // Special handling for Kanata: SMAppService-managed installs can transiently fail `launchctl print`
        // (or be in a warm-up window) even when the daemon is starting. Prefer PID/TCP probes.
        if serviceID == Self.kanataServiceID, !TestEnvironment.shouldSkipAdminOperations {
            let state = await getDaemonManager()?.refreshManagementState() ?? Self.fallbackManagementState
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
            let exists = Foundation.FileManager().fileExists(atPath: plistPath)
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] (test) Service \(serviceID) considered healthy: \(exists)"
            )
            return exists
        }

        AppLogger.shared.log(
            "🔍 [ServiceHealthChecker] About to call SubprocessRunner.launchctl(\"print\", [\"system/\(serviceID)\"])..."
        )
        do {
            let result = try await subprocessRunner.launchctl("print", ["system/\(serviceID)"])
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
    public nonisolated func getServiceStatus() async -> LaunchDaemonStatus {
        // Fast path: Check Kanata state first to avoid expensive checks if SMAppService is managing it
        let kanataState = await getDaemonManager()?.refreshManagementState() ?? Self.fallbackManagementState
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
    public nonisolated func checkKanataServiceHealth(
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataHealthSnapshot {
        if TestEnvironment.shouldSkipAdminOperations {
            // Keep tests hermetic: avoid probing launchctl and real TCP sockets.
            return KanataHealthSnapshot(isRunning: false, isResponding: false)
        }

        let managementState = await getDaemonManager()?.refreshManagementState() ?? Self.fallbackManagementState
        let targets = await getDaemonManager()?.preferredLaunchctlTargets(for: managementState) ?? []

        // 1) launchctl check for PID using SubprocessRunner
        let runningState = await evaluateKanataLaunchctlRunningState(managementState: managementState, launchctlTargets: targets)
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

    public nonisolated func checkKanataServiceRuntimeSnapshot(
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataServiceRuntimeSnapshot {
        #if DEBUG
            if let override = Self.runtimeSnapshotOverride {
                return await override()
            }
        #endif

        let managementState = await getDaemonManager()?.refreshManagementState() ?? Self.fallbackManagementState
        let staleEnabledRegistration: Bool = if managementState == .smappserviceActive {
            await getDaemonManager()?.isRegisteredButNotLoaded() ?? false
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
    public nonisolated func checkKanataServiceRuntimeSnapshot(
        managementState: WizardServiceManagementState,
        staleEnabledRegistration: Bool,
        tcpPort: Int = 37001,
        timeoutMs: Int = 300
    ) async -> KanataServiceRuntimeSnapshot {
        #if DEBUG
            if let override = Self.runtimeSnapshotOverride {
                return await override()
            }
        #endif

        let targets = await getDaemonManager()?.preferredLaunchctlTargets(for: managementState) ?? []
        let runningState = await evaluateKanataLaunchctlRunningState(managementState: managementState, launchctlTargets: targets)
        let stderrDiagnosis = await diagnoseDaemonStderr()
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
            inputCaptureReady: stderrDiagnosis.inputCapture.isReady,
            inputCaptureIssue: stderrDiagnosis.inputCapture.issue,
            launchctlExitCode: runningState.exitCode,
            staleEnabledRegistration: staleEnabledRegistration,
            recentlyRestarted: Self.wasRecentlyRestarted(
                Self.kanataServiceID,
                within: Self.kanataRestartGraceWindow
            )
        )
    }

    private nonisolated func evaluateKanataLaunchctlRunningState(
        managementState: WizardServiceManagementState,
        launchctlTargets: [String]
    ) async
        -> (isRunning: Bool, exitCode: Int32?)
    {
        var lastExitCode: Int32?
        for target in launchctlTargets {
            do {
                let result = try await subprocessRunner.launchctl("print", [target])
                lastExitCode = result.exitCode
                if result.exitCode != 0 {
                    continue
                }

                for line in result.stdout.components(separatedBy: "\n") where line.contains("pid =") {
                    let components = line.components(separatedBy: "=")
                    if components.count == 2,
                       Int(components[1].trimmingCharacters(in: .whitespaces)) != nil
                    {
                        return (true, result.exitCode)
                    }
                }
            } catch {
                AppLogger.shared.warn("⚠️ [ServiceHealthChecker] launchctl check failed for \(target): \(error)")
            }
        }
        return (false, lastExitCode)
    }

    public nonisolated static func decideKanataHealth(
        for runtimeSnapshot: KanataServiceRuntimeSnapshot
    ) -> KanataHealthDecision {
        if !runtimeSnapshot.inputCaptureReady {
            return .unhealthy(reason: runtimeSnapshot.inputCaptureIssue ?? "input-capture-not-ready")
        }

        if runtimeSnapshot.isRunning, runtimeSnapshot.isResponding {
            return .healthy
        }

        if runtimeSnapshot.staleEnabledRegistration {
            return .unhealthy(reason: "stale-enabled-registration")
        }

        if runtimeSnapshot.launchctlExitCode == launchctlNotFoundExitCode,
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

    /// Read the kanata daemon stderr log once and classify all known error patterns.
    /// This replaces `checkDaemonStderrForPermissionFailure()` (SystemValidator) and
    /// `checkKanataInputCaptureStatus()` (ServiceHealthChecker) which previously read
    /// the same file with different tail sizes and overlapping patterns.
    public nonisolated func diagnoseDaemonStderr() async -> KanataDaemonDiagnosis {
        #if DEBUG
            if let override = Self.inputCaptureStatusOverride {
                let capture = await override()
                return KanataDaemonDiagnosis(permissionRejected: false, inputCapture: capture)
            }
        #endif

        guard let logChunk = readRecentKanataStderrLog(), !logChunk.isEmpty else {
            return .clear
        }

        var permissionRejected = false
        var inputCaptureIssue: KanataInputCaptureStatus = .ready

        // AX permission rejection: either the explicit message, or a generic IOHIDDeviceOpen
        // denial that is NOT specific to "Apple Internal Keyboard / Trackpad" (which is an IM issue).
        if logChunk.contains("kanata needs macOS Accessibility permission") {
            permissionRejected = true
        } else if logChunk.contains("IOHIDDeviceOpen error"), logChunk.contains("not permitted") {
            // Check if ALL IOHIDDeviceOpen errors are the keyboard-specific variant.
            // If any line has the error WITHOUT the keyboard specifier, it's an AX issue.
            let lines = logChunk.components(separatedBy: .newlines)
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("iohiddeviceopen error"), lower.contains("not permitted"),
                   !lower.contains("apple internal keyboard / trackpad")
                {
                    permissionRejected = true
                    break
                }
            }
        }

        // Check for input capture failure (built-in keyboard can't be opened)
        // Only meaningful if NOT already explained by AX rejection
        if !permissionRejected {
            for rawLine in logChunk.components(separatedBy: .newlines).reversed() {
                let lower = rawLine.lowercased()
                guard lower.contains("iohiddeviceopen error"),
                      lower.contains("not permitted"),
                      lower.contains("apple internal keyboard / trackpad")
                else { continue }
                inputCaptureIssue = KanataInputCaptureStatus(
                    isReady: false,
                    issue: "kanata-cannot-open-built-in-keyboard"
                )
                break
            }
        }

        return KanataDaemonDiagnosis(
            permissionRejected: permissionRejected,
            inputCapture: inputCaptureIssue
        )
    }

    // MARK: - Configuration Checks

    /// Check if Kanata service plist file exists (but may not be loaded).
    ///
    /// - Returns: `true` if the plist file exists
    public func isKanataPlistInstalled() -> Bool {
        let plistPath = getKanataPlistPath()
        return Foundation.FileManager().fileExists(atPath: plistPath)
    }

    /// Verifies that the installed VHID LaunchDaemon plist points to the DriverKit daemon path.
    ///
    /// - Returns: `true` if the plist is correctly configured
    public func isVHIDDaemonConfiguredCorrectly() -> Bool {
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

    private nonisolated func readRecentKanataStderrLog(maxBytes: Int = 64 * 1024) -> String? {
        let stderrPath = ProcessInfo.processInfo.environment["KEYPATH_KANATA_STDERR_PATH"]
            ?? KeyPathConstants.Logs.kanataStderr
        guard let fileHandle = FileHandle(forReadingAtPath: stderrPath) else {
            return nil
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64 = (try? fileHandle.seekToEnd()) ?? 0
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        try? fileHandle.seek(toOffset: offset)
        guard let data = try? fileHandle.readToEnd(), !data.isEmpty else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
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
        // Use POSIX socket probe directly since TCPProbe is in KeyPathAppKit
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Set non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollFd, 1, Int32(timeoutMs))
        guard pollResult > 0 else { return false }

        var optError: Int32 = 0
        var optLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &optError, &optLen)
        return optError == 0
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
