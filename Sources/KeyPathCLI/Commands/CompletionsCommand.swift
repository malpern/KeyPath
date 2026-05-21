import ArgumentParser
import Foundation
import KeyPathAppKit

struct Completions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Generate or install shell completions",
        subcommands: [
            Zsh.self,
            Bash.self,
            Fish.self,
            Install.self,
            InstallMan.self,
            CompletionValues.self,
        ]
    )

    struct Zsh: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate zsh completions"
        )

        mutating func run() throws {
            let script = KeyPathCLI.completionScript(for: .zsh)
            CLIOutput.writeRaw(script)
            CLIOutput.writeRaw(Self.dynamicCompletionWrapper)
        }

        private static let dynamicCompletionWrapper = """

        # Dynamic completions for keypath argument values
        _keypath_dynamic_values() {
            local noun=$1
            local values
            values=(${(f)"$(keypath completions values "$noun" 2>/dev/null)"})
            compadd -a values
        }

        # Override specific subcommand completers for dynamic argument values
        _keypath_pack_show() { _keypath_dynamic_values pack }
        _keypath_pack_install() { _keypath_dynamic_values pack }
        _keypath_pack_uninstall() { _keypath_dynamic_values pack }
        _keypath_pack_configure() { _keypath_dynamic_values pack }
        _keypath_collection_enable() { _keypath_dynamic_values collection }
        _keypath_collection_disable() { _keypath_dynamic_values collection }
        _keypath_collection_show() { _keypath_dynamic_values collection }
        _keypath_rule_enable() { _keypath_dynamic_values rule }
        _keypath_rule_disable() { _keypath_dynamic_values rule }
        _keypath_rule_show() { _keypath_dynamic_values rule }
        _keypath_rule_remove() { _keypath_dynamic_values rule }
        _keypath_layer_switch() { _keypath_dynamic_values layer }
        _keypath_layer_delete() { _keypath_dynamic_values layer }
        _keypath_layer_rename() { _keypath_dynamic_values layer }
        """
    }

    struct Bash: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate bash completions"
        )

        mutating func run() throws {
            let script = KeyPathCLI.completionScript(for: .bash)
            CLIOutput.writeRaw(script)
        }
    }

    struct Fish: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate fish completions"
        )

        mutating func run() throws {
            let script = KeyPathCLI.completionScript(for: .fish)
            CLIOutput.writeRaw(script)
        }
    }

    struct InstallMan: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-man",
            abstract: "Install man pages for keypath"
        )

        mutating func run() throws {
            let manDir = NSString("~/.local/share/man/man1").expandingTildeInPath

            // Find man pages source: check app bundle, then common install locations
            let candidates = [
                "/Applications/KeyPath.app/Contents/Resources/man",
                NSString("~/Applications/KeyPath.app/Contents/Resources/man").expandingTildeInPath,
                // Development: relative to binary
                Bundle.main.bundlePath + "/../share/man/man1",
            ]

            var sourceDir: String?
            for candidate in candidates {
                let mainPage = (candidate as NSString).appendingPathComponent("keypath.1")
                if FileManager.default.fileExists(atPath: mainPage) {
                    sourceDir = candidate
                    break
                }
            }

            guard let source = sourceDir else {
                printErr("Man pages not found. They ship with KeyPath.app.")
                printErr("")
                printErr("If you installed from source, generate them with:")
                printErr("  swift package plugin --allow-writing-to-directory docs/man generate-manual --multi-page --output-directory docs/man")
                printErr("")
                printErr("Then copy to your man path:")
                printErr("  mkdir -p \(manDir)")
                printErr("  cp docs/man/*.1 \(manDir)/")
                return
            }

            try FileManager.default.createDirectory(
                atPath: manDir,
                withIntermediateDirectories: true
            )

            let fm = FileManager.default
            let pages = try fm.contentsOfDirectory(atPath: source)
                .filter { $0.hasSuffix(".1") }

            for page in pages {
                let src = (source as NSString).appendingPathComponent(page)
                let dst = (manDir as NSString).appendingPathComponent(page)
                if fm.fileExists(atPath: dst) {
                    try fm.removeItem(atPath: dst)
                }
                try fm.copyItem(atPath: src, toPath: dst)
            }

            printErr("Installed \(pages.count) man page(s) to \(manDir)")
            printErr("Try: man keypath")
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

            printErr("Installed \(shellName) completions to \(path)")

            if shellName == "zsh" {
                printErr("")
                printErr("If completions don't work, ensure this is in your ~/.zshrc:")
                printErr("  fpath=(~/.zsh/completions $fpath)")
                printErr("  autoload -Uz compinit && compinit")
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

    struct CompletionValues: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "values",
            abstract: "Output completable values for a noun (used by shell completion functions)",
            shouldDisplay: false
        )

        @Argument(help: "Noun to complete: pack, collection, layer, rule")
        var noun: String

        mutating func run() async throws {
            switch noun.lowercased() {
            case "pack":
                let facade = await MainActor.run { CLIFacade() }
                let packs = await facade.listPacks()
                for pack in packs {
                    let slug = pack.id.replacingOccurrences(of: "com.keypath.pack.", with: "")
                    CLIOutput.writeRaw(slug)
                }
            case "collection":
                let facade = CollectionsFacade()
                let collections = await facade.loadRuleCollections()
                for c in collections {
                    CLIOutput.writeRaw(c.name)
                }
            case "layer":
                let facade = CollectionsFacade()
                let layers = await facade.listDefinedLayers()
                for layer in layers {
                    CLIOutput.writeRaw(layer)
                }
            case "rule":
                let facade = RulesFacade()
                let rules = await facade.listRules()
                for rule in rules {
                    CLIOutput.writeRaw(rule.input)
                }
            default:
                throw ValidationError("Unknown noun: '\(noun)'. Use pack, collection, layer, or rule.")
            }
        }
    }
}
