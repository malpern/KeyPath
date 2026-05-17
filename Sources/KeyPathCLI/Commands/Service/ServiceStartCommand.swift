import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceStart: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the Kanata service"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let success = await facade.startService()
        if success {
            CLIOutput.write(["started": true], context: ctx) {
                "Kanata service started."
            }
        } else {
            let error = CLIError.serviceUnreachable(hint: "Failed to start service. Is it installed? Run 'keypath system install'")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
