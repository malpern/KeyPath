import Foundation
import KeyPathAppKit

@main
struct KeyPathCLIMain {
  static func main() async {
    let exitCode = await KeyPathCLI().run(arguments: CommandLine.arguments)
    exit(exitCode)
  }
}
