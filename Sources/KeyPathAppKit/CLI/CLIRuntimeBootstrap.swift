import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore

@MainActor
enum CLIRuntimeBootstrap {
    private static var isConfigured = false

    static func ensureConfigured() {
        guard !isConfigured else { return }

        // The CLI owns stdout/stderr. Keep app-internal logs in the log file so
        // JSON output remains machine-parseable in debug builds.
        AppLogger.shared.setConsoleLoggingEnabled(false)

        let validator = SystemValidator(kanataManager: nil)

        configureCLIWizardDependencies(systemValidator: validator)
        isConfigured = true
    }
}
