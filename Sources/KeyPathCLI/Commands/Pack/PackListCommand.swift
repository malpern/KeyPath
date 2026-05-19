import ArgumentParser
import Foundation
import KeyPathAppKit

struct PackList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available packs and their install status"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }
        let packs = await facade.listPacks()

        CLIOutput.write(packs, context: ctx) {
            if packs.isEmpty {
                return "No packs available."
            }

            let installedCount = packs.filter(\.isInstalled).count
            var lines = [
                "Packs (\(packs.count) available, \(installedCount) installed):",
                String(repeating: "\u{2500}", count: 60),
            ]

            let grouped = Dictionary(grouping: packs, by: \.category)
            let categoryOrder = orderedCategories(from: packs)

            for category in categoryOrder {
                guard let categoryPacks = grouped[category] else { continue }
                lines.append("")
                lines.append("  \(category)")
                for pack in categoryPacks {
                    let status = pack.isInstalled ? "+" : " "
                    let name = pack.name.padding(toLength: 28, withPad: " ", startingAt: 0)
                    lines.append("    [\(status)] \(name) \(pack.tagline)")
                }
            }

            return lines.joined(separator: "\n")
        }
    }

    private func orderedCategories(from packs: [CLIPack]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for pack in packs {
            if seen.insert(pack.category).inserted {
                order.append(pack.category)
            }
        }
        return order
    }
}
