import SwiftUI

/// Static quick-reference HUD view for Neovim commands.
/// Content is configured in the Rules panel (educational topics only).
struct ContextHUDNeovimTerminalView: View {
    @Environment(\.services) private var services
    let groups: [HUDKeyGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBadge
            referenceLayout
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.3, green: 0.6, blue: 0.9))
            Text("Neovim Quick Reference")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private var referenceLayout: some View {
        let selectedCategories = configuredCategories

        if selectedCategories.isEmpty {
            Text("Enable at least one Neovim topic in Rules to populate this reference.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        } else {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(leftColumnCategories(from: selectedCategories)) { category in
                        categorySection(category)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rightColumnCategories(from: selectedCategories)) { category in
                        categorySection(category)
                    }
                }
            }
        }
    }

    private func categorySection(_ category: NeovimTerminalCategory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(category.title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(category.accentColor.opacity(0.9))
                .tracking(1.2)

            ForEach(category.commands) { command in
                HStack(spacing: 8) {
                    Text(command.keys)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.12))
                        )
                    Text(command.meaning)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
    }

    private var configuredCategories: [NeovimTerminalCategory] {
        let selected = services.preferences.neovimReferenceTopics
        let valid = NeovimTerminalCategory.allCases.filter { selected.contains($0.rawValue) }
        return valid.isEmpty
            ? NeovimTerminalCategory.allCases.filter(\.defaultEnabled)
            : valid
    }

    private func leftColumnCategories(from categories: [NeovimTerminalCategory]) -> [NeovimTerminalCategory] {
        let midpoint = Int(ceil(Double(categories.count) / 2.0))
        return Array(categories.prefix(midpoint))
    }

    private func rightColumnCategories(from categories: [NeovimTerminalCategory]) -> [NeovimTerminalCategory] {
        let midpoint = Int(ceil(Double(categories.count) / 2.0))
        return Array(categories.dropFirst(midpoint))
    }
}
