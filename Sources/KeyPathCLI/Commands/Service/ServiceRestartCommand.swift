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
            let error = CLIError.serviceUnreachable(hint: "Failed to restart service. Check 'keypath service status' for details")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
