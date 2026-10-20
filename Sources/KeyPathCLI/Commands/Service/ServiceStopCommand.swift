import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceStop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop remapping; KeyPath.app keeps running",
        discussion: "Waits until KeyPath.app has finished. Exit codes: 0 done, 1 the runtime refused or failed, 6 KeyPath.app is not running or did not answer."
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        try RuntimeControlClient.run(.stop, globals: globals, launch: false)
    }
}
