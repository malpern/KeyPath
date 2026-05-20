import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print current generated .kbd configuration"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }
        let config = await facade.currentConfig()

        CLIOutput.write(["config": config], context: ctx) {
            config
        }
    }
}
