import Foundation

enum KeyPathCLIEntrypoint {
    private static let supportedCommands: Set<String> = [
        "install",
        "repair",
        "uninstall",
        "status",
        "inspect",
        "help",
        "--help",
        "-h"
    ]

    /// Returns an exit code if CLI mode handled, otherwise nil to bootstrap the UI app.
    @MainActor
    static func runIfNeeded(arguments: [String]) async -> Int32? {
        guard arguments.count > 1 else {
            return nil
        }

        let command = arguments[1]
        guard supportedCommands.contains(command) else {
            return nil
        }

        let cli = KeyPathCLI()
        return await cli.run(arguments: arguments)
    }
}

