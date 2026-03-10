import ArgumentParser
import Foundation
import KeyPathAppKit

/// Shared helper for the --apply flag used across multiple commands.
/// Regenerates config from all collections/rules and reloads Kanata via TCP.
func applyConfigurationOrHint(facade: CLIFacade, apply: Bool) async throws {
    if apply {
        let result = try await facade.applyConfiguration()
        if result.reloadSuccess {
            print("Config applied and Kanata reloaded.")
        } else {
            printErr("Config written but Kanata reload failed.")
            printErr("Run 'keypath tcp reload' once Kanata is running.")
            throw ExitCode.failure
        }
    } else {
        print("Run 'keypath apply' to regenerate config and reload Kanata.")
    }
}
