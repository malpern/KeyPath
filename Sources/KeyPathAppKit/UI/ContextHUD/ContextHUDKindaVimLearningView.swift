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
            Text("Motions + Window Nav")
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
        case .operatorPending: Color.orange
        case .unknown: Color.gray
        }
    }

    private func coachLines(for mode: KindaVimStateAdapter.Mode) -> [String] {
        switch mode {
        case .insert:
            [
                "Type normally. Press Esc (or Ctrl-[) to enter Normal mode.",
                "Use Leader hold for quick motion and navigation shortcuts.",
            ]
        case .normal:
            [
                "Focus on movement first: line, word, and document motions.",
                "Use Ctrl-w h/j/k/l for basic split/window navigation.",
            ]
        case .visual:
            [
                "Extend selections with the same motion keys.",
                "Press Esc to return to Normal movement.",
            ]
        case .operatorPending:
            [
                "An operator is pending — pick a motion or text object next.",
                "Press the same operator twice (dd, yy, cc) to act on the line.",
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
            [
                .init(keys: "Esc", meaning: "enter Normal mode"),
                .init(keys: "Ctrl-[", meaning: "alternate Esc"),
                .init(keys: "Leader hold", meaning: "open KeyPath motion keylist"),
            ]
        case .normal:
            [
                .init(keys: "h j k l", meaning: "left/down/up/right"),
                .init(keys: "w b e", meaning: "word motions"),
                .init(keys: "0  $", meaning: "line start/end"),
                .init(keys: "gg  G", meaning: "document top/bottom"),
                .init(keys: "Ctrl-w h/j/k/l", meaning: "move between windows"),
                .init(keys: "v / V", meaning: "enter Visual mode"),
            ]
        case .visual:
            [
                .init(keys: "h j k l", meaning: "expand selection"),
                .init(keys: "w b e", meaning: "word-wise selection"),
                .init(keys: "0  $", meaning: "line bounds"),
                .init(keys: "gg  G", meaning: "document bounds"),
                .init(keys: "Ctrl-w h/j/k/l", meaning: "window focus navigation"),
                .init(keys: "Esc", meaning: "return to Normal mode"),
            ]
        case .operatorPending:
            [
                .init(keys: "h j k l", meaning: "motion targets"),
                .init(keys: "w b e", meaning: "word motion targets"),
                .init(keys: "0  $", meaning: "line ends"),
                .init(keys: "(same op)", meaning: "× 2 = whole line"),
            ]
        case .unknown:
            commands(for: .normal)
        }
    }
}
