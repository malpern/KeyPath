import SwiftUI

/// Mode-aware KindaVim teaching view for leader-hold Context HUD.
/// This view is intentionally non-interactive (HUD window is click-through).
struct ContextHUDKindaVimLearningView: View {
    let groups: [HUDKeyGroup]
    let state: KindaVimStateAdapter.StateSnapshot?
    let modeSetting: KindaVimLeaderHUDMode

    @State private var strategyMonitor = KindaVimStrategyMonitor.shared
    @AppStorage("kindaVim.showAdvancedHints") private var showAdvancedHints: Bool = false

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

    @ViewBuilder
    private var quickReferenceSection: some View {
        // Strategy.ignored wins over mode: switching from an insert-mode
        // app into an ignore-listed app and opening the HUD before the
        // mode signal updates would otherwise show insert-mode guidance
        // even though kindaVim isn't running there. Show the off-here
        // hint first, then fall back to mode-driven branches.
        if strategyMonitor.currentStrategy == .ignored {
            ignoredStrategyHint
        } else if mode == .insert {
            insertModeHints
        } else {
            vimBindingsSections
        }
    }

    private var insertModeHints: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader("Insert mode")
            ForEach(insertModeCommands) { command in
                commandRow(keys: command.keys, meaning: command.meaning, loud: false)
            }
        }
    }

    private var ignoredStrategyHint: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader("KindaVim is off here")
            Text("This app is in KindaVim's ignore list. Mode signals don't apply.")
                .font(.footnote)
                .lineSpacing(1.5)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var vimBindingsSections: some View {
        let bindingGroups = VimBindings.grouped(
            strategy: strategyMonitor.currentStrategy,
            mode: mode,
            showAdvanced: showAdvancedHints
        )
        return VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(bindingGroups.enumerated()), id: \.offset) { _, group in
                bindingGroupSection(group)
            }
            if mode == .operatorPending {
                Text("Press the same operator twice (dd · yy · cc) to act on the whole line.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(1.5)
            }
        }
    }

    @ViewBuilder
    private func bindingGroupSection(_ group: VimHintGroup) -> some View {
        let isMovement = group.group == .movement
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(group.displayName)
            ForEach(group.entries) { entry in
                commandRow(
                    keys: entry.displayLabel,
                    meaning: entry.actionLabel,
                    loud: isMovement && entry.tier == .core
                )
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.monospaced().weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .tracking(1.2)
    }

    private func commandRow(keys: String, meaning: String, loud: Bool) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(loud ? .body : .footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, loud ? 9 : 7)
                .padding(.vertical, loud ? 4 : 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(loud ? Color.accentColor.opacity(0.5) : .white.opacity(0.12))
                )
            Text(meaning)
                .font(loud ? .footnote.weight(.semibold) : .footnote)
                .lineSpacing(1.5)
                .foregroundStyle(.white.opacity(loud ? 1.0 : 0.85))
        }
    }

    private var insertModeCommands: [CommandItem] {
        [
            .init(keys: "Esc", meaning: "enter Normal mode"),
            .init(keys: "Ctrl-[", meaning: "alternate Esc"),
            .init(keys: "Leader hold", meaning: "open KeyPath motion keylist"),
        ]
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

    // The hardcoded `commands(for:)` switch was replaced with
    // `VimBindings.grouped(strategy:mode:showAdvanced:)` so the cheat
    // sheet narrows to what the active strategy actually supports.
}
