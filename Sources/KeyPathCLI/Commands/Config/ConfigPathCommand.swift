import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigPath: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Print the configuration file path"
    )

    mutating func run() async throws {
        let path = await MainActor.run { CLIFacade().configPath() }
        print(path)
    }
}
