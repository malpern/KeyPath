import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigBackup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Copy the KeyPath config directory for QA-safe restore"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .customLong("output"), help: "Backup directory to create. Defaults to ~/Library/Application Support/KeyPath/QA Backups/keypath-config-<timestamp>.")
    var outputPath: String?

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = ConfigFacade()

        do {
            let result = try facade.backupConfig(outputPath: outputPath)
            CLIOutput.write(result, context: ctx) {
                """
                Backup created: \(result.backupPath)
                Source: \(result.sourcePath)
                Items: \(result.copiedItems.isEmpty ? "none" : result.copiedItems.joined(separator: ", "))
                """
            }
        } catch {
            let cliError = CLIError.validation(
                "Config backup failed",
                hint: "Check that ~/.config/keypath exists and the destination does not already exist.",
                details: [error.localizedDescription]
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }
    }
}
