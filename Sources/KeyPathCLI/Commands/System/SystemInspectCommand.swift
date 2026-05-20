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
        let facade = await MainActor.run { CLIFacade() }
        let result = await facade.runInspect()

        CLIOutput.write(result, context: ctx) {
            var lines = [
                "=== System Inspection ===",
                "macOS Version: \(result.macOSVersion)",
                "Driver Compatible: \(result.driverCompatible ? "Yes" : "No")",
                "",
                "Plan Status: \(result.planStatus)",
            ]
            if let blockedBy = result.blockedBy {
                lines.append("Blocked By: \(blockedBy)")
            }
            if !result.plannedRecipes.isEmpty {
                lines.append("")
                lines.append("Planned Recipes:")
                for recipe in result.plannedRecipes {
                    lines.append("  - \(recipe)")
                }
            }
            lines.append("")
            lines.append("No changes were made to the system.")
            return lines.joined(separator: "\n")
        }
    }
}
