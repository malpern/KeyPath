import ArgumentParser
import Foundation
import KeyPathAppKit

struct HelpSchemas: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schemas",
        abstract: "List available CLI schemas for agent API discovery"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Schema noun to inspect (e.g., action, behavior)")
    var noun: String?

    mutating func run() async throws {
        let ctx = globals.outputContext

        if let noun {
            switch noun.lowercased() {
            case "action":
                let schemas = KeyAction.allSchemaDescriptions
                CLIOutput.write(schemas, context: ctx) {
                    var lines = ["Action Schemas:"]
                    for schema in schemas {
                        lines.append("  \(schema.name) — \(schema.description)")
                    }
                    return lines.joined(separator: "\n")
                }
            case "behavior":
                let schemas = MappingBehavior.allSchemaDescriptions
                CLIOutput.write(schemas, context: ctx) {
                    var lines = ["Behavior Schemas:"]
                    for schema in schemas {
                        lines.append("  \(schema.name) — \(schema.description)")
                    }
                    return lines.joined(separator: "\n")
                }
            default:
                let error = CLIError.notFound("Schema", query: noun, listCommand: "keypath help-topics schemas")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
        } else {
            let overview = [
                SchemaOverview(name: "action", description: "All KeyAction variants (key, hyper, launch-app, etc.)"),
                SchemaOverview(name: "behavior", description: "All MappingBehavior variants (tap-hold, tap-dance, macro, chord)"),
            ]
            CLIOutput.write(overview, context: ctx) {
                var lines = [
                    "Available Schemas:",
                    "  action   — All KeyAction variants (key, hyper, launch-app, etc.)",
                    "  behavior — All MappingBehavior variants (tap-hold, tap-dance, macro, chord)",
                    "",
                    "Run 'keypath help-topics schemas <name>' for details.",
                ]
                return lines.joined(separator: "\n")
            }
        }
    }
}

private struct SchemaOverview: Codable {
    let name: String
    let description: String
}
