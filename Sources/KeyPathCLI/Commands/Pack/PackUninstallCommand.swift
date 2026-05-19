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

        do {
            let result = try await facade.uninstallPack(
                nameOrId: nameOrId,
                dryRun: globals.dryRun
            )

            CLIOutput.write(result, context: ctx) {
                switch result.action {
                case "not-installed":
                    return "Pack '\(result.packName)' is not installed."
                case "would-uninstall":
                    return "Would uninstall '\(result.packName)'"
                default:
                    return "Uninstalled '\(result.packName)'"
                }
            }

            if result.action == "uninstalled" {
                try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
            }
        } catch let notFound as CLIPackNotFound {
            let error = CLIError.notFound("Pack", query: notFound.query, listCommand: "keypath pack list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let ambiguous as AmbiguousPackMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        } catch let installErr as PackInstaller.InstallError {
            let error = CLIError.validation(installErr.errorDescription ?? installErr.localizedDescription)
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }
    }
}
