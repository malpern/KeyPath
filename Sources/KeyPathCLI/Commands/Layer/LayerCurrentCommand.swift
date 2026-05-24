import ArgumentParser
import Foundation
import KeyPathAppKit

struct LayerCurrent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "current",
        abstract: "Show the currently active layer"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = ConfigFacade()

        let layer: String
        do {
            layer = try await facade.tcpGetCurrentLayer()
        } catch {
            let cliError = CLIError.serviceUnreachable()
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        CLIOutput.write(["layer": layer], context: ctx) {
            layer
        }
    }
}
