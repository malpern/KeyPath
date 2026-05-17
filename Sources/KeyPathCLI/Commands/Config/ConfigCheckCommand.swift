import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate configuration using kanata --check"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CLIFacade()
        let result = await facade.validateConfig()

        CLIOutput.write(result, context: ctx) {
            if result.isValid {
                return "Configuration is valid."
            }
            var lines = ["Configuration validation failed:"]
            for error in result.errors {
                lines.append("  - \(error)")
            }
            return lines.joined(separator: "\n")
        }

        if !result.isValid {
            throw CLIExitCode.kanataInvalid.exitCode
        }
    }
}
