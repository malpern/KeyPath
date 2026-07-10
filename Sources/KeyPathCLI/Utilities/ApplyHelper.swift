import ArgumentParser
import Foundation
import KeyPathAppKit
import KeyPathCLISupport

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
    if let completionState = report.completionState {
        lines.append("Completion State: \(completionState)")
    }
    if let runID = report.runID {
        lines.append(ANSIColor.dim("Run ID: \(runID)", noColor: noColor))
    }

    if let reason = report.failureReason {
        lines.append(ANSIColor.red("Failure Reason: \(reason)", noColor: noColor))
    }

    if report.dryRun == true {
        lines.append("Dry Run: Yes")
    }
    if report.userActionRequired == true {
        lines.append("User Action Required: Yes")
    }

    if let plannedRecipes = report.plannedRecipes, !plannedRecipes.isEmpty {
        lines.append("")
        lines.append("Planned Recipes:")
        for recipe in plannedRecipes {
            lines.append("  - \(recipe)")
        }
    }

    if let unmetRequirements = report.unmetRequirements, !unmetRequirements.isEmpty {
        lines.append("")
        lines.append("Unmet Requirements:")
        for requirement in unmetRequirements {
            lines.append("  - \(requirement)")
        }
    }

    if let failedPostconditions = report.failedPostconditions, !failedPostconditions.isEmpty {
        lines.append("")
        lines.append("Failed Postconditions:")
        for postcondition in failedPostconditions {
            lines.append("  - \(postcondition)")
        }
    }

    if let recoveryRecipes = report.recoveryPlanRecipes, !recoveryRecipes.isEmpty {
        lines.append("")
        lines.append("Recommended Recovery Plan:")
        for recipe in recoveryRecipes {
            lines.append("  - \(recipe)")
        }
    }

    if let issues = report.issues, !issues.isEmpty {
        lines.append("")
        lines.append("Issues:")
        for issue in issues {
            let fixability = issue.canAutoFix ? "auto-fixable" : "manual"
            lines.append("  - \(issue.title) [\(issue.category), \(fixability)]")
            lines.append("    Action: \(issue.action)")
            if let url = issue.remediationURL {
                lines.append("    Open: \(url)")
            }
        }
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
