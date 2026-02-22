import SwiftUI

/// Static quick-reference HUD view for Neovim commands.
/// Focused on core motions and basic split/window navigation.
struct ContextHUDNeovimTerminalView: View {
    let groups: [HUDKeyGroup]

    private struct CommandItem: Identifiable {
        let id = UUID()
        let keys: String
        let meaning: String
    }

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

    private var referenceLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                categorySection(
                    title: "MOTIONS",
                    color: NeovimTerminalCategory.movement.accentColor,
                    commands: movementCommands
                )
                categorySection(
                    title: "SEARCH",
                    color: NeovimTerminalCategory.search.accentColor,
                    commands: searchCommands
                )
            }
            VStack(alignment: .leading, spacing: 14) {
                categorySection(
                    title: "WINDOW NAVIGATION",
                    color: NeovimTerminalCategory.windowNavigation.accentColor,
                    commands: windowNavigationCommands
                )
            }
        }
    }

    private func categorySection(
        title: String,
        color: Color,
        commands: [CommandItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(color.opacity(0.9))
                .tracking(1.2)

            ForEach(commands) { command in
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

    // MARK: - Static Command Data

    private var movementCommands: [CommandItem] {
        [
            .init(keys: "h j k l", meaning: "left/down/up/right"),
            .init(keys: "w b e", meaning: "word motions"),
            .init(keys: "0  $", meaning: "line start/end"),
            .init(keys: "gg  G", meaning: "file start/end"),
            .init(keys: "f  t", meaning: "find/till char"),
        ]
    }

    private var windowNavigationCommands: [CommandItem] {
        [
            .init(keys: "Ctrl-w h/j/k/l", meaning: "focus left/down/up/right split"),
            .init(keys: "Ctrl-w v  /  s", meaning: "split vertical / horizontal"),
            .init(keys: "Ctrl-w =", meaning: "equalize split sizes"),
            .init(keys: "Ctrl-w q", meaning: "close current split"),
        ]
    }

    private var searchCommands: [CommandItem] {
        [
            .init(keys: "/  ?", meaning: "search fwd/back"),
            .init(keys: "n  N", meaning: "next/prev match"),
            .init(keys: "*  #", meaning: "word under cursor"),
        ]
    }
}
