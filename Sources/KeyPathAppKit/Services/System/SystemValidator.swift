import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import os.lock

extension RuntimeIdentity {
    static func expectedKeyPathKanata(buildVersion: String = BuildInfo.current().build) -> RuntimeIdentity {
        RuntimeIdentity(
            programIdentifier: KanataRuntimeHost.launcherBundleRelativePath,
            parentBundleIdentifier: KeyPathConstants.Bundle.bundleID,
            parentBundleVersion: buildVersion
        )
    }
}

/// Stateless system validation service for the session runtime.
///
/// Key design principles:
/// - PULL-BASED: UI explicitly calls checkSystem() when it wants state
/// - NO SIDE EFFECTS: Only inspects system, doesn't change anything
/// - BOUNDED: Every capture finishes within `canonicalCaptureTimeout`
@MainActor
public class SystemValidator {
    /// Per-instance validation task - prevents concurrent validations for this instance
    private var inProgressValidation: Task<SystemSnapshot, Never>?
    private var latestSnapshot: SystemSnapshot?
    private static let canonicalSnapshotCacheTTL: TimeInterval = 1.5
    static let canonicalCaptureTimeout: TimeInterval = 12

    // MARK: - Dependencies

    private let systemStateProvider: SystemStateProvider
    private weak var kanataManager: RuntimeCoordinator?

    init(
        systemStateProvider: SystemStateProvider = .shared,
        kanataManager: RuntimeCoordinator? = nil
    ) {
        self.systemStateProvider = systemStateProvider
        self.kanataManager = kanataManager
    }

    // MARK: - Main Validation Method

    /// Check complete system state
    /// This is the ONLY public method - returns fresh state every time
    ///
    /// If validation is already in progress, this will wait for it to complete
    /// rather than starting a concurrent validation. This prevents validation spam
    /// when multiple UI components request validation simultaneously.
    ///
    /// - Parameter progressCallback: Optional callback that receives progress updates (0.0 to 1.0)
    func checkSystem(progressCallback: @escaping @Sendable (Double) -> Void = { _ in }) async
        -> SystemSnapshot
    {
        // Fast path for tests - return stub immediately without any system calls
        // This dramatically speeds up tests that don't need real system state
        // Use KEYPATH_FORCE_REAL_VALIDATION=1 to override in specific tests
        if TestEnvironment.isRunningTests,
           ProcessInfo.processInfo.environment["KEYPATH_FORCE_REAL_VALIDATION"] != "1"
        {
            AppLogger.shared.log("🧪 [SystemValidator] Test mode - returning stub snapshot")
            progressCallback(1.0)
            let snapshot = Self.makeTestSnapshot()
            cacheIfComplete(snapshot)
            return snapshot
        }

        // If validation is already in progress, wait for it
        if let inProgress = inProgressValidation {
            AppLogger.shared.log(
                "🔍 [SystemValidator] Validation already in progress - waiting for result"
            )
            let snapshot = await inProgress.value
            cacheIfComplete(snapshot)
            return snapshot
        }

        // Start new validation
        let validationTask = Task<SystemSnapshot, Never> { @MainActor in
            await Self.boundedCapture(timeout: Self.canonicalCaptureTimeout) {
                await self.performValidation(progressCallback: progressCallback)
            }
        }

        inProgressValidation = validationTask
        defer { inProgressValidation = nil }

        let snapshot = await validationTask.value
        cacheIfComplete(snapshot)
        return snapshot
    }

    static func boundedCapture(
        timeout: TimeInterval,
        operation: @MainActor @Sendable @escaping () async -> SystemSnapshot
    ) async -> SystemSnapshot {
        let completionState = SystemCaptureCompletionState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completionState.setContinuation(continuation)

                let operationTask = Task { @MainActor in
                    let snapshot = await operation()
                    _ = completionState.complete(with: snapshot)
                }
                completionState.setOperationTask(operationTask)

                let timeoutTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                    } catch {
                        return
                    }
                    let didTimeOut = completionState.complete(with: .unavailable(
                        captureStatus: .timedOut,
                        source: "system-validator-timeout"
                    ))
                    if didTimeOut {
                        let message = "⏱️ [SystemValidator] Canonical capture timed out after \(String(format: "%.2f", timeout))s"
                        if TestEnvironment.isRunningTests {
                            AppLogger.shared.info(message)
                        } else {
                            AppLogger.shared.warn(message)
                        }
                    }
                }
                completionState.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            _ = completionState.complete(with: .unavailable(
                captureStatus: .cancelled,
                source: "system-validator-cancelled"
            ))
        }
    }

    func checkSystem(
        freshness: WizardSystemSnapshotFreshness,
        progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> SystemSnapshot {
        if freshness == .cached,
           let latestSnapshot,
           latestSnapshot.captureStatus.isComplete,
           Date().timeIntervalSince(latestSnapshot.timestamp) <= Self.canonicalSnapshotCacheTTL
        {
            AppLogger.shared.log("🔍 [SystemValidator] Reusing recent canonical snapshot")
            progressCallback(1.0)
            return latestSnapshot
        }

        if freshness == .fresh {
            invalidateCaches()
        }

        return await checkSystem(progressCallback: progressCallback)
    }

    public func invalidateCaches() {
        latestSnapshot = nil
        ServiceHealthChecker.shared.invalidateHealthCache()
    }

    private func cacheIfComplete(_ snapshot: SystemSnapshot) {
        guard snapshot.captureStatus.isComplete else { return }
        latestSnapshot = snapshot
    }

    /// Perform the actual validation work
    /// This is called by checkSystem() and should not be called directly
    private func performValidation(progressCallback: @escaping @Sendable (Double) -> Void = { _ in })
        async -> SystemSnapshot
    {
        if Task.isCancelled {
            return .unavailable(captureStatus: .cancelled, source: "cancelled")
        }
        return await captureSessionSnapshot(progressCallback: progressCallback)
    }

    private func captureSessionSnapshot(progressCallback: @escaping @Sendable (Double) -> Void) async -> SystemSnapshot {
        let permissions = await systemStateProvider.currentPermissionSnapshot()
        let report = kanataManager?.serviceLifecycleCoordinator.currentSessionReport()
        let running = report?.state == .running && report?.tapActive == true
        let responding = running ? await systemStateProvider.isTCPPortResponding(port: 37001, timeoutMs: 300) : false
        let host = KanataRuntimeHost.current()
        let payload = FileManager.default.fileExists(atPath: host.bridgeLibraryPath)
            && FileManager.default.fileExists(atPath: Bundle.main.executablePath ?? "")
        progressCallback(1)
        return SystemSnapshot(
            permissions: permissions,
            components: ComponentStatus(
                kanataBinaryInstalled: payload, requiredRuntimePayloadPresent: payload,
                karabinerDriverInstalled: false, karabinerDaemonRunning: false,
                vhidDeviceInstalled: false, vhidDeviceHealthy: false,
                vhidServicesHealthy: false, vhidVersionMismatch: false
            ),
            conflicts: .empty,
            health: HealthStatus(
                backend: .session,
                kanataProcessRunning: running, kanataTCPResponding: responding,
                kanataTCPConfigured: true, kanataRunning: running && responding,
                karabinerDaemonRunning: false, vhidHealthy: false,
                kanataInputCaptureReady: running,
                activeRuntimePathTitle: "Driverless session runtime",
                activeRuntimePathDetail: "Current user · KeyPath app identity · session event tap"
            ),
            compatibility: SystemCompatibilityStatus(
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString, driverCompatible: false
            ),
            timestamp: Date()
        )
    }

    // MARK: - Test Support

    /// Create a minimal snapshot for test mode - returns immediately without system calls
    /// This provides realistic-looking stub data for tests that don't need real system state
    private static func makeTestSnapshot() -> SystemSnapshot {
        let now = Date()
        let testPermissions = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test-stub",
            confidence: .high,
            timestamp: now
        )
        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot(
                keyPath: testPermissions, kanata: testPermissions, timestamp: now
            ),
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                requiredRuntimePayloadPresent: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(
                kanataTCPConfigured: true,
                kanataRunning: true,
                karabinerDaemonRunning: true,
                vhidHealthy: true
            ),
            compatibility: SystemCompatibilityStatus(macOSVersion: "test", driverCompatible: true),
            timestamp: now
        )
    }
}

private final class SystemCaptureCompletionState: @unchecked Sendable {
    private struct State {
        var result: SystemSnapshot?
        var continuation: CheckedContinuation<SystemSnapshot, Never>?
        var operationTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setContinuation(_ continuation: CheckedContinuation<SystemSnapshot, Never>) {
        let completedResult = state.withLock { state -> SystemSnapshot? in
            if let result = state.result {
                return result
            }
            state.continuation = continuation
            return nil
        }
        if let completedResult {
            continuation.resume(returning: completedResult)
        }
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        let alreadyCompleted = state.withLock { state -> Bool in
            state.operationTask = task
            return state.result != nil
        }
        if alreadyCompleted {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        let alreadyCompleted = state.withLock { state -> Bool in
            state.timeoutTask = task
            return state.result != nil
        }
        if alreadyCompleted {
            task.cancel()
        }
    }

    func complete(with result: SystemSnapshot) -> Bool {
        let completion = state.withLock { state -> (
            CheckedContinuation<SystemSnapshot, Never>?,
            Task<Void, Never>?,
            Task<Void, Never>?
        )? in
            guard state.result == nil else { return nil }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return (continuation, state.operationTask, state.timeoutTask)
        }
        guard let completion else { return false }
        completion.1?.cancel()
        completion.2?.cancel()
        completion.0?.resume(returning: result)
        return true
    }
}

/// Sendable is already required of this type: the wizard protocol it conforms to
/// in WizardProtocolConformances.swift inherits Sendable, so the conformance has
/// been in force all along. Swift 6 requires it to be declared alongside the
/// class rather than in the conformance file, so state it here. This records the
/// existing guarantee where the compiler wants it; it is not a new claim about
/// this type's thread safety.
extension SystemValidator: @unchecked Sendable {}
