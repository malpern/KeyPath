import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigRestore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore the KeyPath config directory from a backup"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Backup directory previously created by 'keypath config backup'")
    var backupPath: String

    @Flag(name: .customLong("reload"), help: "Ask the running Kanata service to reload after restore")
    var reload: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = ConfigFacade()

        do {
            let result = try await facade.restoreConfig(from: backupPath, reload: reload)
            CLIOutput.write(result, context: ctx) {
                var lines = [
                    "Config restored: \(result.restoredPath)",
                    "Source: \(result.sourcePath)",
                    "Items: \(result.restoredItems.isEmpty ? "none" : result.restoredItems.joined(separator: ", "))",
                ]
                if result.reloadRequested {
                    lines.append(result.reloadSuccess == true ? "Kanata reload requested successfully." : "Kanata reload failed.")
                }
                return lines.joined(separator: "\n")
            }

            if result.reloadRequested, result.reloadSuccess != true {
                throw CLIExitCode.serviceUnreachable.exitCode
            }
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            let cliError = CLIError.validation(
                "Config restore failed",
                hint: "Pass a backup directory created by 'keypath config backup'.",
                details: [error.localizedDescription]
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }
    }
}
