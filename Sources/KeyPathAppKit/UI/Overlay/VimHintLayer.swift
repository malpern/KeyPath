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
    @AppStorage("kindaVim.showHintsInTerminals") private var showHintsInTerminals: Bool = false

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
        if strategyMonitor.currentStrategy == .ignored,
           !(showHintsInTerminals && Self.isTerminalApp(strategyMonitor.currentBundleID))
        { return false }
        switch adapter.state.mode {
        case .normal, .operatorPending, .visual: return true
        case .insert, .unknown: return false
        }
    }

    /// Whether the hint layer is currently rendering (for external consumers
    /// that need to suppress overlapping content like floating labels).
    @MainActor
    static var isCurrentlyRendering: Bool {
        let adapter = KindaVimStateAdapter.shared
        let monitor = KindaVimStrategyMonitor.shared
        if monitor.currentStrategy == .ignored { return false }
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

    private nonisolated static let terminalBundleIDs: Set<String> = [
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
    ]

    nonisolated static func isTerminalApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return terminalBundleIDs.contains(bundleID)
    }
}

// MARK: - Group colors (ViEmu-inspired pastels)

private func groupColor(for group: VimHint.Group) -> Color {
    switch group {
    case .movement: KeyPathColors.VimHint.movement
    case .wordMotion: KeyPathColors.VimHint.wordMotion
    case .lineMotion: KeyPathColors.VimHint.lineMotion
    case .enterInsert: KeyPathColors.VimHint.enterInsert
    case .edit: KeyPathColors.VimHint.edit
    case .operators: KeyPathColors.VimHint.operators
    case .findChar: KeyPathColors.VimHint.findChar
    case .doc: KeyPathColors.VimHint.lineMotion
    case .page: KeyPathColors.VimHint.page
    case .match: KeyPathColors.VimHint.match
    case .search: KeyPathColors.VimHint.search
    }
}

private func shortActionLabel(for hint: VimHint) -> String {
    // actionLabel is localized in VimBindings, so match it against the same
    // localized keys rather than English text.
    switch hint.actionLabel {
    case String(localized: "left"): String(localized: "left", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "down"): String(localized: "down", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "up"): String(localized: "up", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "right"): String(localized: "right", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "word forward"): String(localized: "word →", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "word back"): String(localized: "← word", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "end of word"): String(localized: "end", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "line start"): String(localized: "start", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "line end"): String(localized: "end", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "insert before cursor"): String(localized: "insert", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "append after cursor"): String(localized: "append", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "open line below"): String(localized: "open ↓", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "insert at line start"): String(localized: "Insert", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "append at line end"): String(localized: "Append", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "open line above"): String(localized: "open ↑", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "delete char"): String(localized: "del chr", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "replace char"): String(localized: "replace", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "undo"): String(localized: "undo", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "redo"): String(localized: "redo", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "delete (motion / dd line)"): String(localized: "delete", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "change (motion / cc line)"): String(localized: "change", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "yank (motion / yy line)"): String(localized: "yank", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "find char forward"): String(localized: "find →", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "find char backward"): String(localized: "← find", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "to char forward"): String(localized: "to →", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "to char backward"): String(localized: "← to", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "doc top"): String(localized: "top", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "doc bottom"): String(localized: "bottom", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "half page down"): String(localized: "½ pg ↓", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "half page up"): String(localized: "½ pg ↑", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "page down"): String(localized: "pg ↓", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "page up"): String(localized: "pg ↑", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "match bracket"): String(localized: "match", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "search forward"): String(localized: "search", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "search backward"): String(localized: "search", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "next match"): String(localized: "next", comment: "Very short Vim command hint shown on a keycap")
    case String(localized: "previous match"): String(localized: "prev", comment: "Very short Vim command hint shown on a keycap")
    default: String(hint.actionLabel.prefix(6))
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
            ZStack {
                // Fully opaque base to cover the keycap background
                RoundedRectangle(cornerRadius: max(4, 6 * scale), style: .continuous)
                    .fill(.black)
                // Group-colored tint on top
                RoundedRectangle(cornerRadius: max(4, 6 * scale), style: .continuous)
                    .fill(color.opacity(isDimmed ? 0.04 : fillOpacity))
                RoundedRectangle(cornerRadius: max(4, 6 * scale), style: .continuous)
                    .strokeBorder(color.opacity(isDimmed ? 0.06 : borderOpacity), lineWidth: max(1, 1.5 * scale))
                Text(hint.displayLabel)
                    .font(.system(size: max(10, 18 * scale), weight: .heavy))
                    .foregroundStyle(color.opacity(isDimmed ? 0.15 : labelOpacity))
            }
        } else {
            ZStack(alignment: .top) {
                fill
                Text(shortActionLabel(for: hint))
                    .font(.system(size: max(5, 6 * scale), weight: .heavy))
                    .foregroundStyle(color.opacity(isDimmed ? 0.15 : labelOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, max(2, 3 * scale))
                    .padding(.horizontal, max(1, 2 * scale))
            }
        }
    }

    private var fill: some View {
        RoundedRectangle(cornerRadius: max(4, 6 * scale), style: .continuous)
            .fill(color.opacity(isDimmed ? 0.03 : fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: max(4, 6 * scale), style: .continuous)
                    .strokeBorder(color.opacity(isDimmed ? 0.06 : borderOpacity), lineWidth: max(1, 1.5 * scale))
            )
    }

    private var color: Color {
        groupColor(for: hint.group)
    }

    private var fillOpacity: Double {
        switch hint.tier {
        case .core: 0.2
        case .secondary: 0.1
        case .advanced: 0.05
        }
    }

    private var borderOpacity: Double {
        switch hint.tier {
        case .core: 0.6
        case .secondary: 0.35
        case .advanced: 0.2
        }
    }

    private var labelOpacity: Double {
        switch hint.tier {
        case .core: 1.0
        case .secondary: 0.8
        case .advanced: 0.55
        }
    }
}
