import ArgumentParser
import Foundation
import KeyPathAppKit

struct PackInstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a pack"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Pack name, slug, or ID (e.g., 'vim-navigation', 'Home Row Mods')")
    var nameOrId: String

    @Option(name: .customLong("setting"), help: "Quick setting value (key=value, repeatable)")
    var settings: [String] = []

    @Flag(help: "Regenerate config and reload Kanata after installing")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext

        var settingValues: [String: Int] = [:]
        for setting in settings {
            let parts = setting.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Int(parts[1]) else {
                let error = CLIError.validation(
                    "Invalid setting format: '\(setting)'",
                    hint: "Use key=value format, e.g., --setting holdTimeout=200"
                )
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            settingValues[String(parts[0])] = value
        }

        let facade = await MainActor.run { CLIFacade() }
        let spinner = CLISpinner(context: ctx)

        do {
            if !globals.dryRun {
                spinner.start("Installing '\(nameOrId)'...")
            }

            let result = try await facade.installPack(
                nameOrId: nameOrId,
                settingValues: settingValues,
                dryRun: globals.dryRun
            )

            switch result.action {
            case "already-installed":
                spinner.stop()
            case "would-install":
                break
            default:
                spinner.succeed("Installed '\(result.packName)'")
            }

            CLIOutput.write(result, context: ctx) {
                switch result.action {
                case "already-installed":
                    return "Pack '\(result.packName)' is already installed."
                case "would-install":
                    var lines = ["Would install '\(result.packName)'"]
                    if !result.quickSettingValues.isEmpty {
                        let pairs = result.quickSettingValues.map { "\($0.key)=\($0.value)" }
                        lines.append("  Settings: \(pairs.joined(separator: ", "))")
                    }
                    for warning in result.warnings {
                        lines.append("  \(warning)")
                    }
                    return lines.joined(separator: "\n")
                default:
                    var lines: [String] = []
                    if !result.quickSettingValues.isEmpty {
                        let pairs = result.quickSettingValues.map { "\($0.key)=\($0.value)" }
                        lines.append("  Settings: \(pairs.joined(separator: ", "))")
                    }
                    for warning in result.warnings {
                        lines.append("  \(warning)")
                    }
                    return lines.isEmpty ? "" : lines.joined(separator: "\n")
                }
            }

            if result.action == "installed" {
                try await applyConfigurationOrHint(apply: apply, context: ctx)
            }
        } catch let notFound as CLIPackNotFound {
            spinner.fail("Pack not found: '\(notFound.query)'")
            let allPacks = await facade.listPacks()
            let candidates = allPacks.flatMap { [$0.name, $0.id.replacingOccurrences(of: "com.keypath.pack.", with: "")] }
            let suggestions = FuzzyMatch.suggestions(for: notFound.query, from: candidates)
            let error = CLIError.notFound("Pack", query: notFound.query, listCommand: "keypath pack list", suggestions: suggestions)
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let ambiguous as AmbiguousPackMatch {
            spinner.fail("Ambiguous pack name")
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let settingErr as CLIPackSettingError {
            spinner.fail("Invalid setting")
            let error = CLIError.validation(settingErr.description)
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let installErr as PackInstaller.InstallError {
            spinner.fail("Install failed")
            let error: CLIError
            switch installErr {
            case .mutuallyExclusive:
                error = CLIError.conflict(
                    installErr.errorDescription ?? installErr.localizedDescription,
                    hint: "Uninstall the conflicting pack first"
                )
            case let .dependencyMissing(name, _):
                error = CLIError.validation(
                    installErr.errorDescription ?? installErr.localizedDescription,
                    hint: "Install \(name) first"
                )
            default:
                error = CLIError.validation(installErr.errorDescription ?? installErr.localizedDescription)
            }
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
