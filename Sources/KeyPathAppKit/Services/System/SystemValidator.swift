import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

/// Captures live session runtime evidence within a fixed deadline.
/// Permission evidence is sampled and cached by the permission provider.
@MainActor
public class SystemValidator {
    static let canonicalCaptureTimeout: TimeInterval = 12

    // MARK: - Dependencies

    private let systemStateProvider: SystemStateProvider
    private weak var kanataManager: RuntimeCoordinator?
    /// Outside KeyPath.app (the CLI) there is no runtime coordinator; this
    /// asks the running app instead. True means its session runtime is ready.
    private let appSessionReady: (@Sendable () async -> Bool)?
    private let useTestSnapshot: Bool

    init(
        systemStateProvider: SystemStateProvider = .shared,
        kanataManager: RuntimeCoordinator? = nil,
        appSessionReady: (@Sendable () async -> Bool)? = nil,
        useTestSnapshot: Bool = TestEnvironment.isRunningTests
            && ProcessInfo.processInfo.environment["KEYPATH_FORCE_REAL_VALIDATION"] != "1"
    ) {
        self.systemStateProvider = systemStateProvider
        self.kanataManager = kanataManager
        self.appSessionReady = appSessionReady
        self.useTestSnapshot = useTestSnapshot
    }

    public func checkSystem() async -> SystemSnapshot {
        await checkSystem(freshness: .cached)
    }

    public func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        if useTestSnapshot {
            return Self.makeTestSnapshot()
        }

        return await Self.boundedCapture(timeout: Self.canonicalCaptureTimeout) {
            await self.captureSessionSnapshot(freshness: freshness)
        }
    }

    static func boundedCapture(
        timeout: TimeInterval,
        operation: @MainActor @Sendable @escaping () async -> SystemSnapshot
    ) async -> SystemSnapshot {
        do {
            return try await withTimeout(.seconds(timeout), cancellation: .returnImmediately, operation: operation)
        } catch is OperationTimeoutError {
            let message = "⏱️ [SystemValidator] Canonical capture timed out after \(String(format: "%.2f", timeout))s"
            if TestEnvironment.isRunningTests {
                AppLogger.shared.info(message)
            } else {
                AppLogger.shared.warn(message)
            }
            return .unavailable(captureStatus: .timedOut, source: "system-validator-timeout")
        } catch {
            return .unavailable(captureStatus: .cancelled, source: "system-validator-cancelled")
        }
    }

    private func captureSessionSnapshot(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        guard !Task.isCancelled else {
            return .unavailable(captureStatus: .cancelled, source: "cancelled")
        }

        let permissions = switch freshness {
        case .cached: await systemStateProvider.currentPermissionSnapshot()
        case .fresh: await systemStateProvider.refreshPermissionSnapshot()
        }
        let running: Bool
        let responding: Bool
        if let kanataManager {
            let report = kanataManager.serviceLifecycleCoordinator.currentSessionReport()
            running = report?.state == .running && report?.tapActive == true
            responding = running
                ? await systemStateProvider.isEngineSocketResponding(path: report?.controlSocketPath, timeoutMs: 300)
                : false
        } else {
            // Outside the app (the CLI) the engine refuses every connection: it
            // admits only the app that launched it (ADR-046). Ask the app to
            // query the engine; "running" alone does not prove it answers.
            running = await appSessionReady?() ?? false
            responding = running ? await ConfigFacade().tcpCheckHealth() : false
        }
        let host = KanataRuntimeHost.current()
        let payload = FileManager.default.fileExists(atPath: host.bridgeLibraryPath)
            && FileManager.default.fileExists(atPath: Bundle.main.executablePath ?? "")
        return SystemSnapshot(
            permissions: permissions,
            components: ComponentStatus(kanataBinaryInstalled: payload, requiredRuntimePayloadPresent: payload),
            conflicts: .empty,
            health: HealthStatus(
                kanataProcessRunning: running, kanataTCPResponding: responding,
                kanataRunning: running && responding,
                kanataInputCaptureReady: running,
                activeRuntimePathTitle: String(localized: "Driverless session runtime"),
                activeRuntimePathDetail: String(localized: "Current user · KeyPath app identity · session event tap")
            ),
            compatibility: SystemCompatibilityStatus(macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString),
            timestamp: Date()
        )
    }

    // MARK: - Test Support

    /// Create a minimal snapshot for test mode - returns immediately without system calls
    /// This provides realistic-looking stub data for tests that don't need real system state
    private static func makeTestSnapshot() -> SystemSnapshot {
        let now = Date()
        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot(
                accessibility: .granted,
                runtimeKeyAccess: .init(status: .granted, source: "test-stub", confidence: .high, timestamp: now),
                timestamp: now
            ),
            components: ComponentStatus(kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(kanataRunning: true),
            compatibility: SystemCompatibilityStatus(macOSVersion: "test"),
            timestamp: now
        )
    }
}

/// Sendable is already required of this type: the wizard protocol it conforms to
/// in WizardProtocolConformances.swift inherits Sendable, so the conformance has
/// been in force all along. Swift 6 requires it to be declared alongside the
/// class rather than in the conformance file, so state it here. This records the
/// existing guarantee where the compiler wants it; it is not a new claim about
/// this type's thread safety.
extension SystemValidator: @unchecked Sendable {}
