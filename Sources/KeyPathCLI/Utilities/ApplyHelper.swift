import ArgumentParser
import Foundation
import KeyPathAppKit

func applyConfigurationOrHint(facade: CLIFacade, apply: Bool, context: OutputContext) async throws {
    if apply {
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

func formatInstallerReport(_ report: CLIInstallerReport, title: String) -> String {
    var lines: [String] = []
    lines.append("=== \(title) Report ===")
    lines.append("Success: \(report.success ? "Yes" : "No")")

    if let reason = report.failureReason {
        lines.append("Failure Reason: \(reason)")
    }

    if !report.steps.isEmpty {
        lines.append("")
        lines.append("Steps:")
        for step in report.steps {
            let status = step.success ? "OK" : "FAIL"
            lines.append("  [\(status)] \(step.name)")
            if let error = step.error {
                lines.append("         \(error)")
            }
        }
    }
    return lines.joined(separator: "\n")
}
