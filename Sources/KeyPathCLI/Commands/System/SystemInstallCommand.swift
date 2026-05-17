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
        CLIOutput.progress("Starting installation...", context: ctx)

        let facade = CLIFacade()
        let report = await facade.runInstall()

        CLIOutput.write(report, context: ctx) {
            formatInstallerReport(report, title: "Installation")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }
}
