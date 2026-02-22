import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct KindaVimCollectionView: View {
    let mappings: [KeyMapping]

    @State private var hasAppeared = false

    private var categories: [KindaVimCategory] {
        KindaVimCategory.allCases.filter { !commandsFor($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Installation status banner
            installationBanner

            // Description
            Text("KindaVim brings real Vim modes to every macOS app. This collection adds leader-key shortcuts for quick access when in Insert mode.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Row 1: Movement + Word Motion
            HStack(alignment: .top, spacing: 12) {
                if let movement = categories.first(where: { $0 == .movement }) {
                    categoryCard(for: movement, index: 0)
                }
                if let word = categories.first(where: { $0 == .wordMotion }) {
                    categoryCard(for: word, index: 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // Row 2: Editing + Search
            HStack(alignment: .top, spacing: 12) {
                if let editing = categories.first(where: { $0 == .editing }) {
                    categoryCard(for: editing, index: 2)
                }
                if let search = categories.first(where: { $0 == .search }) {
                    categoryCard(for: search, index: 3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // Row 3: Clipboard (single card)
            if let clip = categories.first(where: { $0 == .clipboard }) {
                HStack(alignment: .top, spacing: 12) {
                    categoryCard(for: clip, index: 4)
                    Spacer()
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // Tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("KindaVim provides full Vim modes. This collection adds leader-key shortcuts for quick access.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut.delay(0.5), value: hasAppeared)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Installation Banner

    @ViewBuilder
    private var installationBanner: some View {
        let installed = KindaVimDetector.isInstalled
        HStack(spacing: 8) {
            Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(installed ? .green : .orange)
                .font(.body)
            Text(installed ? "KindaVim is installed" : "KindaVim not found")
                .font(.subheadline.weight(.medium))
                .foregroundColor(installed ? .green : .orange)
            Spacer()
            if !installed {
                Button {
                    NSWorkspace.shared.open(KindaVimDetector.downloadURL)
                } label: {
                    Label("Download KindaVim", systemImage: "arrow.down.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((installed ? Color.green : Color.orange).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((installed ? Color.green : Color.orange).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Category Card

    private func categoryCard(for category: KindaVimCategory, index: Int) -> some View {
        KindaVimCategoryCard(
            category: category,
            commands: commandsFor(category)
        )
        .scaleEffect(hasAppeared ? 1 : 0.8)
        .opacity(hasAppeared ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7)
                .delay(Double(index) * 0.1),
            value: hasAppeared
        )
    }

    private func commandsFor(_ category: KindaVimCategory) -> [KeyMapping] {
        let inputs = category.commandInputs
        return mappings.filter { inputs.contains($0.input.lowercased()) }
    }
}

// MARK: - KindaVim Category Card

private struct KindaVimCategoryCard: View {
    let category: KindaVimCategory
    let commands: [KeyMapping]

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.body.weight(.semibold))
                    .foregroundColor(isHovered ? .white : category.accentColor)
                    .symbolEffect(.bounce, value: isHovered)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? category.accentColor : category.accentColor.opacity(0.15))
                    )

                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // Command list
            VStack(alignment: .leading, spacing: 2) {
                ForEach(commands, id: \.id) { command in
                    VimCommandRowCompact(command: command, accentColor: category.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(category.accentColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: category.accentColor.opacity(isHovered ? 0.2 : 0), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
