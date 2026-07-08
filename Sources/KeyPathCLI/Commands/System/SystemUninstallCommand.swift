import ArgumentParser
import Foundation
import KeyPathAppKit
import KeyPathCLISupport

struct SystemUninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove KeyPath services and components"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .customLong("delete-config"), help: "Also delete user configuration files")
    var deleteConfig: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        if deleteConfig {
            CLIOutput.progress("Starting uninstall (configuration will be deleted)...", context: ctx)
        } else {
            CLIOutput.progress("Starting uninstall (configuration will be preserved)...", context: ctx)
        }

        let facade = SystemFacade()
        let shouldDeleteConfig = deleteConfig
        let timeoutSeconds = globals.timeout
        let report: CLIInstallerReport
        do {
            report = try await withThrowingTimeout(seconds: timeoutSeconds) {
                await facade.runUninstall(deleteConfig: shouldDeleteConfig)
            }
        } catch is TimeoutError {
            CLIOutput.progress("Uninstall timed out after \(timeoutSeconds)s", context: ctx)
            throw ExitCode.failure
        }

        CLIOutput.write(report, context: ctx) {
            formatInstallerReport(report, title: "Uninstall")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }
}
