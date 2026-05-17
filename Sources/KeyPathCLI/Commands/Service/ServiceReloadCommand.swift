import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceReload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Hot-reload Kanata configuration"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        CLIOutput.progress("Reloading Kanata configuration...", context: ctx)

        let facade = await MainActor.run { CLIFacade() }
        let success = await facade.tcpReload()

        if success {
            CLIOutput.write(["reloaded": true], context: ctx) {
                "Configuration reloaded successfully."
            }
        } else {
            let error = CLIError.serviceUnreachable(hint: "Check that Kanata is running with 'keypath service status'")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
