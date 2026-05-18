import ArgumentParser
import Foundation
import KeyPathAppKit

struct ImportKarabiner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "karabiner",
        abstract: "Import rules from a Karabiner-Elements configuration"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Path to karabiner.json or complex_modifications rule file")
    var path: String

    @Option(name: .customLong("collection"), help: "Merge all rules into a single collection with this name")
    var collectionName: String?

    @Option(name: .customLong("profile"), help: "Profile index to import (default: selected profile)")
    var profileIndex: Int?

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

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

        let importResult: CLIKarabinerImportResult
        do {
            importResult = try facade.importFromKarabiner(
                data: data,
                collectionName: collectionName,
                profileIndex: profileIndex
            )
        } catch {
            let cliError = CLIError.validation(
                "Failed to parse Karabiner configuration: \(error.localizedDescription)",
                hint: "Ensure the file is a valid Karabiner-Elements JSON configuration"
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }

        if globals.dryRun {
            CLIOutput.write(importResult, context: ctx) {
                formatDryRunOutput(importResult)
            }
            return
        }

        let conflictStrategy: CLIConflictStrategy = switch globals.onConflict {
        case .fail: .fail
        case .replace, .merge: .replace
        case .skip: .skip
        }

        var importedCollections: [CLIRuleCollection] = []
        for exported in importResult.collections {
            do {
                let imported = try await facade.importCollection(exported, onConflict: conflictStrategy)
                importedCollections.append(imported)
            } catch is AmbiguousCollectionMatch {
                let cliError = CLIError.conflict(
                    "Collection '\(exported.name)' already exists",
                    hint: "Use --on-conflict=replace to overwrite, or --on-conflict=skip to no-op"
                )
                CLIOutput.writeError(cliError, context: ctx)
                throw CLIExitCode.conflict.exitCode
            }
        }

        CLIOutput.write(importResult, context: ctx) {
            formatImportOutput(importResult, importedCollections: importedCollections)
        }
    }

    private func formatDryRunOutput(_ result: CLIKarabinerImportResult) -> String {
        let totalMappings = result.collections.map(\.mappings.count).reduce(0, +)
        var lines: [String] = []
        lines.append("Karabiner import preview (profile: \(result.profileName)):")
        lines.append("  \(result.collections.count) collection(s), \(totalMappings) mapping(s)")
        for col in result.collections {
            lines.append("  - \(col.name) (\(col.mappings.count) mappings)")
        }
        appendSkippedAndWarnings(result, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func formatImportOutput(_ result: CLIKarabinerImportResult, importedCollections: [CLIRuleCollection]) -> String {
        var lines: [String] = []
        lines.append("Imported \(importedCollections.count) collection(s) from Karabiner profile '\(result.profileName)':")
        for col in importedCollections {
            lines.append("  + \(col.name) (\(col.mappingCount) mappings)")
        }
        appendSkippedAndWarnings(result, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func appendSkippedAndWarnings(_ result: CLIKarabinerImportResult, to lines: inout [String]) {
        if !result.skippedRules.isEmpty {
            lines.append("\(result.skippedRules.count) rule(s) skipped:")
            for skipped in result.skippedRules {
                lines.append("  - \(skipped.description): \(skipped.reason)")
            }
        }
        if !result.warnings.isEmpty {
            for warning in result.warnings {
                lines.append("Warning: \(warning)")
            }
        }
    }
}
