import KeyPathAppKit
import SwiftUI

@main
struct KeyPath {
    static func main() async {
        if let exitCode = await KeyPathCLIEntrypoint.runIfNeeded(arguments: CommandLine.arguments) {
            exit(exitCode)
        }

        KeyPathApp.main()
    }
}
