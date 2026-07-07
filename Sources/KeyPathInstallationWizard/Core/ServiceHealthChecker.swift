import Foundation
import KeyPathCore
import KeyPathWizardCore
import os.lock

/// Handles health checking and status reporting for LaunchDaemon services.
///
/// This service provides comprehensive health checking capabilities extracted from
/// supporting both LaunchDaemon and SMAppService paths.
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

    /// Reason codes for input-capture failures, shared with SystemInspector.
    public nonisolated static let inputCaptureBuiltInKeyboardReason = "kanata-cannot-open-built-in-keyboard"
    public nonisolated static let inputCaptureGrabFailureReason = "kanata-failed-to-grab-keyboard"
    public nonisolated static let inputCaptureVHIDDriverNotActivatedReason =
        "karabiner-vhid-driver-not-activated"

    // MARK: - Short-lived health cache

    private struct HealthCacheEntry {
        let result: Bool
        let timestamp: Date
        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    private struct RuntimeCacheEntry {
        let snapshot: KanataServiceRuntimeSnapshot
        let timestamp: Date
        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    private struct RuntimeCacheState {
        var entry: RuntimeCacheEntry?
        var inFlight: Task<KanataServiceRuntimeSnapshot, Never>?
    }

    private struct ServiceStatusCacheEntry {
        let status: LaunchDaemonStatus
        let timestamp: Date
        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    private nonisolated static let healthCacheTTL: TimeInterval = 2.0

    #if DEBUG
        /// Test-only override for `isServiceHealthy(serviceID:)`, keyed by serviceID.
        /// `ServiceHealthChecker.shared` is a process-wide singleton, so its real health
        /// check (and the short-lived cache above) would otherwise reflect whatever the
        /// test machine's actual launchd state happens to be — normally "not running",
        /// since the real VHID daemon isn't installed in CI/dev environments. Tests that
        /// need to simulate a healthy service set this instead of relying on real system
        /// state. Reset in `TestSingletonReset.resetAll()`.
        nonisolated(unsafe) static var testForcedServiceHealth: [String: Bool]?
    #endif

    private let healthCache = OSAllocatedUnfairLock(initialState: [String: HealthCacheEntry]())
    private let runtimeCache = OSAllocatedUnfairLock(initialState: RuntimeCacheState())
    private let serviceStatusCache = OSAllocatedUnfairLock(initialState: ServiceStatusCacheEntry?.none)

    /// Clear cached health results. Useful in tests or after service state changes.
    public nonisolated func invalidateHealthCache() {
        healthCache.withLock { $0.removeAll() }
        runtimeCache.withLock {
            $0.entry = nil
            $0.inFlight = nil
        }
        serviceStatusCache.withLock { $0 = nil }
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
        /// Non-nil when stderr shows a kanata config parse error (e.g., duplicate alias, syntax error).
        /// Contains the user-facing error message extracted from kanata's output.
        public let configParseError: String?

        public init(
            permissionRejected: Bool,
            inputCapture: KanataInputCaptureStatus,
            configParseError: String? = nil
        ) {
            self.permissionRejected = permissionRejected
            self.inputCapture = inputCapture
            self.configParseError = configParseError
        }

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
        public nonisolated(unsafe) static var vhidDriverExtensionEnabledOverride:
            (() async -> Bool)?
    #endif

    // MARK: - Service Identifiers

    /// Service identifier for the main Kanata keyboard remapping daemon
    public static let kanataServiceID = "com.keypath.kanata"

    /// Service identifier for the Karabiner Virtual HID Device daemon
    public static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"

    /// Service identifier for the Karabiner Virtual HID Device manager
    public static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    private static let karabinerDriverExtensionBundleID =
        "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"

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
        #if DEBUG
            if let forced = Self.testForcedServiceHealth?[serviceID] {
                return forced
            }
        #endif

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

        if serviceID == Self.vhidDaemonServiceID {
            let driverEnabled = await isVHIDDriverExtensionEnabled()
            guard driverEnabled else {
                AppLogger.shared.log(
                    "🔍 [ServiceHealthChecker] VHID daemon has launchd state but DriverKit extension is not [activated enabled]"
                )
                return false
            }
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
        if let cached = serviceStatusCache.withLock({ $0 }),
           cached.isValid(ttl: Self.healthCacheTTL)
        {
            AppLogger.shared.log("🔍 [ServiceHealthChecker] getServiceStatus() CACHE HIT")
            return cached.status
        }

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
        async let vhidDaemonLoaded = isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
        async let vhidManagerLoaded = isServiceLoaded(serviceID: Self.vhidManagerServiceID)
        async let vhidDaemonHealthy = isServiceHealthy(serviceID: Self.vhidDaemonServiceID)
        async let vhidManagerHealthy = isServiceHealthy(serviceID: Self.vhidManagerServiceID)

        let status = await LaunchDaemonStatus(
            kanataServiceLoaded: kanataLoaded,
            vhidDaemonServiceLoaded: vhidDaemonLoaded,
            vhidManagerServiceLoaded: vhidManagerLoaded,
            kanataServiceHealthy: kanataHealthy,
            vhidDaemonServiceHealthy: vhidDaemonHealthy,
            vhidManagerServiceHealthy: vhidManagerHealthy
        )
        serviceStatusCache.withLock {
            $0 = ServiceStatusCacheEntry(status: status, timestamp: Date())
        }
        return status
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
        tcpPort: Int = KeyPathConstants.Networking.defaultTCPPort,
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

        // 2) TCP readiness through the shared system-state provider.
        let tcpOK = await probeConfiguredTCPPort(defaultPort: tcpPort, timeoutMs: timeoutMs)

        return KanataHealthSnapshot(
            isRunning: isRunning,
            isResponding: tcpOK
        )
    }

    public nonisolated func checkKanataServiceRuntimeSnapshot(
        tcpPort: Int = KeyPathConstants.Networking.defaultTCPPort,
        timeoutMs: Int = 300
    ) async -> KanataServiceRuntimeSnapshot {
        #if DEBUG
            if let override = Self.runtimeSnapshotOverride {
                return await override()
            }
        #endif

        if tcpPort == KeyPathConstants.Networking.defaultTCPPort, timeoutMs == 300,
           ProcessInfo.processInfo.environment["KEYPATH_TCP_PORT"] == nil
        {
            if let cached = runtimeCache.withLock({ $0.entry }),
               cached.isValid(ttl: Self.healthCacheTTL)
            {
                AppLogger.shared.log("🔍 [ServiceHealthChecker] Kanata runtime snapshot CACHE HIT")
                return cached.snapshot
            }

            if let inFlight = runtimeCache.withLock({ $0.inFlight }) {
                AppLogger.shared.log("🔍 [ServiceHealthChecker] Kanata runtime snapshot IN-FLIGHT HIT")
                return await inFlight.value
            }

            let task = Task<KanataServiceRuntimeSnapshot, Never> {
                await self.checkKanataServiceRuntimeSnapshotUncached(
                    tcpPort: tcpPort,
                    timeoutMs: timeoutMs
                )
            }
            runtimeCache.withLock { $0.inFlight = task }
            let snapshot = await task.value
            runtimeCache.withLock {
                $0.entry = RuntimeCacheEntry(snapshot: snapshot, timestamp: Date())
                $0.inFlight = nil
            }
            return snapshot
        }

        return await checkKanataServiceRuntimeSnapshotUncached(tcpPort: tcpPort, timeoutMs: timeoutMs)
    }

    private nonisolated func checkKanataServiceRuntimeSnapshotUncached(
        tcpPort: Int,
        timeoutMs: Int
    ) async -> KanataServiceRuntimeSnapshot {
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
        tcpPort: Int = KeyPathConstants.Networking.defaultTCPPort,
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
        let driverEnabled = await isVHIDDriverExtensionEnabled()
        let stderrFallback = driverEnabled
            ? stderrDiagnosis.inputCapture
            : KanataInputCaptureStatus(
                isReady: false,
                issue: Self.inputCaptureVHIDDriverNotActivatedReason
            )
        let inputCapture = Self.resolveInputCaptureStatus(stderrFallback: stderrFallback)
        let tcpOK = await probeConfiguredTCPPort(defaultPort: tcpPort, timeoutMs: timeoutMs)

        return KanataServiceRuntimeSnapshot(
            managementState: managementState,
            isRunning: runningState.isRunning,
            isResponding: tcpOK,
            inputCaptureReady: inputCapture.isReady,
            inputCaptureIssue: inputCapture.issue,
            launchctlExitCode: runningState.exitCode,
            staleEnabledRegistration: staleEnabledRegistration,
            recentlyRestarted: Self.wasRecentlyRestarted(
                Self.kanataServiceID,
                within: Self.kanataRestartGraceWindow
            )
        )
    }

    public nonisolated func isVHIDDriverExtensionEnabled() async -> Bool {
        #if DEBUG
            if let override = Self.vhidDriverExtensionEnabledOverride {
                return await override()
            }
        #endif

        if TestEnvironment.shouldSkipAdminOperations {
            return true
        }

        do {
            let result = try await subprocessRunner.run(
                "/usr/bin/systemextensionsctl",
                args: ["list"],
                timeout: 5
            )
            let output = [result.stdout, result.stderr].joined(separator: "\n")
            let enabled = Self.systemExtensionsOutputShowsVHIDDriverEnabled(output)
            if !enabled {
                AppLogger.shared.log("⚠️ [ServiceHealthChecker] VHID DriverKit extension is not enabled:\n\(output)")
            }
            return enabled
        } catch {
            AppLogger.shared.log("❌ [ServiceHealthChecker] Unable to inspect VHID DriverKit extension: \(error)")
            return false
        }
    }

    public nonisolated static func systemExtensionsOutputShowsVHIDDriverEnabled(_ output: String) -> Bool {
        output.components(separatedBy: .newlines).contains { line in
            line.contains(karabinerDriverExtensionBundleID)
                && line.contains("[activated enabled]")
        }
    }

    private nonisolated func evaluateKanataLaunchctlRunningState(
        managementState _: WizardServiceManagementState,
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

    /// Resolve the input-capture status, layering kanata's authoritative
    /// `InputGrab` signal (#630) on top of the stderr log-pattern detector
    /// (#632).
    ///
    /// The signal is **strictly additive**: only an authoritative grab
    /// *failure* (`active:false`) overrides the stderr fallback. We deliberately
    /// do NOT let an authoritative `active:true` suppress a failure the stderr
    /// detector found — the grab bit is coarser than stderr (kanata can seize an
    /// external keyboard while failing to open the built-in one), and a cached
    /// `active:true` could outlive a silent grab loss. So this can only make
    /// status MORE truthful (catch a VNC-masked failure stderr missed), never
    /// less. A recovery transition (`active:true` after a prior `active:false`)
    /// still clears the failure by falling back to the now-clean stderr.
    ///
    /// `KanataGrabStatusStore` is recorded by the TCP listener and reset when
    /// the connection drops, so a non-nil failure is always ground truth from
    /// the current live session. When absent (old kanata, no grab-state
    /// transition since connect — kanata does not replay on connect, or no live
    /// connection) we use the stderr detector. Belt-and-suspenders.
    public nonisolated static func resolveInputCaptureStatus(
        stderrFallback: KanataInputCaptureStatus
    ) -> KanataInputCaptureStatus {
        guard let grab = KanataGrabStatusStore.shared.latest, !grab.active else {
            return stderrFallback
        }
        return KanataInputCaptureStatus(
            isReady: false,
            issue: grab.reason ?? Self.inputCaptureGrabFailureReason
        )
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

        guard let fullLog = readRecentKanataStderrLog(), !fullLog.isEmpty else {
            return .clear
        }

        // Only examine errors from the most recent kanata launch.
        // The stderr log accumulates across restarts; stale errors from previous
        // runs (before permissions were granted) cause false positives.
        let logChunk: String = if let lastLaunchRange = fullLog.range(of: "[kanata-launcher] Launching Kanata", options: .backwards) {
            String(fullLog[lastLaunchRange.lowerBound...])
        } else {
            fullLog
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
                    issue: Self.inputCaptureBuiltInKeyboardReason
                )
                break
            }
        }

        // Check for kanata aborting/panicking during Karabiner virtual-HID / input
        // initialization. kanata prints "aborted while talking to the Karabiner virtual
        // HID daemon" (often after a Rust panic, e.g. a CString NulError), followed by a
        // numbered causes list that includes "Another process is already grabbing your
        // keyboard exclusively". When this happens kanata is up (process + TCP), but it
        // never grabs the keyboard — it's crash-looping or running degraded, with NO
        // remapping. This was previously invisible to the health check (#624), so status
        // read green while the core feature was dead.
        if inputCaptureIssue.isReady, !permissionRejected, Self.detectsInputGrabFailure(in: logChunk) {
            inputCaptureIssue = KanataInputCaptureStatus(
                isReady: false,
                issue: Self.inputCaptureGrabFailureReason
            )
        }

        if inputCaptureIssue.isReady, !permissionRejected, Self.detectsVHIDDriverNotActivated(in: logChunk) {
            inputCaptureIssue = KanataInputCaptureStatus(
                isReady: false,
                issue: Self.inputCaptureVHIDDriverNotActivatedReason
            )
        }

        // Check for configuration parse errors (e.g., duplicate aliases, syntax errors).
        // These cause kanata to exit immediately and crash-loop via launchd.
        let configParseError = Self.extractConfigParseError(from: logChunk)

        return KanataDaemonDiagnosis(
            permissionRejected: permissionRejected,
            inputCapture: inputCaptureIssue,
            configParseError: configParseError
        )
    }

    /// Detect kanata aborting/panicking during Karabiner virtual-HID / input
    /// initialization — meaning it is up (process + TCP) but never grabbed the
    /// keyboard, so no remapping occurs. Matches kanata's abort epilogue and the
    /// underlying panic. Pure function over a stderr chunk so it can be unit-tested.
    static func detectsInputGrabFailure(in logChunk: String) -> Bool {
        let lower = logChunk.lowercased()
        return lower.contains("aborted while talking to the karabiner virtual hid daemon")
            || lower.contains("grabbing your keyboard exclusively")
            || (lower.contains("panicked at") && lower.contains("karabiner-driverkit"))
    }

    static func detectsVHIDDriverNotActivated(in logChunk: String) -> Bool {
        logChunk.lowercased().contains("virtualhiddevice driver is not activated")
    }

    /// Extract a user-facing config parse error from kanata stderr output.
    /// Looks for "help:" lines (most specific), falls back to "Error in configuration" / "failed to parse".
    static func extractConfigParseError(from logChunk: String) -> String? {
        let hasParseFailure = logChunk.contains("failed to parse file")
            || logChunk.contains("Error in configuration")
            || logChunk.contains("Host bridge config validation failed")
        guard hasParseFailure else { return nil }

        // Extract the "help:" line — kanata puts the most actionable info there
        // e.g., "help: Duplicate alias: beh_base_;"
        let lines = logChunk.components(separatedBy: .newlines)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("help:") {
                let detail = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !detail.isEmpty {
                    return detail
                }
            }
        }

        // Fallback: use the [ERROR] line
        for line in lines.reversed() {
            if line.contains("[ERROR]") {
                if let range = line.range(of: "[ERROR]") {
                    let raw = String(line[range.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    let msg = raw.replacingOccurrences(
                        of: "\u{1B}\\[[0-9;]*[A-Za-z]",
                        with: "",
                        options: .regularExpression
                    ).trimmingCharacters(in: .whitespaces)
                    if !msg.isEmpty { return msg }
                }
            }
        }

        return "Configuration has errors that prevent Kanata from starting"
    }

    // MARK: - Configuration Checks

    /// Check if Kanata service plist file exists (but may not be loaded).
    ///
    /// - Returns: `true` if the plist file exists
    public func isKanataPlistInstalled() -> Bool {
        let plistPath = getKanataPlistPath()
        return Foundation.FileManager().fileExists(atPath: plistPath)
    }

    /// Verifies that the installed VHID LaunchDaemon plist points to the DriverKit daemon path
    /// and carries the required ProcessType=Interactive key.
    ///
    /// ProcessType=Interactive keeps the daemon from being starved under CPU
    /// load (MAL-57 stuck-key autorepeat). A plist without it predates the fix
    /// and should be treated as misconfigured so repair rewrites it.
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
        return Self.vhidDaemonPlistContentIsValid(dict)
    }

    /// Whether an installed VHID daemon plist predates the MAL-57 fix and needs rewriting.
    ///
    /// Presence-gated: a missing plist returns `false` — that situation is
    /// "services not installed" and is already surfaced via service health.
    /// A plist that exists but has stale content (wrong program path or
    /// missing ProcessType=Interactive) counts as misconfigured, so existing
    /// installs migrate via a wizard repair. A present-but-unparseable plist
    /// also counts: repair rewrites it either way.
    ///
    /// - Returns: `true` if the plist exists but is misconfigured
    public func isVHIDDaemonPlistPresentButMisconfigured() -> Bool {
        let plistPath = getPlistPath(for: Self.vhidDaemonServiceID)
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            return Foundation.FileManager().fileExists(atPath: plistPath)
        }
        return !Self.vhidDaemonPlistContentIsValid(dict)
    }

    /// Shared content check for the VHID daemon plist: DriverKit daemon path
    /// in ProgramArguments plus the MAL-57 ProcessType=Interactive key.
    /// Logs only when the content is invalid — this runs on every validation
    /// cycle via SystemValidator, not just during install/repair.
    private static func vhidDaemonPlistContentIsValid(_ dict: [String: Any]) -> Bool {
        guard let args = dict["ProgramArguments"] as? [String], let first = args.first else {
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] VHID plist ProgramArguments missing or malformed"
            )
            return false
        }
        let pathOK = first == PlistGenerator.vhidDaemonPath
        let processTypeOK = (dict["ProcessType"] as? String) == "Interactive"
        if !pathOK || !processTypeOK {
            AppLogger.shared.log(
                "🔍 [ServiceHealthChecker] VHID plist ProgramArguments[0]=\(first) | pathOK=\(pathOK) | processTypeOK=\(processTypeOK)"
            )
        }
        return pathOK && processTypeOK
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

    private nonisolated func probeConfiguredTCPPort(defaultPort: Int, timeoutMs: Int) async -> Bool {
        let effectivePort = ProcessInfo.processInfo.environment["KEYPATH_TCP_PORT"]
            .flatMap(Int.init) ?? defaultPort
        return await SystemStateProvider.shared.isTCPPortResponding(port: effectivePort, timeoutMs: timeoutMs)
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
