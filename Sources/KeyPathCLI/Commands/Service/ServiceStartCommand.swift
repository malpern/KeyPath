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
        let facade = SystemFacade()

        let success = await facade.startService()
        if success {
            CLIOutput.write(["started": true], context: ctx) {
                "Kanata service started."
            }
        } else {
            let error = CLIError.serviceControlFailed(
                action: "start",
                hint: "Run 'keypath service status --json' to inspect runtime health. If macOS blocks system service control, use KeyPath's repair UI."
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
