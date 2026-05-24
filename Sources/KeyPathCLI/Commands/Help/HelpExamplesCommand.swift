import ArgumentParser
import Foundation

struct HelpExamples: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "examples",
        abstract: "Curated workflow examples for each command noun"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Noun to show examples for (rule, collection, layer, service, config, system)")
    var noun: String?

    mutating func run() async throws {
        let ctx = globals.outputContext

        if let noun {
            guard let examples = Self.examplesByNoun[noun.lowercased()] else {
                let error = CLIError.notFound(
                    "Examples",
                    query: noun,
                    listCommand: "keypath help-topics examples"
                )
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            CLIOutput.write(examples, context: ctx) {
                var lines = ["Examples: \(noun)"]
                lines.append("")
                for example in examples {
                    lines.append("  # \(example.description)")
                    for cmd in example.commands {
                        lines.append("  \(cmd)")
                    }
                    lines.append("")
                }
                return lines.joined(separator: "\n")
            }
        } else {
            let nouns = Self.examplesByNoun.keys.sorted()
            let overview = nouns.map { ExampleOverview(name: $0, count: Self.examplesByNoun[$0]!.count) }
            CLIOutput.write(overview, context: ctx) {
                var lines = ["Available Example Topics:"]
                for noun in nouns {
                    let count = Self.examplesByNoun[noun]!.count
                    lines.append("  \(noun.padding(toLength: 12, withPad: " ", startingAt: 0))— \(count) examples")
                }
                lines.append("")
                lines.append("Run 'keypath help-topics examples <noun>' for details.")
                return lines.joined(separator: "\n")
            }
        }
    }

    // MARK: - Example Data

    private static let examplesByNoun: [String: [ExampleEntry]] = [
        "rule": ruleExamples,
        "collection": collectionExamples,
        "layer": layerExamples,
        "service": serviceExamples,
        "config": configExamples,
        "system": systemExamples,
    ]

    private static let ruleExamples: [ExampleEntry] = [
        ExampleEntry(
            description: "Map Caps Lock to Escape",
            commands: ["keypath rule add caps esc --apply"]
        ),
        ExampleEntry(
            description: "Add home row mods (A=Ctrl, S=Alt, D=Cmd, F=Shift)",
            commands: [
                "keypath rule add a --tap a --hold lctl --apply",
                "keypath rule add s --tap s --hold lalt --apply",
                "keypath rule add d --tap d --hold lmet --apply",
                "keypath rule add f --tap f --hold lsft --apply",
            ]
        ),
        ExampleEntry(
            description: "Map a key to Hyper (Ctrl+Alt+Cmd+Shift)",
            commands: [#"keypath rule add caps --action '{"hyper":{}}' --apply"#]
        ),
        ExampleEntry(
            description: "Launch an app with a key",
            commands: [#"keypath rule add f1 --action '{"launchApp":{"name":"Safari","bundleId":"com.apple.Safari"}}' --apply"#]
        ),
        ExampleEntry(
            description: "Create a tap-dance (single=Esc, double=Caps Lock)",
            commands: [#"keypath rule add caps --behavior '{"tapOrTapDance":{"tapDance":{"windowMs":200,"steps":[{"label":"Esc","action":{"keystroke":{"key":"esc"}}},{"label":"Caps","action":{"keystroke":{"key":"caps"}}}]}}}' --apply"#]
        ),
        ExampleEntry(
            description: "Preview a rule without saving",
            commands: ["keypath rule add caps esc --dry-run"]
        ),
        ExampleEntry(
            description: "Replace an existing rule",
            commands: ["keypath rule add caps esc --on-conflict replace --apply"]
        ),
        ExampleEntry(
            description: "List all rules as JSON (for piping)",
            commands: ["keypath rule list --json"]
        ),
    ]

    private static let collectionExamples: [ExampleEntry] = [
        ExampleEntry(
            description: "Create a collection for vim keybindings",
            commands: [#"keypath collection create "Vim Keys" --category navigation --summary "Vim-style navigation on base layer""#]
        ),
        ExampleEntry(
            description: "Duplicate and modify a collection",
            commands: [
                #"keypath collection duplicate "Home Row Mods" --name "HRM Experimental""#,
                #"keypath collection disable "Home Row Mods""#,
            ]
        ),
        ExampleEntry(
            description: "Export a collection, edit, and reimport",
            commands: [
                #"keypath export collection "Vim Keys" --output vim.json"#,
                "# (edit vim.json)",
                "keypath import collection vim.json --on-conflict replace",
            ]
        ),
        ExampleEntry(
            description: "Reorder collections (affects config priority)",
            commands: [#"keypath collection reorder "Vim Keys" --position 0"#]
        ),
        ExampleEntry(
            description: "Show full details of a collection",
            commands: ["keypath collection show home-row --json"]
        ),
    ]

    private static let layerExamples: [ExampleEntry] = [
        ExampleEntry(
            description: "Create a navigation layer",
            commands: [
                #"keypath layer create nav"#,
                #"keypath rule add h --action '{"keystroke":{"key":"left"}}' --layer nav --apply"#,
                #"keypath rule add j --action '{"keystroke":{"key":"down"}}' --layer nav --apply"#,
                #"keypath rule add k --action '{"keystroke":{"key":"up"}}' --layer nav --apply"#,
                #"keypath rule add l --action '{"keystroke":{"key":"right"}}' --layer nav --apply"#,
            ]
        ),
        ExampleEntry(
            description: "Check which layer is active",
            commands: ["keypath layer current"]
        ),
        ExampleEntry(
            description: "Switch to a layer at runtime",
            commands: ["keypath layer switch nav"]
        ),
        ExampleEntry(
            description: "List all defined layers",
            commands: ["keypath layer list --json"]
        ),
    ]

    private static let serviceExamples: [ExampleEntry] = [
        ExampleEntry(
            description: "Check if Kanata is running",
            commands: ["keypath service status"]
        ),
        ExampleEntry(
            description: "Restart after config changes",
            commands: ["keypath service restart"]
        ),
        ExampleEntry(
            description: "View recent logs",
            commands: ["keypath service logs --lines 50"]
        ),
        ExampleEntry(
            description: "Full restart cycle",
            commands: [
                "keypath service stop",
                "keypath config apply",
                "keypath service start",
            ]
        ),
    ]

    private static let configExamples: [ExampleEntry] = [
        ExampleEntry(
            description: "View the generated Kanata config",
            commands: ["keypath config show"]
        ),
        ExampleEntry(
            description: "Validate config without applying",
            commands: ["keypath config check"]
        ),
        ExampleEntry(
            description: "Apply changes and reload",
            commands: ["keypath config apply"]
        ),
        ExampleEntry(
            description: "Find the config file path",
            commands: ["keypath config path"]
        ),
    ]

    private static let systemExamples: [ExampleEntry] = [
        ExampleEntry(
            description: "Check system health before installing",
            commands: ["keypath system inspect --json"]
        ),
        ExampleEntry(
            description: "Full install flow",
            commands: [
                "keypath system inspect",
                "keypath system install",
                "keypath service status",
            ]
        ),
        ExampleEntry(
            description: "Repair a broken installation",
            commands: ["keypath system repair"]
        ),
        ExampleEntry(
            description: "Clean uninstall (keeps config files)",
            commands: ["keypath system uninstall"]
        ),
    ]
}

private struct ExampleEntry: Codable {
    let description: String
    let commands: [String]
}

private struct ExampleOverview: Codable {
    let name: String
    let count: Int
}
