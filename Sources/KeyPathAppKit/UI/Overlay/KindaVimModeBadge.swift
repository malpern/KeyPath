// Small pill that surfaces the current KindaVim mode in the overlay
// header. Only renders when KindaVim Mode Display pack is installed and
// kindaVim is producing a mode signal — otherwise it draws nothing.

import SwiftUI

@MainActor
struct KindaVimModeBadge: View {
    @State private var monitor = KindaVimModeMonitor.shared
    let isPackInstalled: Bool

    var body: some View {
        if isPackInstalled, let mode = monitor.mode {
            HStack(spacing: 4) {
                Text("VIM")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                Text(mode.displayLabel.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(tint(for: mode))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint(for: mode).opacity(0.15))
            )
            .accessibilityLabel("KindaVim mode: \(mode.displayLabel)")
        }
    }

    private func tint(for mode: KindaVimModeMonitor.Mode) -> Color {
        switch mode {
        case .normal: .green
        case .insert: .blue
        case .visual: .orange
        case .operatorPending: .purple
        }
    }
}
