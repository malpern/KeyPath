import ArgumentParser
import Foundation
import KeyPathAppKit

struct HelpSchemas: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schemas",
        abstract: "List available CLI schemas for agent API discovery"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Schema noun to inspect (e.g., action, behavior, rule, collection)")
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
                    lines.append("")
                    lines.append("JSON examples:")
                    lines.append(#"  {"keystroke":{"key":"esc"}}"#)
                    lines.append(#"  {"hyper":{}}"#)
                    lines.append(#"  {"launchApp":{"name":"Safari","bundleId":"com.apple.Safari"}}"#)
                    lines.append(#"  {"openURL":{"_0":"https://example.com"}}"#)
                    lines.append(#"  {"rawKanata":{"_0":"(multi lctl c)"}}"#)
                    return lines.joined(separator: "\n")
                }
            case "behavior":
                let schemas = MappingBehavior.allSchemaDescriptions
                CLIOutput.write(schemas, context: ctx) {
                    var lines = ["Behavior Schemas:"]
                    for schema in schemas {
                        lines.append("  \(schema.name) — \(schema.description)")
                    }
                    lines.append("")
                    lines.append("JSON examples:")
                    lines.append(#"  {"dualRole":{"tapAction":{"keystroke":{"key":"a"}},"holdAction":{"keystroke":{"key":"lctl"}},"tapTimeout":200,"holdTimeout":200,"activateHoldOnOtherKey":true}}"#)
                    lines.append(#"  {"macro":{"text":"hello","outputs":[],"source":"text"}}"#)
                    lines.append(#"  {"chord":{"keys":["j","k"],"output":{"keystroke":{"key":"esc"}},"timeout":200}}"#)
                    return lines.joined(separator: "\n")
                }
            case "rule":
                if ctx.shouldOutputJSON {
                    CLIOutput.writeJSON(CLISchemas.ruleAdd)
                    return
                }
                let schema = RuleSchema.description
                CLIOutput.write(schema, context: ctx) {
                    var lines = ["Rule Add Schema:"]
                    lines.append("")
                    lines.append("Required:")
                    lines.append("  <input>               Input key (positional argument)")
                    lines.append("")
                    lines.append("Output modes (pick one):")
                    lines.append("  <output>              Simple remap (positional argument)")
                    lines.append("  --action <json>       Full KeyAction JSON")
                    lines.append("  --tap/--hold          Tap-hold shorthand")
                    lines.append("  --behavior <json>     Full MappingBehavior JSON")
                    lines.append("")
                    lines.append("Optional:")
                    lines.append("  --shifted <key>       Alternate output when shift held")
                    lines.append("  --layer <name>        Target layer (default: base)")
                    lines.append("  --title <text>        Human-readable title")
                    lines.append("  --notes <text>        Description/notes")
                    lines.append("  --timeout <ms>        Tap-hold timeout (default: 200)")
                    lines.append("")
                    lines.append("Flags:")
                    lines.append("  --dry-run             Preview without saving")
                    lines.append("  --on-conflict <s>     fail|replace|skip|merge (default: fail)")
                    lines.append("  --apply               Regenerate config after saving")
                    return lines.joined(separator: "\n")
                }
            case "collection":
                if ctx.shouldOutputJSON {
                    CLIOutput.writeJSON(CLISchemas.collectionToggle)
                    return
                }
                let schema = CollectionSchema.description
                CLIOutput.write(schema, context: ctx) {
                    var lines = ["Collection Schema:"]
                    lines.append("")
                    lines.append("Commands:")
                    lines.append("  create <name> [--category <cat>] [--summary <text>]")
                    lines.append("  rename <nameOrId> <newName>")
                    lines.append("  delete <nameOrId> [--force]")
                    lines.append("  duplicate <nameOrId> [--name <newName>]")
                    lines.append("  reorder <nameOrId> --position <index>")
                    lines.append("")
                    lines.append("Categories: custom, productivity, navigation, layers, accessibility, experimental")
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
                SchemaOverview(name: "rule", description: "Rule add command schema and options"),
                SchemaOverview(name: "collection", description: "Collection CRUD command schema"),
            ]
            CLIOutput.write(overview, context: ctx) {
                let lines = [
                    "Available Schemas:",
                    "  action     — All KeyAction variants (key, hyper, launch-app, etc.)",
                    "  behavior   — All MappingBehavior variants (tap-hold, tap-dance, macro, chord)",
                    "  rule       — Rule add command schema and options",
                    "  collection — Collection CRUD command schema",
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

private struct RuleSchema: Codable {
    static let description = RuleSchema(
        fields: ["input", "output|action|tap+hold|behavior", "shifted", "layer", "title", "notes"],
        conflictStrategies: ["fail", "replace", "skip"]
    )
    let fields: [String]
    let conflictStrategies: [String]
}

private struct CollectionSchema: Codable {
    static let description = CollectionSchema(
        commands: ["create", "rename", "delete", "duplicate", "reorder"],
        categories: ["custom", "productivity", "navigation", "layers", "accessibility", "experimental"]
    )
    let commands: [String]
    let categories: [String]
}

// MARK: - JSON Schema Types (for agent consumption)

struct JSONSchemaProperty: Codable {
    let type: String
    let description: String
    let `enum`: [String]?
    let `default`: String?

    init(type: String, description: String, enum: [String]? = nil, default: String? = nil) {
        self.type = type
        self.description = description
        self.enum = `enum`
        self.default = `default`
    }
}

struct JSONSchema: Codable {
    let name: String
    let description: String
    let properties: [String: JSONSchemaProperty]
    let required: [String]
}

enum CLISchemas {
    static let ruleAdd = JSONSchema(
        name: "rule.add",
        description: "Add or update a custom key remapping",
        properties: [
            "input": JSONSchemaProperty(type: "string", description: "Input key (kanata name, e.g., caps, a, lalt, spc)"),
            "output": JSONSchemaProperty(type: "string", description: "Output key for simple remap"),
            "action": JSONSchemaProperty(type: "object", description: "Full KeyAction JSON (alternative to output)"),
            "behavior": JSONSchemaProperty(type: "object", description: "Full MappingBehavior JSON"),
            "tap": JSONSchemaProperty(type: "string", description: "Tap output for tap-hold shorthand"),
            "hold": JSONSchemaProperty(type: "string", description: "Hold output for tap-hold shorthand"),
            "timeout": JSONSchemaProperty(type: "integer", description: "Tap-hold timeout in ms", default: "200"),
            "shifted": JSONSchemaProperty(type: "string", description: "Alternate output when shift held"),
            "layer": JSONSchemaProperty(type: "string", description: "Target layer", default: "base"),
            "title": JSONSchemaProperty(type: "string", description: "Human-readable title"),
            "notes": JSONSchemaProperty(type: "string", description: "Description/notes"),
            "on-conflict": JSONSchemaProperty(type: "string", description: "Conflict resolution strategy", enum: ["fail", "replace", "skip", "merge"], default: "fail"),
            "dry-run": JSONSchemaProperty(type: "boolean", description: "Preview without saving", default: "false"),
            "apply": JSONSchemaProperty(type: "boolean", description: "Regenerate config after saving", default: "false"),
        ],
        required: ["input"]
    )

    static let packInstall = JSONSchema(
        name: "pack.install",
        description: "Install a keyboard pack",
        properties: [
            "name-or-id": JSONSchemaProperty(type: "string", description: "Pack name, slug, or full ID"),
            "setting": JSONSchemaProperty(type: "string", description: "Quick setting as key=value (repeatable)"),
            "apply": JSONSchemaProperty(type: "boolean", description: "Reload Kanata after installing", default: "false"),
            "dry-run": JSONSchemaProperty(type: "boolean", description: "Preview without installing", default: "false"),
        ],
        required: ["name-or-id"]
    )

    static let collectionToggle = JSONSchema(
        name: "collection.enable",
        description: "Enable or disable a rule collection",
        properties: [
            "name-or-id": JSONSchemaProperty(type: "string", description: "Collection name or UUID"),
            "apply": JSONSchemaProperty(type: "boolean", description: "Reload Kanata after toggling", default: "false"),
        ],
        required: ["name-or-id"]
    )
}
