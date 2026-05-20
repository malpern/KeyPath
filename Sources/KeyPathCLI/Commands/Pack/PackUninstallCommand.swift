import ArgumentParser
import Foundation
import KeyPathAppKit

struct PackUninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall a pack"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Pack name, slug, or ID (e.g., 'vim-navigation', 'Home Row Mods')")
    var nameOrId: String

    @Flag(help: "Regenerate config and reload Kanata after uninstalling")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let spinner = CLISpinner(context: ctx)

        do {
            if !globals.dryRun {
                spinner.start("Uninstalling '\(nameOrId)'...")
            }

            let result = try await facade.uninstallPack(
                nameOrId: nameOrId,
                dryRun: globals.dryRun
            )

            switch result.action {
            case "not-installed":
                spinner.stop()
            case "would-uninstall":
                break
            default:
                spinner.succeed("Uninstalled '\(result.packName)'")
            }

            CLIOutput.write(result, context: ctx) {
                switch result.action {
                case "not-installed":
                    return "Pack '\(result.packName)' is not installed."
                case "would-uninstall":
                    return "Would uninstall '\(result.packName)'"
                default:
                    return ""
                }
            }

            if result.action == "uninstalled" {
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
        } catch let installErr as PackInstaller.InstallError {
            spinner.fail("Uninstall failed")
            let error = CLIError.validation(installErr.errorDescription ?? installErr.localizedDescription)
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
