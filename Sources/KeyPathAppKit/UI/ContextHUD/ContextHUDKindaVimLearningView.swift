import SwiftUI

struct ContextHUDKindaVimLearningView: View {
    let groups: [HUDKeyGroup]
    let state: KindaVimStateAdapter.StateSnapshot?
    let modeSetting: KindaVimLeaderHUDMode

    @State private var strategyMonitor = KindaVimStrategyMonitor.shared
    @State private var sequenceObserver = VimSequenceObserver.shared
    @AppStorage("kindaVim.showAdvancedHints") private var showAdvancedHints: Bool = false
    @AppStorage("kindaVim.showHintsInTerminals") private var showHintsInTerminals: Bool = false

    private var mode: KindaVimStateAdapter.Mode {
        guard let state, !state.isStale, state.mode != .unknown else {
            return .normal
        }
        return state.mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if strategyMonitor.currentStrategy == .ignored,
               !(showHintsInTerminals && VimHintLayer.isTerminalApp(strategyMonitor.currentBundleID))
            {
                ignoredStrategyHint
            } else if mode == .insert {
                insertModeHints
            } else {
                commandGrid
            }

            if hasLeaderShortcuts {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 10)
                leaderShortcutsFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Command grid (4 columns)

    private var commandGrid: some View {
        let allGroups = VimBindings.grouped(
            strategy: strategyMonitor.currentStrategy,
            mode: mode,
            showAdvanced: showAdvancedHints
        )
        let columns = distributeColumns(allGroups, count: 4)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 32) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, group in
                            groupSection(group)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if mode == .operatorPending {
                operatorPendingCallout
                    .padding(.top, 14)
            }
        }
    }

    private func distributeColumns(_ groups: [VimHintGroup], count: Int) -> [[VimHintGroup]] {
        guard !groups.isEmpty else { return [] }

        var columns: [[VimHintGroup]] = Array(repeating: [], count: count)
        var heights: [Int] = Array(repeating: 0, count: count)

        for group in groups {
            let weight = group.entries.count + 2
            guard let minIdx = heights.enumerated().min(by: { $0.element < $1.element })?.offset else { continue }
            columns[minIdx].append(group)
            heights[minIdx] += weight
        }

        return columns.filter { !$0.isEmpty }
    }

    // MARK: - Group section

    private func groupSection(_ group: VimHintGroup) -> some View {
        let isMovement = group.group == .movement

        return VStack(alignment: .leading, spacing: 8) {
            Text(group.displayName)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(group.entries) { entry in
                    entryRow(entry, loud: isMovement && entry.tier == .core)
                }
            }
        }
    }

    private func entryRow(_ hint: VimHint, loud: Bool) -> some View {
        HStack(spacing: 0) {
            Text(hint.displayLabel)
                .font(.system(size: loud ? 18 : 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: loud ? 40 : 32, alignment: .center)
                .padding(.vertical, loud ? 4 : 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(entryChipFill(hint, loud: loud))
                )

            Text(hint.actionLabel)
                .font(.system(size: loud ? 15 : 14))
                .foregroundStyle(.white.opacity(loud ? 0.85 : 0.5))
                .padding(.leading, 10)
        }
    }

    private func entryChipFill(_ hint: VimHint, loud: Bool) -> Color {
        if loud { return Color.accentColor.opacity(0.45) }
        switch hint.tier {
        case .core: return .white.opacity(0.12)
        case .secondary: return .white.opacity(0.07)
        case .advanced: return .white.opacity(0.04)
        }
    }

    // MARK: - Operator pending

    @ViewBuilder
    private var operatorPendingCallout: some View {
        if let op = sequenceObserver.currentOperator?.lowercased(),
           ["d", "c", "y"].contains(op)
        {
            Text("Press \(op) again for the whole line.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        } else {
            Text("Press the same operator twice (dd · yy · cc) to act on the whole line.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Insert / Ignored

    private var insertModeHints: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insert Mode")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(insertModeCommands, id: \.keys) { cmd in
                    HStack(spacing: 0) {
                        Text(cmd.keys)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.white.opacity(0.1))
                            )
                        Text(cmd.meaning)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.leading, 10)
                    }
                }
            }
        }
    }

    private var ignoredStrategyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KindaVim is off here")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white.opacity(0.5))
            Text("This app is in KindaVim's ignore list.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Leader shortcuts footer

    private var hasLeaderShortcuts: Bool {
        !groups.flatMap(\.entries).isEmpty
    }

    private var leaderShortcutsFooter: some View {
        let hintEntries = groups
            .flatMap(\.entries)
            .prefix(4)
            .map { "\($0.keycap.lowercased()) → \($0.action)" }

        return HStack(spacing: 6) {
            Text("Leader")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
            Text(hintEntries.joined(separator: "   "))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Data

    private struct CommandItem {
        let keys: String
        let meaning: String
    }

    private var insertModeCommands: [CommandItem] {
        [
            .init(keys: "Esc", meaning: "enter Normal mode"),
            .init(keys: "Ctrl-[", meaning: "alternate Esc"),
            .init(keys: "Leader hold", meaning: "open KeyPath motion keylist"),
        ]
    }
}
