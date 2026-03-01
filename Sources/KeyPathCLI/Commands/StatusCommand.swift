import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check system status and health"
        )

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }
            let code = await facade.runStatus()
            if code != 0 {
                throw ExitCode(code)
            }
        }
    }
}
