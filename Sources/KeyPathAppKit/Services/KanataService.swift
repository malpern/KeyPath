import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

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

    // MARK: - Dependencies
    
    public let daemonManager: KanataDaemonManager
    public let processLifecycle: ProcessLifecycleManager
    public let healthMonitor: ServiceHealthMonitor

    // MARK: - State
    
    public enum ServiceState: Equatable, Sendable {
        case running(pid: Int)
        case stopped
        case failed(reason: String)
        case maintenance // Installing/Repairing
        case unknown
        
        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }
    
    @Published public private(set) var state: ServiceState = .unknown

    // MARK: - Initialization
    
    init(
        daemonManager: KanataDaemonManager = .shared,
        processLifecycle: ProcessLifecycleManager = ProcessLifecycleManager()
    ) {
        self.daemonManager = daemonManager
        self.processLifecycle = processLifecycle
        self.healthMonitor = ServiceHealthMonitor(processLifecycle: processLifecycle)
        
        // Initial state check
        Task { await refreshStatus() }
    }
    
    // MARK: - Public API
    
    /// Start the service via SMAppService
    public func start() async throws {
        AppLogger.shared.log("🚀 [KanataService] Start requested")
        
        // 1. Registration check
        if !KanataDaemonManager.isRegisteredViaSMAppService() {
            AppLogger.shared.log("🔧 [KanataService] Service not registered, registering...")
            try await daemonManager.register()
        }
        
        // 2. Cooldown check
        let cooldown = await healthMonitor.canRestartService()
        guard cooldown.canRestart else {
            throw KeyPathError.process(.restartCooldownActive(seconds: cooldown.remainingCooldown))
        }
        
        // 3. Register start attempt
        await healthMonitor.recordStartAttempt(timestamp: Date())
        
        // 4. Check if already running
        let conflicts = await processLifecycle.detectConflicts()
        if conflicts.managedProcesses.count > 0 {
            AppLogger.shared.info("✅ [KanataService] Service already running")
            await refreshStatus()
            return
        }
        
        // 5. We rely on macOS LaunchDaemon to start the process after registration/enable
        // SMAppService.register() (called above) sets the status to Enabled, which launchd observes.
        
        // Wait briefly for launchd to spin it up
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        await refreshStatus()
        
        if case .running = state {
            await healthMonitor.recordStartSuccess()
        } else {
            await healthMonitor.recordStartFailure()
            throw KeyPathError.process(.startFailed)
        }
    }
    
    /// Stop the service
    public func stop() async throws {
        AppLogger.shared.log("🛑 [KanataService] Stop requested")
        
        // Unregistering via SMAppService stops the daemon
        try await daemonManager.unregister()
        
        // Verify cleanup
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        await processLifecycle.unregisterProcess()
        await refreshStatus()
    }
    
    /// Restart the service
    public func restart() async throws {
        AppLogger.shared.log("cycles [KanataService] Restart requested")
        try await stop()
        try? await Task.sleep(nanoseconds: 500_000_000)
        try await start()
    }
    
    /// Refresh and return the current status
    @discardableResult
    public func refreshStatus() async -> ServiceState {
        // 1. Check SMAppService status
        let smStatus = daemonManager.getStatus()
        
        // 2. Check Process status
        let conflicts = await processLifecycle.detectConflicts()
        let isRunning = !conflicts.managedProcesses.isEmpty
        let pid = conflicts.managedProcesses.first?.pid
        
        let newState: ServiceState
        
        switch (smStatus, isRunning) {
        case (_, true):
            newState = .running(pid: Int(pid ?? 0))
        case (.enabled, false):
            // Enabled but not running - could be crashing or just starting
            newState = .failed(reason: "Service enabled but process not running")
        case (.requiresApproval, _):
            newState = .failed(reason: "Requires Background Item approval")
        default:
            newState = .stopped
        }
        
        if state != newState {
            AppLogger.shared.log("📊 [KanataService] State changed: \(state) -> \(newState)")
            state = newState
        }
        
        return newState
    }
}

