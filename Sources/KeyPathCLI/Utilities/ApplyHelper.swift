import ArgumentParser
import Foundation
import KeyPathAppKit

func applyConfigurationOrHint(apply: Bool, context: OutputContext) async throws {
    if apply {
        let facade = ConfigFacade()
        let result = try await facade.applyConfiguration()
        if result.reloadSuccess {
            CLIOutput.write(["applied": true], context: context) {
                "Config applied and Kanata reloaded."
            }
        } else {
            let error = CLIError.serviceUnreachable(hint: "Config written but Kanata reload failed. Run 'keypath service reload' once Kanata is running.")
            CLIOutput.writeError(error, context: context)
            throw error.code.exitCode
        }
    } else {
        CLIOutput.progress("Run 'keypath config apply' to regenerate config and reload Kanata.", context: context)
    }
}

func formatInstallerReport(_ report: CLIInstallerReport, title: String, noColor: Bool = false) -> String {
    var lines: [String] = []
    lines.append(ANSIColor.bold("=== \(title) Report ===", noColor: noColor))
    let successText = report.success
        ? ANSIColor.green("Yes", noColor: noColor)
        : ANSIColor.red("No", noColor: noColor)
    lines.append("Success: \(successText)")

    if let reason = report.failureReason {
        lines.append(ANSIColor.red("Failure Reason: \(reason)", noColor: noColor))
    }

    if !report.steps.isEmpty {
        lines.append("")
        lines.append("Steps:")
        for step in report.steps {
            let marker = step.success
                ? ANSIColor.green("✓", noColor: noColor)
                : ANSIColor.red("✗", noColor: noColor)
            lines.append("  \(marker) \(step.name)")
            if let error = step.error {
                lines.append(ANSIColor.dim("         \(error)", noColor: noColor))
            }
        }
    }
    return lines.joined(separator: "\n")
}
