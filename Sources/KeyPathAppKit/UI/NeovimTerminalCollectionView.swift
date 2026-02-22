import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Rules tab expanded view for the Neovim Terminal collection.
/// Shows an info banner and compact category cards.
struct NeovimTerminalCollectionView: View {
    let mappings: [KeyMapping]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoBanner
            categorySummary
            categoryGrid
        }
    }

    private var infoBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundColor(Color(red: 0.3, green: 0.6, blue: 0.9))
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.3, green: 0.6, blue: 0.9).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Neovim Quick Reference")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Hold Leader to see motions and basic split/window navigation in the HUD.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var categorySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Covers \(mappings.count) leader-layer shortcuts plus a focused Neovim reference for movement and window navigation.")
                .font(.subheadline)
                .foregroundColor(.primary)
            Text("The HUD keeps the list intentionally short so it’s faster to scan.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ], spacing: 8) {
            ForEach(NeovimTerminalCategory.allCases) { category in
                categoryCard(category)
            }
        }
    }

    private func categoryCard(_ category: NeovimTerminalCategory) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(category.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if category.isNeovimSpecific {
                    Text("Neovim")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(category.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(category.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(category.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}
