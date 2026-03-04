import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Rules: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage rule collections",
            subcommands: [
                List.self,
                Enable.self,
                Disable.self,
                Show.self,
            ]
        )

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List all rule collections"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let collections = await facade.loadRuleCollections()

                if collections.isEmpty {
                    print("No rule collections found.")
                    return
                }

                print("Rule Collections:")
                print(String(repeating: "-", count: 60))
                for collection in collections {
                    let status = collection.isEnabled ? "✓" : "✗"
                    print("  [\(status)] \(collection.name) (\(collection.mappingCount) rules) — id: \(collection.id)")
                }
            }
        }

        struct Enable: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Enable a rule collection"
            )

            @Argument(help: "Collection name or ID")
            var nameOrId: String

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                guard let name = try await facade.enableCollection(nameOrId: nameOrId) else {
                    print("Collection '\(nameOrId)' not found.")
                    throw ExitCode.failure
                }
                print("Enabled '\(name)'")
                print("Run 'keypath apply' to regenerate config and reload Kanata.")
            }
        }

        struct Disable: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Disable a rule collection"
            )

            @Argument(help: "Collection name or ID")
            var nameOrId: String

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                guard let name = try await facade.disableCollection(nameOrId: nameOrId) else {
                    print("Collection '\(nameOrId)' not found.")
                    throw ExitCode.failure
                }
                print("Disabled '\(name)'")
                print("Run 'keypath apply' to regenerate config and reload Kanata.")
            }
        }

        struct Show: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show details of a rule collection"
            )

            @Argument(help: "Collection name or ID")
            var nameOrId: String

            @Flag(help: "Output as JSON")
            var json: Bool = false

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }

                guard let collection = await facade.showCollection(nameOrId: nameOrId) else {
                    print("Collection '\(nameOrId)' not found.")
                    throw ExitCode.failure
                }

                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(collection)
                    print(String(data: data, encoding: .utf8) ?? "")
                } else {
                    print("Name: \(collection.name)")
                    print("ID: \(collection.id)")
                    print("Enabled: \(collection.isEnabled)")
                    print("Mappings: \(collection.mappingCount)")
                    print("Summary: \(collection.summary)")
                }
            }
        }
    }
}
