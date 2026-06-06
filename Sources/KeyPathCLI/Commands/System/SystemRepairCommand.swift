import ArgumentParser
import Foundation
import KeyPathAppKit

struct SystemRepair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repair",
        abstract: "Repair broken or unhealthy services"
    )

    @OptionGroup var globals: GlobalOptions
    @Flag(name: .customLong("open-permissions"), help: "Open the relevant System Settings pane when permissions require manual repair")
    var openPermissions: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let dryRun = globals.dryRun
        let spinner = CLISpinner(context: ctx)
        spinner.start("Repairing...")

        let facade = SystemFacade()
        let report: CLIInstallerReport
        do {
            report = try await withThrowingTimeout(seconds: globals.timeout) {
                await facade.runRepair(dryRun: dryRun)
            }
        } catch is TimeoutError {
            spinner.fail("Repair timed out after \(globals.timeout)s")
            throw ExitCode.failure
        }

        if dryRun, report.success {
            spinner.succeed("Repair plan ready")
        } else if dryRun {
            spinner.fail("Repair plan has blockers")
        } else if report.success { spinner.succeed("Repair complete") }
        else { spinner.fail("Repair failed") }

        if openPermissions, let issues = report.issues {
            let opened = await facade.openFirstRemediationURL(in: issues)
            if !opened {
                CLIOutput.progress("No permission remediation URL was available.", context: ctx)
            }
        }

        CLIOutput.write(report, context: ctx) {
            if report.fastRepair {
                return "Repair completed via KanataService restart."
            }
            return formatInstallerReport(report, title: dryRun ? "Repair Dry Run" : "Repair")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }
}
