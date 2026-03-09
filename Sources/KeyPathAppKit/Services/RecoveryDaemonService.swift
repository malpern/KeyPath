import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import ServiceManagement

/// Errors related to recovery-daemon operations.
enum RecoveryDaemonServiceError: LocalizedError, Equatable {
    case stopFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .stopFailed(reason):
            "Failed to stop Kanata service: \(reason)"
        }
    }
}

/// Narrow utility for interacting with the internal recovery daemon.
///
/// The split runtime host is the real runtime path. This type only remains to:
/// - stop the internal recovery daemon when needed
/// - refresh its launchd-backed status on demand
/// - log recovery-daemon failures for diagnosis
@MainActor
final class RecoveryDaemonService {
    static let shared = RecoveryDaemonService()

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
            if case .running = self { return true }
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

    private nonisolated static func fetchSMStatus() -> SMAppService.Status {
        smServiceFactory(Constants.daemonPlistName).status
    }

    private func unregisterDaemon() async throws {
        let service = makeSMService()
        do {
            try await service.unregister()
        } catch {
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [RecoveryDaemonService] Ignoring unregister error in tests: \(error)")
                return
            }
            throw RecoveryDaemonServiceError.stopFailed(reason: error.localizedDescription)
        }
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

    /// Stop the service
    func stop() async throws {
        AppLogger.shared.log("🛑 [RecoveryDaemonService] Stop requested")

        try await unregisterDaemon()

        // Verify cleanup
        try? await Task.sleep(for: .milliseconds(200)) // 0.2s
        try? PIDFileManager.removePID()
        await pidCache.invalidateCache()
        let refreshedStatus = await refreshStatus()

        if case .running = refreshedStatus {
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [RecoveryDaemonService] Test environment stop fallback - marking service as stopped")
                lastObservedState = .stopped
            } else {
                // If still running, it might be a zombie or external process
                AppLogger.shared.warn("⚠️ [RecoveryDaemonService] Service still running after stop request")
                throw RecoveryDaemonServiceError.stopFailed(reason: "Process failed to terminate")
            }
        }

        if lastObservedState != .stopped {
            AppLogger.shared.log("ℹ️ [RecoveryDaemonService] Forcing state to stopped after successful stop")
            lastObservedState = .stopped
        }

        AppLogger.shared.info("✅ [RecoveryDaemonService] Stopped successfully")
    }

    /// Returns whether the internal recovery daemon is currently active.
    func isRecoveryDaemonRunning() async -> Bool {
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
        let smStatusTask = Task.detached(priority: .utility) {
            Self.fetchSMStatus()
        }
        let processTask = Task.detached(priority: .utility) {
            await Self.detectProcessState(pidCache: pidCache)
        }

        let smStatus = await smStatusTask.value
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
                    "⏳ [RecoveryDaemonService] SMAppService is enabled but process sample is missing (\(enabledWithoutProcessSampleCount)/\(enabledWithoutProcessFailureThreshold)); holding prior state"
                )

                if case let .running(previousPID) = lastObservedState {
                    return .running(pid: previousPID)
                }
                return .unknown
            }

            // Before declaring failure, probe the Kanata TCP server as a last resort.
            let tcpPort = PreferencesService.shared.tcpServerPort
            let tcpAlive = await Task.detached(priority: .utility) {
                TCPProbe.probe(port: tcpPort, timeoutMs: 300)
            }.value

            if tcpAlive {
                AppLogger.shared.log(
                    "🩹 [RecoveryDaemonService] TCP probe saved false failure — kanata responding on port \(tcpPort) despite PID miss"
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
        AppLogger.shared.log("📊 [RecoveryDaemonService] State changed: \(lastObservedState.description) -> \(newStatus.description)")
        let oldState = lastObservedState
        lastObservedState = newStatus

        // Log service failures for crash analysis only when a running service drops to failed.
        // This avoids noisy false positives from startup/probe states (e.g. unknown -> failed).
        if case let .failed(reason) = newStatus {
            if oldState.isRunning {
                logServiceFailure(from: oldState, reason: reason)
            } else {
                AppLogger.shared.debug(
                    "ℹ️ [RecoveryDaemonService] Skipping crash-log entry for non-running transition: \(oldState.description) -> failed(\(reason))"
                )
            }
        }

        // Note: Previously re-evaluated status on running→running(different PID) transitions.
        // Removed: the recursive publishStatus() call could cascade unboundedly when PIDs
        // differ across evaluations, monopolizing the MainActor under load.
    }

    /// Log service state failures to persistent crash log for later analysis
    private func logServiceFailure(from oldState: ServiceState, reason: String) {
        let crashLogDir = Foundation.FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KeyPath")
        let crashLogPath = crashLogDir.appendingPathComponent("crashes.log")

        // Ensure directory exists
        do {
            try Foundation.FileManager().createDirectory(at: crashLogDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.warn("⚠️ [RecoveryDaemonService] Failed to create crash log directory: \(error.localizedDescription)")
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
                AppLogger.shared.warn("⚠️ [RecoveryDaemonService] Failed to write crash log: \(error.localizedDescription)")
            }
        }

        AppLogger.shared.error(
            "💥 [CrashLog] Logged service failure: \(oldState.description) -> failed(\(reason))"
        )
    }

}
