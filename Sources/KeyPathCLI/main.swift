import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

// Standalone CLI executable - uses the same CLI implementation as the GUI app
// This allows users to install and run CLI separately from the GUI

@main
struct KeyPathCLIMain {
    static func main() async {
        // Use the same CLI implementation
        let cli = KeyPathCLI()
        let exitCode = await cli.run(arguments: CommandLine.arguments)
        exit(exitCode)
    }
}
