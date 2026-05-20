import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleEnsure: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ensure",
        abstract: "Ensure a rule exists with the given mapping (idempotent)"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key")
    var input: String

    @Argument(help: "Output key")
    var output: String

    @Option(help: "Hold output for tap-hold")
    var hold: String?

    @Option(help: "Tap-hold timeout in ms (default: 200)")
    var timeout: Int = 200

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let existing = await facade.showRule(input: input)

        let matchesDesired: Bool
        if let existing {
            if let hold {
                if case let .dualRole(dr) = existing.behavior {
                    matchesDesired = existing.action.outputString == output
                        && dr.holdActionString == hold
                        && dr.tapTimeout == timeout
                } else {
                    matchesDesired = false
                }
            } else {
                matchesDesired = existing.action.outputString == output && existing.behavior == nil
            }
        } else {
            matchesDesired = false
        }

        if matchesDesired {
            let result = CLIEnsureResult(input: input, output: output, action: "unchanged")
            CLIOutput.write(result, context: ctx) {
                "Rule '\(input) → \(output)' already matches — no change"
            }
            return
        }

        if globals.dryRun {
            let action = existing != nil ? "would-update" : "would-create"
            let result = CLIEnsureResult(input: input, output: output, action: action)
            CLIOutput.write(result, context: ctx) {
                existing != nil
                    ? "Would update rule: \(input) → \(output)"
                    : "Would create rule: \(input) → \(output)"
            }
            return
        }

        if let hold {
            _ = try await facade.addTapHoldRemap(input: input, tap: output, hold: hold, timeout: timeout)
        } else {
            _ = try await facade.addSimpleRemap(input: input, output: output)
        }

        let action = existing != nil ? "updated" : "created"
        let result = CLIEnsureResult(input: input, output: output, action: action)
        CLIOutput.write(result, context: ctx) {
            existing != nil
                ? "Updated rule: \(input) → \(output)"
                : "Created rule: \(input) → \(output)"
        }

        try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
    }
}

private struct CLIEnsureResult: Codable {
    let input: String
    let output: String
    let action: String
}
