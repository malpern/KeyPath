import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigPath: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Print the configuration file path"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let path = await MainActor.run { ConfigFacade().configPath() }

        CLIOutput.write(["path": path], context: ctx) {
            path
        }
    }
}
