import SwiftUI

/// Mode-aware KindaVim teaching view for leader-hold Context HUD.
/// This view is intentionally non-interactive (HUD window is click-through).
struct ContextHUDKindaVimLearningView: View {
    let groups: [HUDKeyGroup]
    let state: KindaVimStateAdapter.StateSnapshot?
    let modeSetting: KindaVimLeaderHUDMode

    private struct CommandItem: Identifiable {
        let id = UUID()
        let keys: String
        let meaning: String
    }

    private var mode: KindaVimStateAdapter.Mode {
        guard let state, !state.isStale, state.mode != .unknown else {
            return .normal
        }
        return state.mode
    }

    private var isLiveMode: Bool {
        guard let state else { return false }
        return !state.isStale && state.mode != .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modeStrip
            sourceLine

            if modeSetting == .contextualCoach {
                coachSection
            }

            quickReferenceSection
            leaderShortcutsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeStrip: some View {
        HStack(spacing: 10) {
            ForEach([KindaVimStateAdapter.Mode.insert, .normal, .visual], id: \.self) { current in
                HStack(spacing: 6) {
                    Circle()
                        .fill(current == mode ? modeColor(current) : modeColor(current).opacity(0.35))
                        .frame(width: 7, height: 7)
                    Text(current.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(current == mode ? .white : .white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(current == mode ? modeColor(current).opacity(0.3) : .white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(current == mode ? modeColor(current).opacity(0.8) : .white.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    private var sourceLine: some View {
        HStack(spacing: 7) {
            Image(systemName: isLiveMode ? "dot.radiowaves.left.and.right" : "exclamationmark.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isLiveMode ? Color.green : Color.orange)
            Text(modeSourceDescription)
                .font(.footnote)
                .lineSpacing(1.5)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Now")
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(modeColor(mode).opacity(0.9))
                .tracking(1.2)

            ForEach(coachLines(for: mode), id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .lineSpacing(1.5)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(modeColor(mode).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(modeColor(mode).opacity(0.35), lineWidth: 1)
        )
    }

    private var quickReferenceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Quick Reference")
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(1.2)

            ForEach(commands(for: mode)) { command in
                HStack(spacing: 10) {
                    Text(command.keys)
                        .font(.system(.footnote, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.white.opacity(0.12))
                        )
                    Text(command.meaning)
                        .font(.footnote)
                        .lineSpacing(1.5)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private var leaderShortcutsSection: some View {
        let hintEntries = groups
            .flatMap(\.entries)
            .prefix(4)
            .map { "\($0.keycap.lowercased()) \u{2192} \($0.action)" }

        return VStack(alignment: .leading, spacing: 5) {
            Text("Leader Shortcuts")
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .tracking(1.2)

            if hintEntries.isEmpty {
                Text("Enable the KindaVim collection to add leader shortcuts.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text(hintEntries.joined(separator: "  ·  "))
                    .font(.footnote)
                    .lineSpacing(1.5)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
        }
    }

    private var modeSourceDescription: String {
        guard let state else {
            return "Mode unavailable. Showing Normal defaults."
        }
        if state.isStale {
            return "Mode signal is stale. Showing last-known commands."
        }
        switch state.source {
        case .json:
            return "Live mode from KindaVim environment.json."
        case .karabiner:
            return "Mode from Karabiner integration fallback."
        case .fallback:
            return "Mode unavailable. Showing Normal defaults."
        }
    }

    private func modeColor(_ mode: KindaVimStateAdapter.Mode) -> Color {
        switch mode {
        case .insert: Color.green
        case .normal: Color.blue
        case .visual: Color.purple
        case .unknown: Color.gray
        }
    }

    private func coachLines(for mode: KindaVimStateAdapter.Mode) -> [String] {
        switch mode {
        case .insert:
            [
                "Type normally. Press Esc (or Ctrl-[) to enter Normal mode.",
                "Use Leader hold for quick nav actions without leaving Insert.",
            ]
        case .normal:
            [
                "Navigate/edit with motions and operators.",
                "Press v or V to select; press i/a/o to return to typing.",
            ]
        case .visual:
            [
                "Extend selection with motions, then apply an operator.",
                "Use d/y/~/< or > on the current selection.",
            ]
        case .unknown:
            [
                "Mode signal unavailable. Start from Normal commands.",
            ]
        }
    }

    private func commands(for mode: KindaVimStateAdapter.Mode) -> [CommandItem] {
        switch mode {
        case .insert:
            return [
                .init(keys: "Esc", meaning: "enter Normal mode"),
                .init(keys: "Ctrl-[", meaning: "alternate Esc"),
                .init(keys: "i / a", meaning: "insert before/after (from Normal)"),
                .init(keys: "o / O", meaning: "open line below/above"),
            ]
        case .normal:
            return [
                .init(keys: "h j k l", meaning: "left/down/up/right"),
                .init(keys: "w b e", meaning: "word motions"),
                .init(keys: "0  $", meaning: "line start/end"),
                .init(keys: "d{motion}", meaning: "delete by motion"),
                .init(keys: "c{motion}", meaning: "change by motion"),
                .init(keys: "u  Ctrl-r", meaning: "undo / redo"),
                .init(keys: "v / V", meaning: "enter Visual mode"),
            ]
        case .visual:
            return [
                .init(keys: "h j k l", meaning: "expand selection"),
                .init(keys: "w b e", meaning: "word-wise selection"),
                .init(keys: "d", meaning: "delete selection"),
                .init(keys: "y", meaning: "yank selection"),
                .init(keys: "~", meaning: "toggle case"),
                .init(keys: "<  >", meaning: "indent/outdent"),
                .init(keys: "Esc", meaning: "return to Normal mode"),
            ]
        case .unknown:
            return commands(for: .normal)
        }
    }
}
