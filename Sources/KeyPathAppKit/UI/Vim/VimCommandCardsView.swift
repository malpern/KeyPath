import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct VimCommandCardsView: View {
    let mappings: [KeyMapping]

    @State private var hasAppeared = false

    private var categories: [VimCategory] {
        VimCategory.allCases.filter { !commandsFor($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            shortcutCardsSection
            shiftTip
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }

    @ViewBuilder
    private var shortcutCardsSection: some View {
        if categories.isEmpty {
            Text("Enable this collection to load shortcut cards.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                    Text("Shortcut Reference")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    if let nav = categories.first(where: { $0 == .navigation }) {
                        cardView(for: nav, index: 0)
                    }
                    if let edit = categories.first(where: { $0 == .editing }) {
                        cardView(for: edit, index: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 12) {
                    if let search = categories.first(where: { $0 == .search }) {
                        cardView(for: search, index: 2)
                    }
                    if let clip = categories.first(where: { $0 == .clipboard }) {
                        cardView(for: clip, index: 3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shiftTip: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.caption)
            Text("Hold ⇧ Shift while navigating to select text.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 2)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut.delay(0.45), value: hasAppeared)
    }

    private func cardView(for category: VimCategory, index: Int) -> some View {
        VimCategoryCard(
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

    private func commandsFor(_ category: VimCategory) -> [KeyMapping] {
        let inputs = category.commandInputs
        return mappings.filter { inputs.contains($0.input.lowercased()) }
    }
}
