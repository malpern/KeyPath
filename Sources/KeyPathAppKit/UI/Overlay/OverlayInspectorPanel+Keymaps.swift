import KeyPathCore
import Observation
import SwiftUI

// MARK: - System Keymap Card

/// Card for the "System" keymap option — shows globe icon and current input source name.
private struct SystemKeymapCard: View {
    let isSelected: Bool
    let isDark: Bool
    let fadeAmount: CGFloat
    let onSelect: () -> Void

    @State private var isHovering = false

    /// Read input source name reactively from the provider
    private var inputSourceName: String {
        SystemKeyLabelProvider.shared.inputSourceName
    }

    private var cardFillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        return isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)
    }

    private var strokeColor: Color {
        isSelected ? Color.accentColor : Color.clear
    }

    private var subtitle: String {
        inputSourceName.isEmpty ? "Current Input Source" : inputSourceName
    }

    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-keymap-button-system")
        .accessibilityLabel("Select System keymap")
        .onHover { isHovering = $0 }
    }

    private var cardContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(isSelected ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("System")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardFillColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(strokeColor, lineWidth: 2)
        )
    }
}

extension OverlayInspectorPanel {
    // MARK: - Keymaps Content

    var keymapsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // System keymap card (uses current OS input source)
            SystemKeymapCard(
                isSelected: selectedKeymapId == "system",
                isDark: isDark,
                fadeAmount: fadeAmount
            ) {
                selectedKeymapId = "system"
            }

            // Alt layouts section (QWERTY + ergonomic layouts) - no header
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // QWERTY first
                KeymapCard(
                    keymap: LogicalKeymap.qwertyUS,
                    isSelected: selectedKeymapId == LogicalKeymap.qwertyUS.id,
                    isDark: isDark,
                    fadeAmount: fadeAmount
                ) {
                    selectedKeymapId = LogicalKeymap.qwertyUS.id
                }

                // Then alt layouts
                ForEach(LogicalKeymap.altLayouts) { keymap in
                    KeymapCard(
                        keymap: keymap,
                        isSelected: selectedKeymapId == keymap.id,
                        isDark: isDark,
                        fadeAmount: fadeAmount
                    ) {
                        selectedKeymapId = keymap.id
                    }
                }
            }

            // International layouts section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("International")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                }
                .padding(.leading, 4)
                .padding(.trailing, 4)
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(LogicalKeymap.internationalLayouts) { keymap in
                        KeymapCard(
                            keymap: keymap,
                            isSelected: selectedKeymapId == keymap.id,
                            isDark: isDark,
                            fadeAmount: fadeAmount
                        ) {
                            selectedKeymapId = keymap.id
                        }
                    }
                }
            }

            // Link to international physical layouts
            Button {
                onSelectSection(.layout)
                // Set scroll target after tab switch to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scrollToLayoutCategory = .international
                }
            } label: {
                HStack(spacing: 4) {
                    Text("International physical layouts")
                        .font(.caption)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("international-physical-layouts-link")
        }
    }
}
