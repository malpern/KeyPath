// M1 Gallery MVP — pack card for the Gallery list.
// Spec: docs/design/sprint-1/gallery-and-cards.md — default 240×140 pt card.
// Craft (illustration, color language) will iterate once we're in the runtime.

import AppKit
import SwiftUI

/// Card representing a single pack in the Gallery. Click → opens Pack Detail.
struct PackCardView: View {
    let pack: Pack
    let isInstalled: Bool
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                illustration
                copy
            }
            .frame(width: 240, height: 140, alignment: .topLeading)
            .background(background)
            .overlay(border)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : (isHovering ? 1.02 : 1.0))
        .shadow(color: .black.opacity(isHovering ? 0.14 : 0.06),
                radius: isHovering ? 10 : 3,
                y: isHovering ? 5 : 2)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isHovering)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onHover { hovering in
            isHovering = hovering
        }
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity,
                            pressing: { pressing in
                                isPressed = pressing
                            },
                            perform: {})
        .accessibilityLabel("\(pack.name). \(pack.tagline)")
        .accessibilityHint(isInstalled ? "Installed. Double tap to open." : "Double tap to open pack detail.")
    }

    // MARK: - Sub-views

    /// Upper ~60% of the card. Placeholder illustration until the visual
    /// designer iterates in-runtime.
    private var illustration: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(illustrationGradient)
                .padding(8)

            // Affected-keys indicator: small row of keycaps across the
            // illustration. Signals what keys this pack touches at a glance.
            keyIndicatorRow
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(12)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 84)
        .clipped()
    }

    /// Small row of stylized keycaps representing the keys the pack affects.
    /// This is intentionally minimal — full keyboard diagrams come later.
    private var keyIndicatorRow: some View {
        HStack(spacing: 3) {
            ForEach(Array(pack.affectedKeys.prefix(6).enumerated()), id: \.offset) { _, key in
                Text(displayLabel(for: key).uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
                    )
            }

            if pack.affectedKeys.count > 6 {
                Text("+\(pack.affectedKeys.count - 6)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.5))
                    .padding(.leading, 2)
            }
        }
    }

    /// Lower ~40% of the card — name + one-line tagline.
    private var copy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pack.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(pack.tagline)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Style

    private var illustrationGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.18),
                Color.accentColor.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
    }

    /// Kanata identifiers are lowercase tokens (`caps`, `lmet`, `rmet`).
    /// Users recognize letters like `d`/`f`/`j`/`k` directly; modifiers need
    /// translation to a symbol or short word.
    private func displayLabel(for kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        case "caps": "⇪"
        case "lmet": "⌘"
        case "rmet": "⌘"
        case "lalt": "⌥"
        case "ralt": "⌥"
        case "lctl": "⌃"
        case "rctl": "⌃"
        case "lsft": "⇧"
        case "rsft": "⇧"
        case "spc": "Space"
        case "ret", "enter": "⏎"
        case "tab": "⇥"
        case "esc": "⎋"
        case "bspc", "backspace": "⌫"
        case "del": "⌦"
        case "minus": "-"
        case "equal": "="
        default: kanataKey
        }
    }
}
