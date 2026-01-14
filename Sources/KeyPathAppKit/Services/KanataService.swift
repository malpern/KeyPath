import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import ServiceManagement

/// Errors related to Kanata service operations
public enum KanataServiceError: LocalizedError, Equatable {
    case serviceNotRegistered
    case requiresApproval
    case startFailed(reason: String)
    case stopFailed(reason: String)
    case restartCooldownActive(seconds: Double)
    case processConflict(pid: Int)

    public var errorDescription: String? {
        switch self {
        case .serviceNotRegistered:
            "Kanata service is not registered with the system."
        case .requiresApproval:
            "Background item approval required in System Settings."
        case let .startFailed(reason):
            "Failed to start Kanata service: \(reason)"
        case let .stopFailed(reason):
            "Failed to stop Kanata service: \(reason)"
        case let .restartCooldownActive(seconds):
            "Restart cooldown active. Please wait \(String(format: "%.1f", seconds)) seconds."
        case let .processConflict(pid):
            "Conflicting Kanata process detected (PID \(pid))."
        }
    }
}

/// Unified service manager for the Kanata daemon.
///
/// This manager consolidates the responsibilities of:
/// - `KanataDaemonManager` (SMAppService registration)
/// - `ProcessLifecycleManager` (PID tracking & conflict detection)
/// - `ServiceHealthMonitor` (Health checks & restart cooldowns)
///
/// It provides a single, high-level API for starting, stopping, and monitoring the service.
@MainActor
public final class KanataService: ObservableObject {
    public static let shared = KanataService()

    private enum Constants {
        static let daemonPlistName = "com.keypath.kanata.plist"
    }

    /// Factory used to create SMAppService instances (test seam)
    nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
        NativeSMAppService(wrapped: SMAppService.daemon(plistName: plistName))
    }

    // MARK: - Internal Dependencies (Hidden from consumers)

    private let healthMonitor: ServiceHealthMonitor
    private let pidCache = LaunchDaemonPIDCache()

    private struct ProcessSnapshot {
        let isRunning: Bool
        let pid: Int?
    }

    // MARK: - State

    public enum ServiceState: Equatable, Sendable {
        case running(pid: Int)
        case stopped
        case failed(reason: String)
        case maintenance // Installing/Repairing
        case requiresApproval // SMAppService specific state
        case unknown

        public var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        public var description: String {
            switch self {
            case let .running(pid): "Running (PID \(pid))"
            case .stopped: "Stopped"
            case let .failed(reason): "Failed: \(reason)"
            case .maintenance: "Maintenance Mode"
            case .requiresApproval: "Requires Approval"
            case .unknown: "Unknown"
            }
        }
    }

    @Published public private(set) var state: ServiceState = .unknown

    // Polling task for status updates
    private var statusTask: Task<Void, Never>?

    // MARK: - Initialization

    init(healthMonitor: ServiceHealthMonitor = ServiceHealthMonitor(processLifecycle: ProcessLifecycleManager())) {
        self.healthMonitor = healthMonitor

        // Skip polling and initial check in test environment to avoid TCP timeouts
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.log("🧪 [KanataService] Test environment - skipping status polling")
            return
        }

        // Initial status check
        Task { await refreshStatus() }

        // Setup observers
        setupObservers()
    }

    private func setupObservers() {
        // Observe SMAppService approval notifications
        NotificationCenter.default.addObserver(
            forName: .smAppServiceApprovalRequired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state = .requiresApproval
            }
        }

        // Start polling for status updates (every 2 seconds)
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                if let self {
                    await refreshStatus()
                } else {
                    break
                }
            }
        }
    }

    deinit {
        statusTask?.cancel()
    }

    // MARK: - SMAppService helpers

    private func makeSMService() -> SMAppServiceProtocol {
        Self.smServiceFactory(Constants.daemonPlistName)
    }

    private func currentDaemonStatus() -> SMAppService.Status {
        makeSMService().status
    }

    private nonisolated static func fetchSMStatus() -> SMAppService.Status {
        smServiceFactory(Constants.daemonPlistName).status
    }

    private func ensureDaemonRegistered() async throws {
        let service = makeSMService()
        switch service.status {
        case .enabled:
            // Check for stale registration: SMAppService says enabled but plist doesn't exist
            // This can happen if uninstall used launchctl/rm instead of SMAppService.unregister()
            let plistPath = "/Library/LaunchDaemons/\(Constants.daemonPlistName)"
            if !FileManager.default.fileExists(atPath: plistPath) {
                AppLogger.shared.log(
                    "⚠️ [KanataService] Stale SMAppService registration detected - " +
                        "status=enabled but plist missing. Clearing and re-registering..."
                )
                // Clear the stale registration, then re-register
                do {
                    try await service.unregister()
                } catch {
                    AppLogger.shared.log(
                        "⚠️ [KanataService] Failed to unregister stale service: \(error.localizedDescription)"
                    )
                    // Continue anyway - register() might still work
                }
                do {
                    try service.register()
                    AppLogger.shared.log("✅ [KanataService] Re-registered after clearing stale state")
                } catch {
                    throw KanataServiceError.startFailed(reason: error.localizedDescription)
                }
            }
            return
        case .requiresApproval:
            throw KanataServiceError.requiresApproval
        default:
            do {
                try service.register()
            } catch {
                throw KanataServiceError.startFailed(reason: error.localizedDescription)
            }
        }
    }

    private func unregisterDaemon() async throws {
        let service = makeSMService()
        do {
            try await service.unregister()
        } catch {
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [KanataService] Ignoring unregister error in tests: \(error)")
                return
            }
            throw KanataServiceError.stopFailed(reason: error.localizedDescription)
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

    /// Start the service
    public func start() async throws {
        AppLogger.shared.log("🚀 [KanataService] Start requested")

        // 1. Reset cached PID to avoid stale readings
        await pidCache.invalidateCache()

        // 2. Check current state
        await refreshStatus()
        if case .running = state {
            AppLogger.shared.info("✅ [KanataService] Already running, ignoring start request")
            return
        }

        // 3. Cooldown check
        let cooldown = await healthMonitor.canRestartService()
        guard cooldown.canRestart else {
            throw KanataServiceError.restartCooldownActive(seconds: cooldown.remainingCooldown)
        }

        // 4. Ensure daemon is properly registered (also handles stale registrations)
        AppLogger.shared.log("🔧 [KanataService] Ensuring service registration...")
        try await ensureDaemonRegistered()

        // 5. Record start attempt
        await healthMonitor.recordStartAttempt(timestamp: Date())

        // 6. Wait for launchd
        // Give it up to 1.5 seconds to appear, checking every 0.3s
        for _ in 0 ..< 5 {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            await refreshStatus()
            if case .running = state { break }
        }

        // 7. Verify success
        await refreshStatus()

        if case .running = state {
            await healthMonitor.recordStartSuccess()
            AppLogger.shared.info("✅ [KanataService] Started successfully")
            return
        }

        // In test environments, we don't spawn real processes. Treat registration success as running.
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [KanataService] Test environment start fallback - marking service as running")
            state = .running(pid: 0)
            await healthMonitor.recordStartSuccess()
            return
        }

        await healthMonitor.recordStartFailure()

        if case .requiresApproval = state {
            throw KanataServiceError.requiresApproval
        }

        throw KanataServiceError.startFailed(reason: "Process did not start after registration")
    }

    /// Stop the service
    public func stop() async throws {
        AppLogger.shared.log("🛑 [KanataService] Stop requested")

        try await unregisterDaemon()

        // Verify cleanup
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        try? PIDFileManager.removePID()
        await pidCache.invalidateCache()
        await refreshStatus()

        if case .running = state {
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [KanataService] Test environment stop fallback - marking service as stopped")
                state = .stopped
            } else {
                // If still running, it might be a zombie or external process
                AppLogger.shared.warn("⚠️ [KanataService] Service still running after stop request")
                throw KanataServiceError.stopFailed(reason: "Process failed to terminate")
            }
        }

        if state != .stopped {
            AppLogger.shared.log("ℹ️ [KanataService] Forcing state to stopped after successful stop")
            state = .stopped
        }

        AppLogger.shared.info("✅ [KanataService] Stopped successfully")
    }

    /// Restart the service
    public func restart() async throws {
        AppLogger.shared.log("cycles [KanataService] Restart requested")
        try await stop()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s wait
        try await start()
    }

    /// Force a status refresh (useful for UI pull-to-refresh)
    @discardableResult
    public func refreshStatus() async -> ServiceState {
        let status = await evaluateStatus()
        publishStatus(status)
        return status
    }

    /// Check if the service is completely installed and ready
    public var isInstalled: Bool {
        switch currentDaemonStatus() {
        case .notFound:
            false
        default:
            true
        }
    }

    /// Evaluate current health using the internal monitor and the latest process snapshot.
    func checkHealth(tcpPort: Int) async -> ServiceHealthStatus {
        let snapshot = await detectProcessState()
        let processStatus = ProcessHealthStatus(isRunning: snapshot.isRunning, pid: snapshot.pid)
        return await healthMonitor.checkServiceHealth(processStatus: processStatus, tcpPort: tcpPort)
    }

    /// Determine whether the service can be restarted based on the active cooldown.
    func canRestartService() async -> RestartCooldownState {
        await healthMonitor.canRestartService()
    }

    /// Record a manual start attempt – used by UI flows that orchestrate restarts.
    func recordStartAttempt(timestamp: Date) async {
        await healthMonitor.recordStartAttempt(timestamp: timestamp)
    }

    /// Record successful start completion.
    func recordStartSuccess() async {
        await healthMonitor.recordStartSuccess()
    }

    /// Record a failed start attempt.
    func recordStartFailure() async {
        await healthMonitor.recordStartFailure()
    }

    /// Record a VirtualHID connection failure; returns true when auto-recovery should trigger.
    func recordConnectionFailure() async -> Bool {
        await healthMonitor.recordConnectionFailure()
    }

    /// Record a VirtualHID connection success (resets cooldown/counters).
    func recordConnectionSuccess() async {
        await healthMonitor.recordConnectionSuccess()
    }

    // MARK: - Status Composition

    private func evaluateStatus() async -> ServiceState {
        let pidCache = self.pidCache
        let smStatusTask = Task.detached(priority: .utility) {
            Self.fetchSMStatus()
        }
        let processTask = Task.detached(priority: .utility) {
            await Self.detectProcessState(pidCache: pidCache)
        }

        let smStatus = await smStatusTask.value
        let processState = await processTask.value

        switch smStatus {
        case .requiresApproval:
            return .requiresApproval
        case .enabled:
            return processState.isRunning
                ? .running(pid: processState.pid ?? 0)
                : .failed(reason: "Service enabled but process not running")
        case .notRegistered, .notFound:
            return processState.isRunning ? .running(pid: processState.pid ?? 0) : .stopped
        @unknown default:
            return .unknown
        }
    }

    private func publishStatus(_ newStatus: ServiceState) {
        guard state != newStatus else { return }
        AppLogger.shared.log("📊 [KanataService] State changed: \(state.description) -> \(newStatus.description)")
        let oldState = state
        state = newStatus

        // Log service failures for crash analysis
        if case let .failed(reason) = newStatus {
            logServiceFailure(from: oldState, reason: reason)
        }

        // Track PID for crash loop detection
        if case let .running(pid) = newStatus {
            Task {
                let isCrashLoop = await healthMonitor.recordPIDObservation(pid)
                if isCrashLoop {
                    await handleCrashLoopDetected()
                }
            }
        }

        if oldState.isRunning, case .running = newStatus {
            Task {
                let status = await evaluateStatus()
                publishStatus(status)
            }
        }
    }

    /// Log service state failures to persistent crash log for later analysis
    private func logServiceFailure(from oldState: ServiceState, reason: String) {
        let crashLogDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KeyPath")
        let crashLogPath = crashLogDir.appendingPathComponent("crashes.log")

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: crashLogDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.warn("⚠️ [KanataService] Failed to create crash log directory: \(error.localizedDescription)")
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
                if FileManager.default.fileExists(atPath: crashLogPath.path) {
                    let handle = try FileHandle(forWritingTo: crashLogPath)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: crashLogPath)
                }
            } catch {
                AppLogger.shared.warn("⚠️ [KanataService] Failed to write crash log: \(error.localizedDescription)")
            }
        }

        AppLogger.shared.error(
            "💥 [CrashLog] Logged service failure: \(oldState.description) -> failed(\(reason))"
        )
    }

    /// Handle detected crash loop by stopping the service and notifying user
    private func handleCrashLoopDetected() async {
        AppLogger.shared.error("🚨 [KanataService] Crash loop detected - stopping service to protect keyboard")

        // Stop the service immediately
        do {
            try await unregisterDaemon()
            state = .failed(reason: "Crash loop detected - service stopped. Open Setup Wizard to diagnose.")
            AppLogger.shared.info("✅ [KanataService] Service stopped due to crash loop")

            // Post notification for UI to show alert
            NotificationCenter.default.post(
                name: .kanataCrashLoopDetected,
                object: nil,
                userInfo: ["reason": "Kanata was crash-looping and has been stopped to protect your keyboard."]
            )
        } catch {
            AppLogger.shared.error("❌ [KanataService] Failed to stop crash-looping service: \(error)")
        }
    }
}
