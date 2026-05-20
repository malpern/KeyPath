import ArgumentParser
import Foundation

struct Completions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Generate or install shell completions",
        subcommands: [
            Zsh.self,
            Bash.self,
            Fish.self,
            Install.self,
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

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install completions for your shell"
        )

        @Option(help: "Shell to install for (zsh, bash, fish). Defaults to current shell from $SHELL.")
        var shell: String?

        mutating func run() throws {
            let shellName = try resolveShell()
            let script: String
            let path: String

            switch shellName {
            case "zsh":
                script = KeyPathCLI.completionScript(for: .zsh)
                path = NSString("~/.zsh/completions/_keypath").expandingTildeInPath
            case "bash":
                script = KeyPathCLI.completionScript(for: .bash)
                path = NSString("~/.bash_completion.d/keypath").expandingTildeInPath
            case "fish":
                script = KeyPathCLI.completionScript(for: .fish)
                path = NSString("~/.config/fish/completions/keypath.fish").expandingTildeInPath
            default:
                throw ValidationError("Unsupported shell: '\(shellName)'. Use zsh, bash, or fish.")
            }

            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true
            )
            try script.write(toFile: path, atomically: true, encoding: .utf8)

            print("Installed \(shellName) completions to \(path)")

            if shellName == "zsh" {
                let completionsDir = NSString("~/.zsh/completions").expandingTildeInPath
                print("")
                print("If completions don't work, ensure this is in your ~/.zshrc:")
                print("  fpath=(~/.zsh/completions $fpath)")
                print("  autoload -Uz compinit && compinit")
                let _ = completionsDir
            }
        }

        private func resolveShell() throws -> String {
            if let explicit = shell {
                let normalized = explicit.lowercased()
                guard ["zsh", "bash", "fish"].contains(normalized) else {
                    throw ValidationError("Unsupported shell: '\(explicit)'. Use zsh, bash, or fish.")
                }
                return normalized
            }

            guard let shellEnv = ProcessInfo.processInfo.environment["SHELL"] else {
                throw ValidationError("Cannot detect shell from $SHELL. Use --shell to specify.")
            }

            let basename = (shellEnv as NSString).lastPathComponent
            guard ["zsh", "bash", "fish"].contains(basename) else {
                throw ValidationError("Unsupported shell '\(basename)' from $SHELL. Use --shell zsh, bash, or fish.")
            }
            return basename
        }
    }
}
