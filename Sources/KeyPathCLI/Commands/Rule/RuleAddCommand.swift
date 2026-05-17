import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create or modify a key remapping"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key to remap (e.g., caps, lalt)")
    var input: String

    @Argument(help: "Output key for simple remap (e.g., esc, lctl)")
    var output: String?

    @Option(help: "Key to emit on tap (for tap-hold)")
    var tap: String?

    @Option(help: "Key to emit on hold (for tap-hold)")
    var hold: String?

    @Option(help: "Tap-hold timeout in milliseconds (default: 200)")
    var timeout: Int = 200

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    func validate() throws {
        if (tap != nil) != (hold != nil) {
            throw ValidationError("--tap and --hold must be used together")
        }
    }

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        if let tap, let hold {
            for (key, label) in [(input, "input"), (tap, "tap"), (hold, "hold")] {
                guard facade.validateKey(key) != nil else {
                    let error = CLIError.invalidKey(key, label: label)
                    CLIOutput.writeError(error, context: ctx)
                    throw error.code.exitCode
                }
            }

            let replaced = try await facade.addTapHoldRemap(input: input, tap: tap, hold: hold, timeout: timeout)
            let result = ["replaced": "\(replaced)", "input": input, "tap": tap, "hold": hold, "timeout": "\(timeout)"]
            CLIOutput.write(result, context: ctx) {
                var lines: [String] = []
                if replaced { lines.append("Replaced existing mapping for '\(input)'") }
                lines.append("Mapped \(input) → tap:\(tap), hold:\(hold) (timeout: \(timeout)ms)")
                return lines.joined(separator: "\n")
            }
        } else if let output {
            for (key, label) in [(input, "input"), (output, "output")] {
                guard facade.validateKey(key) != nil else {
                    let error = CLIError.invalidKey(key, label: label)
                    CLIOutput.writeError(error, context: ctx)
                    throw error.code.exitCode
                }
            }

            let replaced = try await facade.addSimpleRemap(input: input, output: output)
            let result = ["replaced": replaced ? "true" : "false", "input": input, "output": output]
            CLIOutput.write(result, context: ctx) {
                var lines: [String] = []
                if replaced { lines.append("Replaced existing mapping for '\(input)'") }
                lines.append("Mapped \(input) → \(output)")
                return lines.joined(separator: "\n")
            }
        } else {
            let error = CLIError.validation(
                "Missing output key",
                hint: "Specify an output key, or --tap/--hold for tap-hold"
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
    }
}
