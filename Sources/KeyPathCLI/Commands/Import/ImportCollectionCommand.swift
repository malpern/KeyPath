import ArgumentParser
import Foundation
import KeyPathAppKit

struct ImportCollection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collection",
        abstract: "Import a collection from a JSON file"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Path to the JSON file to import")
    var path: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CollectionsFacade()

        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let cliError = CLIError.validation(
                "Cannot read file: \(url.path)",
                hint: "Check that the file exists and is readable"
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        let exported: CLIExportedCollection
        do {
            exported = try JSONDecoder().decode(CLIExportedCollection.self, from: data)
        } catch {
            let cliError = CLIError.validation(
                "Invalid collection JSON",
                hint: "File must be a KeyPath collection export (from 'keypath export collection')",
                details: [error.localizedDescription]
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        let conflictStrategy: CLIConflictStrategy = switch globals.onConflict {
        case .fail: .fail
        case .replace, .merge: .replace
        case .skip: .skip
        }

        if globals.dryRun {
            CLIOutput.write(exported, context: ctx) {
                "Would import: \(exported.name) (\(exported.mappings.count) mappings, layer: \(exported.targetLayer))"
            }
            return
        }

        do {
            let result = try await facade.importCollection(exported, onConflict: conflictStrategy)
            CLIOutput.write(result, context: ctx) {
                "Imported collection: \(result.name) (\(result.mappingCount) mappings)"
            }
        } catch let error as AmbiguousCollectionMatch {
            let cliError = CLIError.conflict(
                "Collection '\(exported.name)' already exists",
                hint: "Use --on-conflict=replace to overwrite, or --on-conflict=skip to no-op"
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }
    }
}
