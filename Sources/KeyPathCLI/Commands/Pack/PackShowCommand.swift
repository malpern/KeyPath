import ArgumentParser
import Foundation
import KeyPathAppKit

struct PackShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show details of a pack"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Pack name, slug, or ID (e.g., 'vim-navigation', 'Home Row Mods')")
    var nameOrId: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let detail: CLIPackDetail
        do {
            guard let found = try await facade.showPack(nameOrId: nameOrId) else {
                let error = CLIError.notFound("Pack", query: nameOrId, listCommand: "keypath pack list")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            detail = found
        } catch let ambiguous as AmbiguousPackMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(detail, context: ctx) {
            var lines = [
                "Name: \(detail.name)",
                "ID: \(detail.id)",
                "Version: \(detail.version)",
                "Category: \(detail.category)",
                "Author: \(detail.author)",
            ]

            if detail.isInstalled {
                if let date = detail.installedAt {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    lines.append("Status: Installed (since \(formatter.string(from: date)))")
                } else {
                    lines.append("Status: Installed")
                }
            } else {
                lines.append("Status: Not installed")
            }

            if detail.visualOnly {
                lines.append("Type: Visual only (no kanata config changes)")
            }

            lines.append("")
            lines.append(detail.shortDescription)
            if !detail.longDescription.isEmpty {
                lines.append("")
                lines.append(detail.longDescription)
            }

            if !detail.bindings.isEmpty {
                lines.append("")
                lines.append("Bindings:")
                for binding in detail.bindings {
                    if let hold = binding.holdOutput {
                        lines.append("  \(binding.input) \u{2192} tap: \(binding.output), hold: \(hold)")
                    } else {
                        lines.append("  \(binding.input) \u{2192} \(binding.output)")
                    }
                }
            }

            if !detail.quickSettings.isEmpty {
                lines.append("")
                lines.append("Quick Settings:")
                for setting in detail.quickSettings {
                    let current = detail.quickSettingValues[setting.id] ?? setting.defaultValue
                    lines.append("  \(setting.label): \(current)\(setting.unitSuffix) (range: \(setting.min)-\(setting.max)\(setting.unitSuffix), default: \(setting.defaultValue)\(setting.unitSuffix))")
                }
            }

            if !detail.dependencies.isEmpty {
                lines.append("")
                lines.append("Dependencies:")
                for dep in detail.dependencies {
                    let kindLabel = dep.kind == "requires" ? "Requires" : "Enhanced by"
                    let desc = dep.description ?? dep.packID
                    lines.append("  [\(kindLabel)] \(desc)")
                }
            }

            return lines.joined(separator: "\n")
        }
    }
}
