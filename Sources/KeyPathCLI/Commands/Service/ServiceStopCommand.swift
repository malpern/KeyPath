import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceStop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the Kanata service"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = SystemFacade()

        let success = await facade.stopService()
        if success {
            CLIOutput.write(["stopped": true], context: ctx) {
                "Kanata service stopped."
            }
        } else {
            let error = CLIError.serviceControlFailed(
                action: "stop",
                hint: "macOS may require administrator authorization for system services. Check 'keypath service status --json' or use KeyPath's repair UI."
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
