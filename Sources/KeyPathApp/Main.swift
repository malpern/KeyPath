import KeyPathAppKit
import SwiftUI

@main
struct KeyPathMain {
    static func main() async {
        if let exitCode = await KeyPathCLIEntrypoint.runIfNeeded(arguments: CommandLine.arguments) {
            exit(exitCode)
        }

        KeyPathApp.main()
    }
}
