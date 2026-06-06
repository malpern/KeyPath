import ArgumentParser
import Foundation
import KeyPathAppKit

struct SystemInstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install KeyPath services and components"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let dryRun = globals.dryRun
        let spinner = CLISpinner(context: ctx)
        spinner.start("Installing...")

        let facade = SystemFacade()
        let report: CLIInstallerReport
        do {
            report = try await withThrowingTimeout(seconds: globals.timeout) {
                await facade.runInstall(dryRun: dryRun)
            }
        } catch is TimeoutError {
            spinner.fail("Installation timed out after \(globals.timeout)s")
            throw ExitCode.failure
        }

        if dryRun, report.success {
            spinner.succeed("Installation plan ready")
        } else if dryRun {
            spinner.fail("Installation plan has blockers")
        } else if report.success { spinner.succeed("Installation complete") }
        else { spinner.fail("Installation failed") }

        CLIOutput.write(report, context: ctx) {
            formatInstallerReport(report, title: dryRun ? "Installation Dry Run" : "Installation")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }
}
