// Small pill that surfaces the current KindaVim mode in the overlay
// header. Only renders when KindaVim Mode Display pack is installed and
// kindaVim is producing a mode signal — otherwise it draws nothing.

import SwiftUI

@MainActor
struct KindaVimModeBadge: View {
    @State private var adapter = KindaVimStateAdapter.shared
    @State private var sequenceObserver = VimSequenceObserver.shared
    @State private var strategyMonitor = KindaVimStrategyMonitor.shared
    @AppStorage("kindaVim.showHintsInTerminals") private var showHintsInTerminals: Bool = false
    let isPackInstalled: Bool

    var body: some View {
        if isPackInstalled, shouldRender {
            let mode = adapter.state.mode
            HStack(spacing: 4) {
                Text("VIM")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                Text(modeLabel(for: mode))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(tint(for: mode))
                if !sequenceObserver.countBuffer.isEmpty {
                    Text("\(sequenceObserver.countBuffer)×")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.accentColor.opacity(0.85))
                        )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint(for: mode).opacity(0.15))
            )
            .accessibilityIdentifier("kindavim-mode-badge")
            .accessibilityLabel(accessibilityDescription(for: mode))
        }
    }

    private func accessibilityDescription(for mode: KindaVimStateAdapter.Mode) -> String {
        var desc = "KindaVim mode: \(modeLabel(for: mode))"
        if !sequenceObserver.countBuffer.isEmpty {
            desc += ", count \(sequenceObserver.countBuffer)"
        }
        return desc
    }

    /// Don't surface a badge for `.unknown` — kindaVim hasn't published a
    /// signal yet. We deliberately do NOT gate on `isStale`: kindaVim writes
    /// the environment file only on mode transitions, so a user sitting in
    /// Normal mode for >5s would otherwise lose the badge despite the mode
    /// still being valid.
    private func modeLabel(for mode: KindaVimStateAdapter.Mode) -> String {
        if mode == .operatorPending, let op = sequenceObserver.currentOperator {
            if sequenceObserver.completedLineOp != nil {
                return "\(op.uppercased())\(op.uppercased())"
            }
            return "\(op.uppercased())…"
        }
        return mode.displayName.uppercased()
    }

    private var shouldRender: Bool {
        if strategyMonitor.currentStrategy == .ignored,
           !(showHintsInTerminals && VimHintLayer.isTerminalApp(strategyMonitor.currentBundleID))
        { return false }
        return adapter.state.mode != .unknown
    }

    private func tint(for mode: KindaVimStateAdapter.Mode) -> Color {
        switch mode {
        case .normal: .green
        case .insert: .blue
        case .visual: .orange
        case .operatorPending: .purple
        case .unknown: .secondary
        }
    }
}
