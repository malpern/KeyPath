import ArgumentParser
import Foundation

struct Completions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
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
