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

        @Option(help: "Tap-hold timeout in milliseconds (default: 200)")
        var timeout: Int = 200

        @Flag(help: "Remove the mapping for the input key")
        var remove: Bool = false

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
                // Validate all keys
                try validateKeyName(input, label: "input", facade: facade)
                try validateKeyName(tap, label: "tap", facade: facade)
                try validateKeyName(hold, label: "hold", facade: facade)

                try await facade.addTapHoldRemap(input: input, tap: tap, hold: hold, timeout: timeout)
                print("Mapped \(input) → tap:\(tap), hold:\(hold) (timeout: \(timeout)ms)")
            } else if let output {
                // Validate keys
                try validateKeyName(input, label: "input", facade: facade)
                try validateKeyName(output, label: "output", facade: facade)

                try await facade.addSimpleRemap(input: input, output: output)
                print("Mapped \(input) → \(output)")
            } else {
                print("Error: specify an output key, or --tap/--hold for tap-hold, or --remove")
                throw ExitCode.failure
            }

            print("Run 'keypath apply' to regenerate config and reload Kanata.")
        }

        private func validateKeyName(_ key: String, label: String, facade: CLIFacade) throws {
            guard facade.validateKey(key) != nil else {
                print("Invalid \(label) key: '\(key)'")
                print("Use canonical Kanata key names (e.g., caps, lalt, esc, lctl, spc, ret)")
                throw ExitCode.failure
            }
        }
    }
}
