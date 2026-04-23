// M1 Gallery MVP — pack card, v2.
// v1 tried a row of keycap chips to "show what the pack does"; v2 drops
// that in favor of a single distinctive hero icon per pack, which makes
// the three starter packs legible as different things at a glance.
//
// Design constraints:
//   - No custom illustrations. Everything is SF Symbols + system color.
//   - Each pack carries its own icon/category in its manifest so the card
//     doesn't have to hardcode pack-specific art.
//   - Card is scannable in under a second — category chip, hero, name,
//     one-line tagline — in a single top-to-bottom read.

import AppKit
import SwiftUI

struct PackCardView: View {
    let pack: Pack
    let isInstalled: Bool
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                topRow
                hero
                copy
            }
            .padding(16)
            .frame(width: 260, height: 208, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
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
            // Pointing-hand cursor says "this is tappable" without the card
            // needing a visible affordance (button outline, etc).
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity,
                            pressing: { isPressed = $0 }, perform: {})
        .accessibilityLabel("\(pack.name). \(pack.category). \(pack.tagline)")
        .accessibilityHint(isInstalled ? "On. Double tap to open." : "Double tap to open pack detail.")
    }

    // MARK: - Anatomy

    /// Category chip on the left, installed badge on the right.
    private var topRow: some View {
        HStack(alignment: .center) {
            categoryChip
            Spacer(minLength: 8)
            if isInstalled {
                installedBadge
            }
        }
    }

    private var categoryChip: some View {
        Text(pack.category.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .separatorColor).opacity(0.4))
            )
    }

    private var installedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)
            Text("On")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)
        }
    }

    /// The hero zone. Centered icon on a soft tinted square. This is the
    /// single piece of visual that differs most between packs — a well-
    /// chosen primary symbol does most of the work.
    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(heroFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
                )

            heroIcon
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var heroIcon: some View {
        if let secondary = pack.iconSecondarySymbol {
            HStack(spacing: 8) {
                Image(systemName: pack.iconSymbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: secondary)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        } else {
            Image(systemName: pack.iconSymbol)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pack.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(pack.tagline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Style

    /// Hero area fill. Very light accent wash so the icon reads cleanly.
    private var heroFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.14),
                Color.accentColor.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 0.5)
    }
}
