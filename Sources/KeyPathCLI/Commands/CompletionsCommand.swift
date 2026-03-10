import ArgumentParser
import Foundation

extension KeyPathCLI {
    /// Explicit subcommands for shell completions.
    /// ArgumentParser also provides a built-in `--generate-completion-script <shell>`
    /// flag, but these subcommands are more discoverable for users.
    struct Completions: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate shell completions",
            subcommands: [
                Zsh.self,
                Bash.self,
                Fish.self,
            ]
        )

        struct Zsh: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate zsh completions"
            )

            mutating func run() throws {
                let script = KeyPathCLI.completionScript(for: .zsh)
                print(script)
            }
        }

        struct Bash: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate bash completions"
            )

            mutating func run() throws {
                let script = KeyPathCLI.completionScript(for: .bash)
                print(script)
            }
        }

        struct Fish: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate fish completions"
            )

            mutating func run() throws {
                let script = KeyPathCLI.completionScript(for: .fish)
                print(script)
            }
        }
    }
}
