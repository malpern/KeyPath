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
        let facade = ConfigFacade()
        let result = await facade.validateConfig()

        CLIOutput.write(result, context: ctx) {
            let nc = ctx.noColor
            if result.isValid {
                var lines = [ANSIColor.green("✓ Configuration is valid.", noColor: nc)]
                if let path = result.configPath {
                    lines.append(ANSIColor.dim("  Path: \(path)", noColor: nc))
                }
                if let bytes = result.configBytes {
                    lines.append(ANSIColor.dim("  Size: \(bytes) bytes", noColor: nc))
                }
                if let cols = result.collectionsCount, let rules = result.customRulesCount {
                    lines.append(ANSIColor.dim("  Collections: \(cols), Custom rules: \(rules)", noColor: nc))
                }
                return lines.joined(separator: "\n")
            }
            var lines = [ANSIColor.red("✗ Configuration validation failed:", noColor: nc)]
            for error in result.errors {
                lines.append("  - \(error)")
            }
            if let path = result.configPath {
                lines.append(ANSIColor.dim("  Config: \(path)", noColor: nc))
            }
            if let cols = result.collectionsCount, let rules = result.customRulesCount {
                lines.append(ANSIColor.dim("  Collections: \(cols), Custom rules: \(rules)", noColor: nc))
            }
            return lines.joined(separator: "\n")
        }

        if !result.isValid {
            throw CLIExitCode.kanataInvalid.exitCode
        }
    }
}
