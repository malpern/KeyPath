import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleEnsure: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ensure",
        abstract: "Ensure a rule exists with the given mapping (idempotent)"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key (omit when using --from-file)")
    var input: String?

    @Argument(help: "Output key (omit when using --from-file)")
    var output: String?

    @Option(help: "Hold output for tap-hold")
    var hold: String?

    @Option(name: .customLong("tap-timeout"), help: "Tap-hold timeout in ms (default: 200)")
    var tapTimeout: Int = 200

    @Option(name: .customLong("from-file"), help: "JSON file with array of rules to ensure (batch mode)")
    var fromFile: String?

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        if let fromFile {
            try await runBatch(file: fromFile, facade: facade, ctx: ctx)
        } else {
            guard let input, let output else {
                let error = CLIError.validation(
                    "Missing required arguments: <input> <output>",
                    hint: "Provide input and output keys, or use --from-file for batch mode"
                )
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            let spec = EnsureSpec(input: input, output: output, hold: hold, timeout: tapTimeout)
            let result = try await ensureOne(spec: spec, facade: facade, dryRun: globals.dryRun)

            CLIOutput.write(result, context: ctx) {
                switch result.action {
                case "unchanged":
                    "Rule '\(result.input) → \(result.output)' already matches — no change"
                case "would-create":
                    "Would create rule: \(result.input) → \(result.output)"
                case "would-update":
                    "Would update rule: \(result.input) → \(result.output)"
                case "created":
                    "Created rule: \(result.input) → \(result.output)"
                case "updated":
                    "Updated rule: \(result.input) → \(result.output)"
                default:
                    "\(result.action): \(result.input) → \(result.output)"
                }
            }

            if result.action == "created" || result.action == "updated" {
                try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
            }
        }
    }

    private func runBatch(file: String, facade: CLIFacade, ctx: OutputContext) async throws {
        let path = (file as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else {
            let error = CLIError.validation("Cannot read file: '\(file)'")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        let specs: [EnsureSpec]
        do {
            specs = try JSONDecoder().decode([EnsureSpec].self, from: data)
        } catch {
            let cliError = CLIError.validation(
                "Invalid JSON in '\(file)'",
                hint: "Expected array of {\"input\": \"...\", \"output\": \"...\", \"hold\": \"...\", \"timeout\": 200}"
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        var results: [CLIEnsureResult] = []
        for spec in specs {
            let result = try await ensureOne(spec: spec, facade: facade, dryRun: globals.dryRun)
            results.append(result)
        }

        let batchResult = CLIBatchEnsureResult(
            total: results.count,
            created: results.filter { $0.action == "created" || $0.action == "would-create" }.count,
            updated: results.filter { $0.action == "updated" || $0.action == "would-update" }.count,
            unchanged: results.filter { $0.action == "unchanged" }.count,
            rules: results
        )

        CLIOutput.write(batchResult, context: ctx) {
            var lines = ["Batch ensure: \(batchResult.total) rules processed"]
            if batchResult.created > 0 {
                let verb = globals.dryRun ? "would create" : "created"
                lines.append("  \(verb): \(batchResult.created)")
            }
            if batchResult.updated > 0 {
                let verb = globals.dryRun ? "would update" : "updated"
                lines.append("  \(verb): \(batchResult.updated)")
            }
            if batchResult.unchanged > 0 {
                lines.append("  unchanged: \(batchResult.unchanged)")
            }
            return lines.joined(separator: "\n")
        }

        let hadChanges = results.contains { $0.action == "created" || $0.action == "updated" }
        if hadChanges {
            try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
        }
    }

    private func ensureOne(spec: EnsureSpec, facade: CLIFacade, dryRun: Bool) async throws -> CLIEnsureResult {
        let existing = await facade.showRule(input: spec.input)

        let matchesDesired: Bool
        if let existing {
            if let hold = spec.hold {
                if case let .dualRole(dr) = existing.behavior {
                    matchesDesired = existing.action.outputString == spec.output
                        && dr.holdActionString == hold
                        && dr.tapTimeout == spec.timeout
                } else {
                    matchesDesired = false
                }
            } else {
                matchesDesired = existing.action.outputString == spec.output && existing.behavior == nil
            }
        } else {
            matchesDesired = false
        }

        if matchesDesired {
            return CLIEnsureResult(input: spec.input, output: spec.output, action: "unchanged")
        }

        if dryRun {
            let action = existing != nil ? "would-update" : "would-create"
            return CLIEnsureResult(input: spec.input, output: spec.output, action: action)
        }

        if let hold = spec.hold {
            _ = try await facade.addTapHoldRemap(input: spec.input, tap: spec.output, hold: hold, timeout: spec.timeout)
        } else {
            _ = try await facade.addSimpleRemap(input: spec.input, output: spec.output)
        }

        let action = existing != nil ? "updated" : "created"
        return CLIEnsureResult(input: spec.input, output: spec.output, action: action)
    }
}

struct EnsureSpec: Codable {
    let input: String
    let output: String
    let hold: String?
    let timeout: Int

    init(input: String, output: String, hold: String? = nil, timeout: Int = 200) {
        self.input = input
        self.output = output
        self.hold = hold
        self.timeout = timeout
    }
}

private struct CLIEnsureResult: Codable {
    let input: String
    let output: String
    let action: String
}

private struct CLIBatchEnsureResult: Codable {
    let total: Int
    let created: Int
    let updated: Int
    let unchanged: Int
    let rules: [CLIEnsureResult]
}
