import ArgumentParser
import Foundation
import KeyPathAppKit
import KeyPathCLISupport

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

        static let dynamicCompletionWrapper = """

        # Dynamic completions for keypath argument values
        # Wraps ArgumentParser-generated functions to add dynamic values
        # for positional arguments while preserving flag completions.
        _keypath_wrap_with_dynamic() {
            local func_name=$1 noun=$2
            (( ${+functions[$func_name]} )) || return
            eval "$(functions -- $func_name | sed '1s/.*/___orig_&/')"
            eval "${func_name}() {
                ___orig_${func_name}
                local values
                values=(\\${(f)\\"\\$(keypath completions values ${noun} 2>/dev/null)\\"})
                compadd -a values
            }"
        }

        _keypath_wrap_with_dynamic _keypath_pack_show pack
        _keypath_wrap_with_dynamic _keypath_pack_install pack
        _keypath_wrap_with_dynamic _keypath_pack_uninstall pack
        _keypath_wrap_with_dynamic _keypath_pack_configure pack
        _keypath_wrap_with_dynamic _keypath_collection_enable collection
        _keypath_wrap_with_dynamic _keypath_collection_disable collection
        _keypath_wrap_with_dynamic _keypath_collection_show collection
        _keypath_wrap_with_dynamic _keypath_collection_delete collection
        _keypath_wrap_with_dynamic _keypath_collection_rename collection
        _keypath_wrap_with_dynamic _keypath_collection_duplicate collection
        _keypath_wrap_with_dynamic _keypath_rule_enable rule
        _keypath_wrap_with_dynamic _keypath_rule_disable rule
        _keypath_wrap_with_dynamic _keypath_rule_show rule
        _keypath_wrap_with_dynamic _keypath_rule_remove rule
        _keypath_wrap_with_dynamic _keypath_layer_switch layer
        _keypath_wrap_with_dynamic _keypath_layer_delete layer
        _keypath_wrap_with_dynamic _keypath_layer_rename layer
        """
    }

    struct Bash: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate bash completions"
        )

        mutating func run() throws {
            let script = KeyPathCLI.completionScript(for: .bash)
            CLIOutput.writeRaw(script)
            CLIOutput.writeRaw(Self.dynamicCompletionWrapper)
        }

        static let dynamicCompletionWrapper = """

        # Dynamic completions for keypath argument values (Bash 3.2 compatible)
        _keypath_dynamic_values() {
            local noun=$1 cur="${COMP_WORDS[COMP_CWORD]}"
            local line
            while IFS= read -r line; do
                [[ "$line" == "$cur"* ]] && COMPREPLY+=("$line")
            done < <(keypath completions values "$noun" 2>/dev/null)
        }

        _keypath_dynamic_complete() {
            local cmd="${COMP_WORDS[1]:-}" sub="${COMP_WORDS[2]:-}"
            case "$cmd:$sub" in
                pack:show|pack:install|pack:uninstall|pack:configure)
                    _keypath_dynamic_values pack ;;
                collection:enable|collection:disable|collection:show|collection:delete|collection:rename|collection:duplicate)
                    _keypath_dynamic_values collection ;;
                rule:enable|rule:disable|rule:show|rule:remove)
                    _keypath_dynamic_values rule ;;
                layer:switch|layer:delete|layer:rename)
                    _keypath_dynamic_values layer ;;
            esac
        }

        if type -t _keypath_bash_complete >/dev/null 2>&1; then
            _keypath_orig_bash_complete=$(declare -f _keypath_bash_complete | sed '1d;$d')
            _keypath_bash_complete() {
                eval "$_keypath_orig_bash_complete"
                _keypath_dynamic_complete
            }
        else
            echo "keypath: warning: _keypath_bash_complete not found, flag completions unavailable" >&2
            complete -F _keypath_dynamic_complete keypath
        fi
        """
    }

    struct Fish: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate fish completions"
        )

        mutating func run() throws {
            let script = KeyPathCLI.completionScript(for: .fish)
            CLIOutput.writeRaw(script)
            CLIOutput.writeRaw(Self.dynamicCompletionWrapper)
        }

        static let dynamicCompletionWrapper = """

        # Dynamic completions for keypath argument values
        complete -c keypath -n '__fish_seen_subcommand_from pack; and __fish_seen_subcommand_from show install uninstall configure' -xa '(keypath completions values pack 2>/dev/null)'
        complete -c keypath -n '__fish_seen_subcommand_from collection; and __fish_seen_subcommand_from enable disable show delete rename duplicate' -xa '(keypath completions values collection 2>/dev/null)'
        complete -c keypath -n '__fish_seen_subcommand_from rule; and __fish_seen_subcommand_from enable disable show remove' -xa '(keypath completions values rule 2>/dev/null)'
        complete -c keypath -n '__fish_seen_subcommand_from layer; and __fish_seen_subcommand_from switch delete rename' -xa '(keypath completions values layer 2>/dev/null)'
        """
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
                script = KeyPathCLI.completionScript(for: .zsh) + Zsh.dynamicCompletionWrapper
                path = NSString("~/.zsh/completions/_keypath").expandingTildeInPath
            case "bash":
                script = KeyPathCLI.completionScript(for: .bash) + Bash.dynamicCompletionWrapper
                path = NSString("~/.bash_completion.d/keypath").expandingTildeInPath
            case "fish":
                script = KeyPathCLI.completionScript(for: .fish) + Fish.dynamicCompletionWrapper
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
                let facade = PacksFacade()
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
