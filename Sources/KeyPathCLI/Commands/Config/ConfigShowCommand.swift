import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print current generated .kbd configuration"
    )

    mutating func run() async throws {
        let facade = await MainActor.run { CLIFacade() }
        let config = await facade.currentConfig()
        print(config)
    }
}
