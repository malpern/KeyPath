import ArgumentParser
import Foundation
import KeyPathAppKit

struct SystemInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect system state without making changes"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = SystemFacade()
        let result: CLIInspectResult
        do {
            result = try await withThrowingTimeout(seconds: globals.timeout) {
                await facade.runInspect()
            }
        } catch is TimeoutError {
            let error = CLIError.serviceUnreachable(hint: "System inspection timed out. Try --timeout \(globals.timeout * 2)")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(result, context: ctx) {
            var lines = [
                "=== System Inspection ===",
                "macOS Version: \(result.macOSVersion)",
                "Driver Compatible: \(result.driverCompatible ? "Yes" : "No")",
                "",
                "System Ready: \((result.isOperational ?? false) ? "Yes" : "No")",
                "Plan Status: \(result.planStatus)",
            ]
            if let intent = result.planIntent {
                lines.append("Plan Intent: \(intent)")
            }
            if let blockedBy = result.blockedBy {
                lines.append("Blocked By: \(blockedBy)")
            }
            if result.promptsNeeded == true {
                lines.append("Prompts Needed: Yes")
            }
            if !result.plannedRecipes.isEmpty {
                lines.append("")
                lines.append("Planned Recipes:")
                for recipe in result.plannedRecipes {
                    lines.append("  - \(recipe)")
                }
            }
            if let issues = result.issues, !issues.isEmpty {
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
            lines.append("")
            lines.append("No changes were made to the system.")
            return lines.joined(separator: "\n")
        }
    }
}
