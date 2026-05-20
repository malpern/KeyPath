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

    @Option(help: "Full KeyAction as JSON (e.g., '{\"hyper\":{}}')")
    var action: String?

    @Option(help: "Full MappingBehavior as JSON")
    var behavior: String?

    @Option(help: "Key to emit on tap (for tap-hold)")
    var tap: String?

    @Option(help: "Key to emit on hold (for tap-hold)")
    var hold: String?

    @Option(name: .customLong("tap-timeout"), help: "Tap-hold timeout in milliseconds (default: 200)")
    var tapTimeout: Int = 200

    @Option(help: "Alternate output when shift is held")
    var shifted: String?

    @Option(help: "Target layer for this rule (default: base)")
    var layer: String?

    @Option(help: "Human-readable title for the rule")
    var title: String?

    @Option(help: "Optional notes/description")
    var notes: String?

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    func validate() throws {
        if (tap != nil) != (hold != nil) {
            throw ValidationError("--tap and --hold must be used together")
        }
        let modeCount = [output != nil, action != nil, tap != nil].filter { $0 }.count
        if modeCount > 1 {
            throw ValidationError("Specify only one of: <output>, --action, or --tap/--hold")
        }
        if modeCount == 0 && behavior == nil {
            throw ValidationError("Specify an output key, --action, --tap/--hold, or --behavior")
        }
    }

    mutating func run() async throws {
        let ctx = globals.outputContext
        let validator = SimulatorFacade()
        let rules = RulesFacade()

        guard validator.validateKey(input) != nil else {
            let error = CLIError.invalidKey(input, label: "input")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        let resolvedAction: KeyAction
        var resolvedBehavior: MappingBehavior?

        if let actionJSON = action {
            resolvedAction = try decodeAction(actionJSON, context: ctx)
        } else if let tap, let hold {
            for (key, label) in [(tap, "tap"), (hold, "hold")] {
                guard validator.validateKey(key) != nil else {
                    let error = CLIError.invalidKey(key, label: label)
                    CLIOutput.writeError(error, context: ctx)
                    throw error.code.exitCode
                }
            }
            resolvedAction = .keystroke(key: tap)
            resolvedBehavior = .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: tap),
                holdAction: .keystroke(key: hold),
                tapTimeout: tapTimeout
            ))
        } else if let output {
            guard validator.validateKey(output) != nil else {
                let error = CLIError.invalidKey(output, label: "output")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            resolvedAction = .keystroke(key: output)
        } else {
            resolvedAction = .empty
        }

        if let behaviorJSON = behavior {
            resolvedBehavior = try decodeBehavior(behaviorJSON, context: ctx)
        }

        let conflictStrategy: CLIConflictStrategy = switch globals.onConflict {
        case .fail: .fail
        case .replace: .replace
        case .skip: .skip
        case .merge: .merge
        }

        if globals.dryRun {
            let detail = CLIRuleDetail.dryRunPreview(
                input: input,
                action: resolvedAction.isEmpty ? nil : resolvedAction,
                behavior: resolvedBehavior,
                shiftedOutput: shifted,
                title: title,
                notes: notes,
                targetLayer: layer
            )
            let dryResult = DryRunOutput(wouldCreate: true, rule: detail)
            CLIOutput.write(dryResult, context: ctx) {
                "Would create rule: \(input) → \(resolvedAction.displayName)"
            }
            return
        }

        let finalAction = resolvedAction.isEmpty ? .keystroke(key: input) : resolvedAction

        do {
            let result = try await rules.addRule(
                input: input,
                action: finalAction,
                behavior: resolvedBehavior,
                shiftedOutput: shifted,
                title: title,
                notes: notes,
                targetLayer: layer,
                onConflict: conflictStrategy
            )

            CLIOutput.write(result, context: ctx) {
                switch result {
                case let .created(detail):
                    "Created rule: \(detail.input) → \(detail.action.displayName)"
                case let .replaced(detail):
                    "Replaced rule: \(detail.input) → \(detail.action.displayName)"
                case let .merged(detail):
                    "Merged rule: \(detail.input) → \(detail.action.displayName)"
                case .skipped:
                    "Skipped: rule already exists for '\(input)'"
                }
            }
        } catch let mergeErr as CLIMergeError {
            let error = CLIError.conflict(
                mergeErr.description,
                hint: "Use --on-conflict=replace to overwrite instead"
            )
            CLIOutput.writeError(error, context: ctx)
            throw CLIExitCode.conflict.exitCode
        } catch is CLIConflictError {
            let error = CLIError.conflict(
                "Rule already exists for '\(input)'",
                hint: "Use --on-conflict=replace to overwrite, --on-conflict=skip to no-op, or --on-conflict=merge to combine"
            )
            CLIOutput.writeError(error, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }

        try await applyConfigurationOrHint(apply: apply, context: ctx)
    }

    private func decodeAction(_ json: String, context: OutputContext) throws -> KeyAction {
        guard let data = json.data(using: .utf8) else {
            let error = CLIError.validation("Invalid JSON for --action")
            CLIOutput.writeError(error, context: context)
            throw error.code.exitCode
        }
        do {
            return try JSONDecoder().decode(KeyAction.self, from: data)
        } catch {
            let cliError = CLIError.validation(
                "Failed to decode --action JSON",
                hint: "Run 'keypath help-topics schemas action' for valid formats",
                details: [error.localizedDescription]
            )
            CLIOutput.writeError(cliError, context: context)
            throw cliError.code.exitCode
        }
    }

    private func decodeBehavior(_ json: String, context: OutputContext) throws -> MappingBehavior {
        guard let data = json.data(using: .utf8) else {
            let error = CLIError.validation("Invalid JSON for --behavior")
            CLIOutput.writeError(error, context: context)
            throw error.code.exitCode
        }
        do {
            return try JSONDecoder().decode(MappingBehavior.self, from: data)
        } catch {
            let cliError = CLIError.validation(
                "Failed to decode --behavior JSON",
                hint: "Run 'keypath help-topics schemas behavior' for valid formats",
                details: [error.localizedDescription]
            )
            CLIOutput.writeError(cliError, context: context)
            throw cliError.code.exitCode
        }
    }
}

private struct DryRunOutput: Codable {
    let wouldCreate: Bool
    let rule: CLIRuleDetail
}
