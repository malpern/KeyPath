import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Multi-Legend, Launcher Mode, and Layer Mode Content

extension OverlayKeycapView {
    // MARK: - Multi-Legend Content (JIS/ISO)

    /// Renders a key with multiple legends in different positions
    /// Two layout modes based on key type:
    ///
    /// **Number row (has shiftLabel)**: 3-position layout
    /// - Top-left: shifted character (e.g., "!")
    /// - Bottom-left: main character (e.g., "1")
    /// - Bottom-right: hiragana (e.g., "ぬ")
    ///
    /// **Alpha keys (no shiftLabel)**: 2-position layout
    /// - Center: LARGE main character (e.g., "Q")
    /// - Bottom-right: small hiragana (e.g., "た")
    var multiLegendContent: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 3 * scale
            let subFontSize: CGFloat = 7 * scale

            // Choose layout based on whether key has shift label
            if key.shiftLabel != nil {
                // Number row style: 3-position layout
                let mainFontSize: CGFloat = 10 * scale
                let shiftFontSize: CGFloat = 8 * scale

                ZStack {
                    // Top-left: shift label (shifted character)
                    if let shiftLabel = key.shiftLabel {
                        Text(shiftLabel)
                            .font(.system(size: shiftFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.7))
                            .position(
                                x: padding + shiftFontSize / 2,
                                y: padding + shiftFontSize / 2
                            )
                    }

                    // Top-right: tertiary label (optional)
                    if let tertiaryLabel = key.tertiaryLabel {
                        Text(tertiaryLabel)
                            .font(.system(size: subFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.5))
                            .position(
                                x: geometry.size.width - padding - subFontSize / 2,
                                y: padding + subFontSize / 2
                            )
                    }

                    // Bottom-left: main label (primary character)
                    Text(key.label)
                        .font(.system(size: mainFontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .position(
                            x: padding + mainFontSize / 2,
                            y: geometry.size.height - padding - mainFontSize / 2
                        )

                    // Bottom-right: sub label (hiragana/katakana)
                    if let subLabel = key.subLabel {
                        Text(subLabel)
                            .font(.system(size: subFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.6))
                            .position(
                                x: geometry.size.width - padding - subFontSize / 2,
                                y: geometry.size.height - padding - subFontSize / 2
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                // Alpha key style: large centered letter + small bottom-right hiragana
                let mainFontSize: CGFloat = 14 * scale

                ZStack {
                    // Center: LARGE main character
                    Text(key.label.uppercased())
                        .font(.system(size: mainFontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom-right: small hiragana
                    if let subLabel = key.subLabel {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(subLabel)
                                    .font(.system(size: subFontSize, weight: .regular))
                                    .foregroundStyle(foregroundColor.opacity(0.5))
                                    .padding(.trailing, padding)
                                    .padding(.bottom, padding)
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    // Layer mode rendering has moved to LayerModeKeycap.swift
}
