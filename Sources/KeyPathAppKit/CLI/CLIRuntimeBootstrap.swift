import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import os.lock

@MainActor
enum CLIRuntimeBootstrap {
    private static var isConfigured = false

    static func ensureConfigured() async {
        guard !isConfigured else { return }
        // Set before the first await so a concurrent caller cannot configure twice.
        isConfigured = true

        // The CLI owns stdout/stderr. Keep app-internal logs in the log file so
        // JSON output remains machine-parseable in debug builds.
        AppLogger.shared.setConsoleLoggingEnabled(false)

        // The session runtime lives in KeyPath.app, out of this process's
        // sight. Ask the running app, the way `keypath doctor` does, so local
        // inspection agrees with it instead of always reading "not running".
        let validator = SystemValidator(kanataManager: nil, appSessionReady: { AppSessionProbe.current().runtimeRunning })
        await SystemStateProvider.shared.configureRuntimeKeyAccessProvider {
            guard AppSessionProbe.current().runtimeKeyAccess else { return nil }
            return .init(status: .granted, source: "keypath-app.doctor", confidence: .high, timestamp: Date())
        }

        configureCLIWizardDependencies(systemValidator: validator)
    }
}

/// One `doctor` request to the running KeyPath.app per CLI process. This never
/// launches the app; no answer reads as "runtime not running", which is then true.
///
/// The answer is cached for the life of the process. That is safe only because
/// the CLI cannot change the runtime itself (it has no runtime coordinator); a
/// CLI path that forwards start/stop to the app must re-ask afterwards.
enum AppSessionProbe {
    struct Evidence: Equatable {
        /// The app's session runtime is running.
        let runtimeRunning: Bool
        /// Running, and the app reports no permission problem, so the runtime
        /// has keyboard access. Anything else is left unverified, not denied.
        let runtimeKeyAccess: Bool

        static let none = Evidence(runtimeRunning: false, runtimeKeyAccess: false)
    }

    private static let cached = OSAllocatedUnfairLock<Evidence?>(initialState: nil)

    static func current() -> Evidence {
        if let evidence = cached.withLock({ $0 }) { return evidence }
        // Tests must never depend on whichever KeyPath.app happens to run.
        let evidence: Evidence = if TestEnvironment.isRunningTests {
            .none
        } else {
            evidence(from: try? RuntimeControl.send(.init(operation: .doctor), timeout: 10))
        }
        // Ask outside the lock: the socket call can block for the full timeout.
        return cached.withLock { stored in
            if let stored { return stored }
            stored = evidence
            return evidence
        }
    }

    /// Runtime facts from the app's doctor answer. `ready` covers the whole
    /// system, so it is not used here: a conflict must not read as "stopped".
    static func evidence(from response: RuntimeControl.Response?) -> Evidence {
        guard let response, response.state == .running else { return .none }
        let permissionProblem = response.issues?.contains { $0.category == "permissions" } ?? false
        return Evidence(runtimeRunning: true, runtimeKeyAccess: !permissionProblem)
    }
}
