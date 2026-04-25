// Renders a hint label on top of every keycap that has a corresponding
// command in `VimBindings`, while kindaVim is in a vim-y mode (normal /
// operator-pending / visual). Designed to live as a sibling layer inside
// `OverlayKeyboardView`'s `ZStack`, sharing its position math via the
// `keyFrame` builder passed from the parent.
//
// hjkl get the loudest treatment: large, accent-coloured arrow glyphs
// centered on the keycap. Other core/secondary hints render as a smaller
// chip pinned to the keycap's top-right corner. Advanced hints are gated
// behind the user's "Show all keys" toggle.

import KeyPathCore
import SwiftUI

@MainActor
struct VimHintLayer: View {
    let layout: PhysicalLayout
    let scale: CGFloat
    let keyFrame: (PhysicalKey) -> CGRect

    @State private var adapter = KindaVimStateAdapter.shared
    @State private var strategyMonitor = KindaVimStrategyMonitor.shared
    @AppStorage("kindaVim.showAdvancedHints") private var showAdvancedHints: Bool = false

    var body: some View {
        if shouldRender {
            ZStack(alignment: .topLeading) {
                ForEach(layout.keys, id: \.id) { key in
                    if let hint = hint(for: key) {
                        VimHintLabel(
                            hint: hint,
                            isLoud: isHjkl(key),
                            isDimmed: isDimmedInOperatorPending(hint: hint),
                            scale: scale
                        )
                        .frame(
                            width: keyFrame(key).width,
                            height: keyFrame(key).height
                        )
                        .position(
                            x: keyFrame(key).midX,
                            y: keyFrame(key).midY
                        )
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Visibility

    /// Render only while kindaVim is publishing a vim-y mode and the
    /// frontmost app isn't in kindaVim's ignore list. Insert mode and
    /// `.unknown` mode hide the layer entirely.
    private var shouldRender: Bool {
        guard strategyMonitor.currentStrategy != .ignored else { return false }
        switch adapter.state.mode {
        case .normal, .operatorPending, .visual: return true
        case .insert, .unknown: return false
        }
    }

    // MARK: - Per-key hint resolution

    /// Public-friendly lookup helper (also used by tests) that resolves
    /// a physical key to the `VimHint` that should render on it given
    /// the current strategy + mode + advanced flag.
    nonisolated static func resolveHint(
        for keyCode: UInt16,
        strategy: KindaVimStrategy,
        mode: KindaVimStateAdapter.Mode,
        showAdvanced: Bool
    ) -> VimHint? {
        let kanataName = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
        let candidates = VimBindings.hints(
            strategy: strategy,
            mode: mode,
            showAdvanced: showAdvanced
        )
        return candidates.first { hint in
            physicalKanataName(for: hint.key) == kanataName
        }
    }

    /// Translate a `VimHint.key` (which uses vim notation: `/`, `$`,
    /// `ctrl-d`, etc.) into the underlying physical kanata key name
    /// returned by `keyCodeToKanataName`. Returns an empty string for
    /// chord-only hints (e.g. `ctrl-d`) so they don't render on the
    /// `d` keycap and conflict with the `d` operator hint — chords
    /// belong in the HUD list, not the per-key overlay.
    nonisolated static func physicalKanataName(for vimKey: String) -> String {
        let lower = vimKey.lowercased()
        if lower.hasPrefix("ctrl-") {
            // Chord — suppress on the overlay; HUD list still surfaces it.
            return ""
        }
        switch lower {
        case "/", "?": return "slash"
        case "$": return "4"
        case "%": return "5"
        default: return lower
        }
    }

    private func hint(for key: PhysicalKey) -> VimHint? {
        Self.resolveHint(
            for: key.keyCode,
            strategy: strategyMonitor.currentStrategy,
            mode: adapter.state.mode,
            showAdvanced: showAdvancedHints
        )
    }

    private func isHjkl(_ key: PhysicalKey) -> Bool {
        let name = OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
        return ["h", "j", "k", "l"].contains(name)
    }

    /// Op-pending mode: keep motion targets bright, dim everything else
    /// (operators show through but at reduced strength as a "next step is
    /// a motion" cue).
    private func isDimmedInOperatorPending(hint: VimHint) -> Bool {
        guard adapter.state.mode == .operatorPending else { return false }
        let motionGroups: Set<VimHint.Group> = [
            .movement, .wordMotion, .lineMotion, .findChar, .doc,
        ]
        return !motionGroups.contains(hint.group)
    }
}

// MARK: - Per-key label

private struct VimHintLabel: View {
    let hint: VimHint
    let isLoud: Bool
    let isDimmed: Bool
    let scale: CGFloat

    var body: some View {
        if isLoud {
            // hjkl: large arrow glyph centered, normal label ghosts under it.
            Text(hint.displayLabel)
                .font(.system(size: max(14, 26 * scale), weight: .heavy))
                .foregroundStyle(Color.accentColor.opacity(opacity))
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 0.5)
        } else {
            // Other hints: small chip pinned top-right.
            VStack(alignment: .trailing) {
                HStack {
                    Spacer()
                    Text(hint.displayLabel)
                        .font(.system(size: max(7, 9 * scale), weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(opacity))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(chipFill)
                        )
                        .padding(2)
                }
                Spacer()
            }
        }
    }

    private var opacity: Double {
        if isDimmed { return 0.18 }
        switch hint.tier {
        case .core: return 1.0
        case .secondary: return 0.7
        case .advanced: return 0.5
        }
    }

    private var chipFill: Color {
        if isDimmed { return Color.black.opacity(0.25) }
        switch hint.tier {
        case .core: return Color.accentColor.opacity(0.55)
        case .secondary: return Color.accentColor.opacity(0.35)
        case .advanced: return Color.black.opacity(0.4)
        }
    }
}
