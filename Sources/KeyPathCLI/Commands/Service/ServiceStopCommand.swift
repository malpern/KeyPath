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
        let facade = await MainActor.run { CLIFacade() }

        let success = await facade.stopService()
        if success {
            CLIOutput.write(["stopped": true], context: ctx) {
                "Kanata service stopped."
            }
        } else {
            let error = CLIError.serviceUnreachable(hint: "Failed to stop service. Is it running? Check with 'keypath service status'")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
