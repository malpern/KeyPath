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
        let spinner = CLISpinner(context: ctx)
        spinner.start("Installing...")

        let facade = await MainActor.run { CLIFacade() }
        let report: CLIInstallerReport
        do {
            report = try await withThrowingTimeout(seconds: globals.timeout) {
                await facade.runInstall()
            }
        } catch is TimeoutError {
            spinner.fail("Installation timed out after \(globals.timeout)s")
            throw ExitCode.failure
        }

        if report.success { spinner.succeed("Installation complete") }
        else { spinner.fail("Installation failed") }

        CLIOutput.write(report, context: ctx) {
            formatInstallerReport(report, title: "Installation")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }
}
