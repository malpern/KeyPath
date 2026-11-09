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

        // The CLI owns stdout/stderr. Keep app-internal logs in the log file so
        // JSON output remains machine-parseable in debug builds.
        AppLogger.shared.setConsoleLoggingEnabled(false)

        // The session runtime lives in KeyPath.app, out of this process's
        // sight. Ask the running app, the way `keypath doctor` does, so local
        // inspection agrees with it instead of always reading "not running".
        let validator = SystemValidator(kanataManager: nil, appSessionReady: { AppSessionProbe.isReady() })
        await SystemStateProvider.shared.configureRuntimeKeyAccessProvider {
            guard AppSessionProbe.isReady() else { return nil }
            return .init(status: .granted, source: "keypath-app.doctor", confidence: .high, timestamp: Date())
        }

        configureCLIWizardDependencies(systemValidator: validator)
        isConfigured = true
    }
}

/// One `doctor` request to the running KeyPath.app per CLI process. Ready means
/// the app verified its session runtime is running with keyboard access. No
/// answer (app not running) counts as not ready; this never launches the app.
enum AppSessionProbe {
    private static let answer = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    static func isReady() -> Bool {
        answer.withLock { cached in
            if let cached { return cached }
            // Tests must never depend on whichever KeyPath.app happens to run.
            if TestEnvironment.isRunningTests { return false }
            let ready = (try? RuntimeControl.send(.init(operation: .doctor), timeout: 10))?.ready == true
            cached = ready
            return ready
        }
    }
}
