import SwiftUI

// MARK: - Snap Key Badge

struct SnapKeyBadge: View {
    let key: String
    let color: Color
    var isHighlighted: Bool = false
    var size: BadgeSize = .regular
    var label: String?

    /// Track displayed key and flip animation state
    @State private var displayedKey: String = ""
    @State private var flipAngle: Double = 0
    /// Randomized delay for this badge (0-0.15s)
    @State private var randomDelay: Double = 0
    /// Randomized duration multiplier (0.8-1.2x)
    @State private var durationMultiplier: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum BadgeSize {
        case small, regular, large

        var dimension: CGFloat {
            switch self {
            case .small: 22
            case .regular: 28
            case .large: 34
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 11
            case .regular: 13
            case .large: 15
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(displayedKey.uppercased())
                .font(.system(size: size.fontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(isHighlighted ? .white : color)
                .frame(width: size.dimension, height: size.dimension)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHighlighted ? color : color.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
                .scaleEffect(isHighlighted ? 1.1 : 1.0)
                .rotation3DEffect(
                    .degrees(flipAngle),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHighlighted)

            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            displayedKey = key
            // Generate random timing characteristics for this badge
            randomDelay = Double.random(in: 0 ... 0.12)
            durationMultiplier = Double.random(in: 0.8 ... 1.3)
        }
        .onChange(of: key) { oldKey, newKey in
            guard oldKey != newKey else { return }

            if reduceMotion {
                displayedKey = newKey
            } else {
                // Determine flip direction: Standard→Vim flips right (+90), Vim→Standard flips left (-90)
                // We detect direction by checking if we're going to a "vim-style" key
                let isGoingToVim = ["Y", "B", "N", "H"].contains(newKey.uppercased())
                let targetAngle: Double = isGoingToVim ? 90 : -90

                let baseDuration = 0.15 * durationMultiplier

                // Staggered start with random delay
                DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay) {
                    // Flip out (to 90 or -90)
                    withAnimation(.easeIn(duration: baseDuration)) {
                        flipAngle = targetAngle
                    }
                    // Change key at midpoint and flip back in
                    DispatchQueue.main.asyncAfter(deadline: .now() + baseDuration) {
                        displayedKey = newKey
                        withAnimation(.easeOut(duration: baseDuration)) {
                            flipAngle = 0
                        }
                    }
                }
            }
        }
    }
}
