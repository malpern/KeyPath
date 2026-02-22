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
        VStack(alignment: .leading, spacing: 14) {
            installationBanner
            shortcutCardsSection
            strategyTip
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
            Text("Enable this collection to load leader shortcuts.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                    Text("Leader Shortcuts in KeyPath")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    if let movement = categories.first(where: { $0 == .movement }) {
                        categoryCard(for: movement, index: 0)
                    }
                    if let word = categories.first(where: { $0 == .wordMotion }) {
                        categoryCard(for: word, index: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 12) {
                    if let editing = categories.first(where: { $0 == .editing }) {
                        categoryCard(for: editing, index: 2)
                    }
                    if let search = categories.first(where: { $0 == .search }) {
                        categoryCard(for: search, index: 3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if let clip = categories.first(where: { $0 == .clipboard }) {
                    HStack(alignment: .top, spacing: 12) {
                        categoryCard(for: clip, index: 4)
                        Spacer()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var strategyTip: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.caption)
            Text("KindaVim auto-detects strategy. Hold fn while moving to force Keyboard Strategy.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 2)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut.delay(0.45), value: hasAppeared)
    }

    @ViewBuilder
    private var installationBanner: some View {
        let installed = KindaVimDetector.isInstalled
        HStack(alignment: .center, spacing: 12) {
            kindaVimLogo

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(installed ? .green : .orange)
                        .font(.caption.weight(.semibold))
                    Text(installed ? "KindaVim is installed" : "KindaVim not found")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
                Text(installed ? "KeyPath detected KindaVim and your Rules collection is ready." : "Install KindaVim to enable modal editing in macOS apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if !installed {
                Button {
                    NSWorkspace.shared.open(KindaVimDetector.downloadURL)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("kindavim-download-button")
                .accessibilityLabel("Download KindaVim")
            }
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

    private var kindaVimLogo: some View {
        Group {
            if let image = Self.kindaVimLogoImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "command.square.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private static let kindaVimLogoImage: NSImage? = {
        let resourceName = "kindavim-icon"
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks

        for bundle in bundles {
            if let url = bundle.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }

        if let mainResourceURL = Bundle.main.resourceURL {
            let keyPathBundleURL = mainResourceURL.appendingPathComponent("KeyPath_KeyPath.bundle")
            if let keyPathBundle = Bundle(url: keyPathBundleURL),
               let url = keyPathBundle.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }

        return nil
    }()

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

            if category == .movement {
                VimArrowKeysCompact()
                    .padding(.vertical, 4)
            }

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
