import ArgumentParser
import Foundation
import KeyPathAppKit

struct LayerSwitch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switch",
        abstract: "Switch to a layer by name"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Layer name (e.g., base, nav, vim)")
    var name: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = ConfigFacade()
        let success = await facade.tcpChangeLayer(name)
        if success {
            CLIOutput.write(["layer": name], context: ctx) {
                "Switched to layer '\(name)'"
            }
        } else {
            let error = CLIError.notFound("Layer", query: name, listCommand: "keypath layer list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
