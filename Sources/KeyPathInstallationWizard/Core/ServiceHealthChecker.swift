import Foundation
import KeyPathCore
import KeyPathWizardCore
import os.lock

/// Readiness evidence for the session runtime.
///
/// The session runtime lives in a KeyPath-owned user-session worker, so readiness
/// comes from `ServiceLifecycleCoordinator`, which registers a provider at launch
/// (`configureSessionReadinessProvider`). Without a provider (the CLI, or tests
/// that do not configure one) the runtime reports not running.
// SAFETY: @unchecked Sendable — the only mutable state is the provider, protected
// by OSAllocatedUnfairLock.
public final class ServiceHealthChecker: @unchecked Sendable {
    @MainActor public static let shared = ServiceHealthChecker()

    public struct KanataServiceRuntimeSnapshot: Sendable, Equatable {
        public let isRunning: Bool
        public let isResponding: Bool
        public let inputCaptureReady: Bool
        public let inputCaptureIssue: String?

        public init(
            isRunning: Bool,
            isResponding: Bool,
            inputCaptureReady: Bool,
            inputCaptureIssue: String?
        ) {
            self.isRunning = isRunning
            self.isResponding = isResponding
            self.inputCaptureReady = inputCaptureReady
            self.inputCaptureIssue = inputCaptureIssue
        }

        public var readiness: KanataRuntimeReadiness {
            KanataRuntimeReadiness(
                isRunning: isRunning,
                isResponding: isResponding,
                inputCaptureReady: inputCaptureReady
            )
        }
    }

    private let sessionReadinessProvider = OSAllocatedUnfairLock<(@Sendable () async -> KanataRuntimeReadiness)?>(initialState: nil)

    @MainActor
    public init() {}

    public func configureSessionReadinessProvider(_ provider: @escaping @Sendable () async -> KanataRuntimeReadiness) {
        sessionReadinessProvider.withLock { $0 = provider }
    }

    // MARK: - Session runtime readiness

    /// Process + TCP + input-capture readiness of the session runtime.
    public nonisolated func checkKanataServiceHealth() async -> KanataRuntimeReadiness {
        await sessionReadinessProvider.withLock { $0 }?()
            ?? KanataRuntimeReadiness(isRunning: false, isResponding: false, inputCaptureReady: false)
    }

    public nonisolated func checkKanataServiceRuntimeSnapshot() async -> KanataServiceRuntimeSnapshot {
        let readiness = await checkKanataServiceHealth()
        return KanataServiceRuntimeSnapshot(
            isRunning: readiness.isRunning,
            isResponding: readiness.isResponding,
            inputCaptureReady: readiness.inputCaptureReady,
            inputCaptureIssue: readiness.isReady ? nil : "driverless-runtime-not-ready"
        )
    }
}
