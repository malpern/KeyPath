import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import ServiceManagement

/// Errors related to recovery-daemon operations.
enum KanataDaemonServiceError: LocalizedError, Equatable {
    case approvalRequired
    case startFailed(reason: String)
    case stopFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .approvalRequired:
            "Starting Kanata requires approval in System Settings."
        case let .startFailed(reason):
            "Failed to start Kanata service: \(reason)"
        case let .stopFailed(reason):
            "Failed to stop Kanata service: \(reason)"
        }
    }
}

/// Manages the Kanata LaunchDaemon lifecycle via SMAppService.
///
/// Responsibilities:
/// - Stop/unregister the daemon
/// - Poll launchd-backed status on demand
/// - Log service failures for diagnosis
@MainActor
final class KanataDaemonService {
    static let shared = KanataDaemonService()

    private enum Constants {
        static let daemonPlistName = "com.keypath.kanata.plist"
    }

    // Factory used to create SMAppService instances (test seam)
    #if DEBUG
        nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: SMAppService.daemon(plistName: plistName))
        }
    #else
        nonisolated(unsafe) static let smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: SMAppService.daemon(plistName: plistName))
        }
    #endif

    // Test seam for the last-resort TCP liveness probe. Without this, integration
    // tests that assert a "failed" status get contaminated by a real kanata daemon
    // answering on the default port (the CI runner is a dev Mac with kanata running).
    // Tests inject `{ _, _ in false }` so the probe is deterministic regardless of
    // whatever is listening on the machine. DEBUG-only — production always probes.
    #if DEBUG
        nonisolated(unsafe) static var tcpProbeOverride: ((Int, Int) -> Bool)?
        nonisolated(unsafe) static var processRunningOverride: (() async -> Bool)?
        nonisolated(unsafe) static var runningPostconditionOverride: (() async -> Bool)?
        nonisolated(unsafe) static var privilegedStopOverride: (() async throws -> Void)?
    #endif

    // MARK: - Internal Dependencies (Hidden from consumers)

    @ObservationIgnored private let pidCache = LaunchDaemonPIDCache()

    private struct ProcessSnapshot {
        let isRunning: Bool
        let pid: Int?
    }

    // MARK: - State

    enum ServiceState: Equatable, Sendable {
        case running(pid: Int)
        case stopped
        case failed(reason: String)
        case unknown

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }

        var description: String {
            switch self {
            case let .running(pid): "Running (PID \(pid))"
            case .stopped: "Stopped"
            case let .failed(reason): "Failed: \(reason)"
            case .unknown: "Unknown"
            }
        }
    }

    private var lastObservedState: ServiceState = .unknown
    /// Debounce transient "enabled but no PID" samples to avoid false failure reports.
    private var enabledWithoutProcessSampleCount = 0
    private let enabledWithoutProcessFailureThreshold = 3

    // MARK: - Initialization

    init() {}

    // MARK: - SMAppService helpers

    private func makeSMService() -> SMAppServiceProtocol {
        Self.smServiceFactory(Constants.daemonPlistName)
    }

    private func unregisterDaemon() async throws {
        let service = makeSMService()
        do {
            try await service.unregister()
            // Drop the centralized status cache so the next read re-fetches.
            await SystemStateProvider.shared.invalidateSMAppServiceStatus(plistName: Constants.daemonPlistName)
        } catch {
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [KanataDaemonService] Ignoring unregister error in tests: \(error)")
                return
            }
            throw KanataDaemonServiceError.stopFailed(reason: error.localizedDescription)
        }
    }

    private func registerDaemon() async throws {
        let service = makeSMService()
        do {
            try service.register()
            await SystemStateProvider.shared.invalidateSMAppServiceStatus(plistName: Constants.daemonPlistName)
        } catch {
            throw KanataDaemonServiceError.startFailed(reason: error.localizedDescription)
        }
    }

    private func currentRegistrationStatus() async -> SMAppService.Status {
        await SystemStateProvider.shared
            .freshSMAppServiceStatus(for: Constants.daemonPlistName)
    }

    private func processIsRunning() async -> Bool {
        #if DEBUG
            if let override = Self.processRunningOverride {
                return await override()
            }
        #endif

        await pidCache.invalidateCache()
        let processState = await detectProcessState()
        return processState.isRunning
    }

    private func waitForRunningPostcondition(
        maxAttempts: Int = 80,
        delayMilliseconds: Int = 250
    ) async -> Bool {
        #if DEBUG
            if let override = Self.runningPostconditionOverride {
                return await override()
            }
        #endif

        for attempt in 1 ... maxAttempts {
            if await processIsRunning() {
                let tcpPort = PreferencesService.shared.tcpServerPort
                let tcpAlive = await SystemStateProvider.shared
                    .isTCPPortResponding(port: tcpPort, timeoutMs: 300)
                if tcpAlive {
                    return true
                }
            }
            if attempt < maxAttempts {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
        }
        return false
    }

    private enum StoppedPostcondition: Equatable {
        case satisfied
        case registrationPresent
        case processRunning
    }

    private func waitForStoppedPostcondition(
        maxAttempts: Int = 10,
        delayMilliseconds: Int = 100
    ) async -> StoppedPostcondition {
        // Registration is correctness-critical but SMAppService.status is slow
        // synchronous IPC. Fetch it once per unregister phase, then poll only the
        // inexpensive launchd-backed process evidence while removal settles.
        let status = await currentRegistrationStatus()
        guard status == .notRegistered || status == .notFound else {
            return .registrationPresent
        }

        for attempt in 1 ... maxAttempts {
            if await !processIsRunning() {
                return .satisfied
            }
            if attempt < maxAttempts {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
        }
        return .processRunning
    }

    private func forceStopStaleDaemon() async throws {
        #if DEBUG
            if let override = Self.privilegedStopOverride {
                try await override()
                return
            }
        #endif

        try await PrivilegeBroker().stopKanataDaemonService()
    }

    private func detectProcessState() async -> ProcessSnapshot {
        if let daemonPID = await pidCache.getCachedPID() {
            return ProcessSnapshot(isRunning: true, pid: Int(daemonPID))
        }

        let ownership = PIDFileManager.checkOwnership()
        if ownership.owned, let pid = ownership.pid {
            return ProcessSnapshot(isRunning: true, pid: Int(pid))
        }

        return ProcessSnapshot(isRunning: false, pid: nil)
    }

    private nonisolated static func detectProcessState(
        pidCache: LaunchDaemonPIDCache
    ) async -> ProcessSnapshot {
        if let daemonPID = await pidCache.getCachedPID() {
            return ProcessSnapshot(isRunning: true, pid: Int(daemonPID))
        }

        let ownership = PIDFileManager.checkOwnership()
        if ownership.owned, let pid = ownership.pid {
            return ProcessSnapshot(isRunning: true, pid: Int(pid))
        }

        return ProcessSnapshot(isRunning: false, pid: nil)
    }

    // MARK: - Public API

    /// Start the service through its owning SMAppService registration.
    func start() async throws {
        AppLogger.shared.log("▶️ [KanataDaemonService] Start requested")

        let finalRegistrationStatus: SMAppService.Status
        switch await currentRegistrationStatus() {
        case .enabled:
            finalRegistrationStatus = .enabled
        case .requiresApproval:
            throw KanataDaemonServiceError.approvalRequired
        case .notRegistered, .notFound:
            try await registerDaemon()
            finalRegistrationStatus = await currentRegistrationStatus()
        @unknown default:
            throw KanataDaemonServiceError.startFailed(reason: "Unknown SMAppService registration state")
        }

        switch finalRegistrationStatus {
        case .enabled:
            break
        case .requiresApproval:
            throw KanataDaemonServiceError.approvalRequired
        case .notRegistered, .notFound:
            throw KanataDaemonServiceError.startFailed(reason: "Registration did not persist")
        @unknown default:
            throw KanataDaemonServiceError.startFailed(reason: "Unknown SMAppService registration state")
        }

        guard await waitForRunningPostcondition() else {
            throw KanataDaemonServiceError.startFailed(
                reason: "Service registered but did not reach process and TCP readiness"
            )
        }

        await pidCache.invalidateCache()
        lastObservedState = await refreshStatus()
        AppLogger.shared.info("✅ [KanataDaemonService] Started successfully")
    }

    /// Stop the service
    func stop() async throws {
        AppLogger.shared.log("🛑 [KanataDaemonService] Stop requested")

        try await unregisterDaemon()

        // SMAppService removes its launchd job asynchronously. Across an app
        // replacement, macOS can leave the prior bundle's registration alive
        // after the first unregister request. Verify the real postcondition,
        // retry the owning API once, then use the existing privileged bootout
        // path only if the stale job still survives.
        var stoppedPostcondition = await waitForStoppedPostcondition()
        if stoppedPostcondition == .registrationPresent {
            AppLogger.shared.warn(
                "⚠️ [KanataDaemonService] Job survived unregister; retrying SMAppService removal"
            )
            try? await unregisterDaemon()
            stoppedPostcondition = await waitForStoppedPostcondition()
        }

        if stoppedPostcondition != .satisfied {
            AppLogger.shared.warn(
                "⚠️ [KanataDaemonService] Stale job survived SMAppService retry; using privileged cleanup"
            )
            do {
                try await forceStopStaleDaemon()
            } catch {
                throw KanataDaemonServiceError.stopFailed(reason: error.localizedDescription)
            }

            // A bootout can stop the process, but only the owning API can remove
            // a still-enabled registration and prevent a later KeepAlive respawn.
            if stoppedPostcondition == .registrationPresent {
                try await unregisterDaemon()
            }
            stoppedPostcondition = await waitForStoppedPostcondition(maxAttempts: 20)
        }

        guard stoppedPostcondition == .satisfied else {
            throw KanataDaemonServiceError.stopFailed(
                reason: "Service remained registered or running after stale-job cleanup"
            )
        }

        try? PIDFileManager.removePID()
        await pidCache.invalidateCache()
        lastObservedState = .stopped

        AppLogger.shared.info("✅ [KanataDaemonService] Stopped successfully")
    }

    /// Restart by removing the SMAppService registration before registering it
    /// again. This is the supported way to stop a loaded KeepAlive job; disabling
    /// or signaling the launchd label alone does not suppress an existing job's
    /// KeepAlive respawn.
    func restart() async throws {
        AppLogger.shared.log("🔄 [KanataDaemonService] Restart requested")
        try await stop()
        try await start()
        AppLogger.shared.info("✅ [KanataDaemonService] Restart requested successfully")
    }

    /// Returns whether the internal recovery daemon is currently active.
    func isDaemonRunning() async -> Bool {
        let status = await refreshStatus()
        return status.isRunning
    }

    /// Best-effort stop for the internal recovery daemon.
    /// - Returns: `true` if the daemon was running and a stop was attempted, otherwise `false`.
    @discardableResult
    func stopIfRunning() async throws -> Bool {
        let status = await refreshStatus()
        guard status.isRunning else { return false }
        try await stop()
        return true
    }

    /// Force a status refresh (useful for UI pull-to-refresh)
    @discardableResult
    func refreshStatus() async -> ServiceState {
        let status = await evaluateStatus()
        publishStatus(status)
        return status
    }

    // MARK: - Status Composition

    private func evaluateStatus() async -> ServiceState {
        let pidCache = pidCache
        // Route the SMAppService.status read through SystemStateProvider.
        // This is the hot state-refresh path (overlay polling), so use the cached
        // accessor — it collapses a polling burst into a single background IPC.
        async let smStatusValue = SystemStateProvider.shared
            .cachedSMAppServiceStatus(for: Constants.daemonPlistName)
        let processTask = Task.detached(priority: .utility) {
            await Self.detectProcessState(pidCache: pidCache)
        }

        let smStatus = await smStatusValue
        let processState = await processTask.value

        switch smStatus {
        case .enabled:
            if processState.isRunning {
                enabledWithoutProcessSampleCount = 0
                return .running(pid: processState.pid ?? 0)
            }

            // Guard against transient process-detection misses (observed in the field):
            // require several consecutive misses before reporting a hard failure.
            enabledWithoutProcessSampleCount += 1
            if enabledWithoutProcessSampleCount < enabledWithoutProcessFailureThreshold {
                AppLogger.shared.debug(
                    "⏳ [KanataDaemonService] SMAppService is enabled but process sample is missing (\(enabledWithoutProcessSampleCount)/\(enabledWithoutProcessFailureThreshold)); holding prior state"
                )

                if case let .running(previousPID) = lastObservedState {
                    return .running(pid: previousPID)
                }
                return .unknown
            }

            // Before declaring failure, probe the Kanata TCP server as a last resort.
            let tcpPort = PreferencesService.shared.tcpServerPort
            let tcpAlive: Bool
            #if DEBUG
                if let override = Self.tcpProbeOverride {
                    tcpAlive = override(tcpPort, 300)
                } else {
                    tcpAlive = await SystemStateProvider.shared
                        .isTCPPortResponding(port: tcpPort, timeoutMs: 300)
                }
            #else
                tcpAlive = await SystemStateProvider.shared
                    .isTCPPortResponding(port: tcpPort, timeoutMs: 300)
            #endif

            if tcpAlive {
                AppLogger.shared.log(
                    "🩹 [KanataDaemonService] TCP probe saved false failure — kanata responding on port \(tcpPort) despite PID miss"
                )
                enabledWithoutProcessSampleCount = 0
                return .running(pid: 0)
            }

            return .failed(reason: "Service enabled but process not running")
        case .notRegistered, .notFound:
            enabledWithoutProcessSampleCount = 0
            return processState.isRunning ? .running(pid: processState.pid ?? 0) : .stopped
        case .requiresApproval:
            enabledWithoutProcessSampleCount = 0
            return .stopped
        @unknown default:
            enabledWithoutProcessSampleCount = 0
            return .unknown
        }
    }

    private func publishStatus(_ newStatus: ServiceState) {
        guard lastObservedState != newStatus else { return }
        AppLogger.shared.log("📊 [KanataDaemonService] State changed: \(lastObservedState.description) -> \(newStatus.description)")
        let oldState = lastObservedState
        lastObservedState = newStatus

        // Log service failures for crash analysis only when a running service drops to failed.
        // This avoids noisy false positives from startup/probe states (e.g. unknown -> failed).
        if case let .failed(reason) = newStatus {
            if oldState.isRunning {
                logServiceFailure(from: oldState, reason: reason)
            } else {
                AppLogger.shared.debug(
                    "ℹ️ [KanataDaemonService] Skipping crash-log entry for non-running transition: \(oldState.description) -> failed(\(reason))"
                )
            }
        }
    }

    /// Log service state failures to persistent crash log for later analysis
    /// (redirected to a temp sandbox during tests via AppPaths).
    private func logServiceFailure(from oldState: ServiceState, reason: String) {
        let crashLogDir = AppPaths.logsDirectory
        let crashLogPath = AppPaths.crashLogFile

        // Ensure directory exists
        do {
            try Foundation.FileManager().createDirectory(at: crashLogDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.warn("⚠️ [KanataDaemonService] Failed to create crash log directory: \(error.localizedDescription)")
        }

        // Format crash entry
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let entry = """
        [\(timestamp)] [SERVICE_FAILURE] Kanata service failed
        Previous state: \(oldState.description)
        Reason: \(reason)
        ---

        """

        // Append to log file
        if let data = entry.data(using: .utf8) {
            do {
                if Foundation.FileManager().fileExists(atPath: crashLogPath.path) {
                    let handle = try FileHandle(forWritingTo: crashLogPath)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: crashLogPath)
                }
            } catch {
                AppLogger.shared.warn("⚠️ [KanataDaemonService] Failed to write crash log: \(error.localizedDescription)")
            }
        }

        AppLogger.shared.error(
            "💥 [CrashLog] Logged service failure: \(oldState.description) -> failed(\(reason))"
        )
    }
}
