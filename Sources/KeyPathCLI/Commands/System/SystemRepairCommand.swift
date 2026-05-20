import ArgumentParser
import Foundation
import KeyPathAppKit

struct SystemRepair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repair",
        abstract: "Repair broken or unhealthy services"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let spinner = CLISpinner(context: ctx)
        spinner.start("Repairing...")

        let facade = await MainActor.run { CLIFacade() }
        let report = await facade.runRepair()

        if report.success { spinner.succeed("Repair complete") }
        else { spinner.fail("Repair failed") }

        CLIOutput.write(report, context: ctx) {
            if report.fastRepair {
                return "Repair completed via KanataService restart."
            }
            return formatInstallerReport(report, title: "Repair")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }
}
