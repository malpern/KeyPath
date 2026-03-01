import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Remap: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create or modify key remappings"
        )

        @Argument(help: "Input key to remap (e.g., caps, lalt)")
        var input: String

        @Argument(help: "Output key for simple remap (e.g., esc, lctl)")
        var output: String?

        @Option(help: "Key to emit on tap (for tap-hold)")
        var tap: String?

        @Option(help: "Key to emit on hold (for tap-hold)")
        var hold: String?

        @Flag(help: "Remove the mapping for the input key")
        var remove: Bool = false

        @Flag(help: "Apply changes immediately after remapping")
        var apply: Bool = false

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }

            if remove {
                let removed = try await facade.removeRemap(input: input)
                if !removed {
                    print("No mapping found for '\(input)'")
                    throw ExitCode.failure
                }
                print("Removed mapping for '\(input)'")
            } else if let tap, let hold {
                try await facade.addTapHoldRemap(input: input, tap: tap, hold: hold)
                print("Mapped \(input) → tap:\(tap), hold:\(hold)")
            } else if let output {
                try await facade.addSimpleRemap(input: input, output: output)
                print("Mapped \(input) → \(output)")
            } else {
                print("Error: specify an output key, or --tap/--hold for tap-hold, or --remove")
                throw ExitCode.failure
            }

            if apply {
                print("Applying configuration...")
                let result = try await facade.applyConfiguration()
                if result.reloadSuccess {
                    print("Configuration applied and Kanata reloaded.")
                } else {
                    print("Configuration written but Kanata reload failed.")
                    throw ExitCode.failure
                }
            }
        }
    }
}
