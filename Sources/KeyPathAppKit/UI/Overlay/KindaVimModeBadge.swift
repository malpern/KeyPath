// Small pill that surfaces the current KindaVim mode in the overlay
// header. Only renders when KindaVim Mode Display pack is installed and
// kindaVim is producing a mode signal — otherwise it draws nothing.

import SwiftUI

@MainActor
struct KindaVimModeBadge: View {
    @State private var adapter = KindaVimStateAdapter.shared
    let isPackInstalled: Bool

    var body: some View {
        if isPackInstalled, shouldRender {
            let mode = adapter.state.mode
            HStack(spacing: 4) {
                Text("VIM")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                Text(mode.displayName.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(tint(for: mode))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint(for: mode).opacity(0.15))
            )
            .accessibilityLabel("KindaVim mode: \(mode.displayName)")
        }
    }

    /// Don't surface a badge for `.unknown` — kindaVim hasn't published a
    /// signal yet. We deliberately do NOT gate on `isStale`: kindaVim writes
    /// the environment file only on mode transitions, so a user sitting in
    /// Normal mode for >5s would otherwise lose the badge despite the mode
    /// still being valid.
    private var shouldRender: Bool {
        adapter.state.mode != .unknown
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
