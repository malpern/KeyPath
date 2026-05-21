import ArgumentParser
import Foundation
import KeyPathAppKit

struct PackConfigure: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "configure",
        abstract: "Update quick settings on an installed pack"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Pack name, slug, or ID (e.g., 'home-row-mods')")
    var nameOrId: String

    @Option(name: .customLong("setting"), help: "Quick setting value (key=value, repeatable)")
    var settings: [String] = []

    @Flag(help: "Regenerate config and reload Kanata after configuring")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext

        guard !settings.isEmpty else {
            let error = CLIError.validation(
                "No settings provided",
                hint: "Use --setting key=value (e.g., --setting holdTimeout=250)"
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        var settingValues: [String: Int] = [:]
        for setting in settings {
            let parts = setting.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Int(parts[1]) else {
                let error = CLIError.validation(
                    "Invalid setting format: '\(setting)'",
                    hint: "Use key=value format, e.g., --setting holdTimeout=250"
                )
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            settingValues[String(parts[0])] = value
        }

        let facade = PacksFacade()

        do {
            let result = try await facade.configurePack(
                nameOrId: nameOrId,
                settingValues: settingValues,
                dryRun: globals.dryRun
            )

            CLIOutput.write(result, context: ctx) {
                switch result.action {
                case "not-installed":
                    return "Pack '\(result.packName)' is not installed. Install it first with 'keypath pack install \(nameOrId)'."
                case "would-configure":
                    let pairs = result.quickSettingValues.map { "\($0.key)=\($0.value)" }
                    return "Would configure '\(result.packName)': \(pairs.joined(separator: ", "))"
                default:
                    let pairs = result.quickSettingValues.map { "\($0.key)=\($0.value)" }
                    return "Configured '\(result.packName)': \(pairs.joined(separator: ", "))"
                }
            }

            if result.action == "configured" {
                try await applyConfigurationOrHint(apply: apply, context: ctx)
            }
        } catch let notFound as CLIPackNotFound {
            let allPacks = await facade.listPacks()
            let candidates = allPacks.flatMap { [$0.name, $0.id.replacingOccurrences(of: "com.keypath.pack.", with: "")] }
            let suggestions = FuzzyMatch.suggestions(for: notFound.query, from: candidates)
            let error = CLIError.notFound("Pack", query: notFound.query, listCommand: "keypath pack list", suggestions: suggestions)
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let ambiguous as AmbiguousPackMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let settingErr as CLIPackSettingError {
            let error = CLIError.validation(settingErr.description)
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
