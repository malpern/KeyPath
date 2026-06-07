import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceRestart: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart the Kanata service"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = SystemFacade()

        CLIOutput.progress("Restarting Kanata service...", context: ctx)
        let success = await facade.restartService()
        if success {
            CLIOutput.write(["restarted": true], context: ctx) {
                "Kanata service restarted."
            }
        } else {
            let error = CLIError.serviceControlFailed(
                action: "restart",
                hint: "macOS may require administrator authorization for system services. Check 'keypath service status --json' or use KeyPath's repair UI."
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
