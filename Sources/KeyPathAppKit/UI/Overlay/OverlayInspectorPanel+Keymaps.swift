import KeyPathCore
import SwiftUI

extension OverlayInspectorPanel {
    // MARK: - Keymaps Content

    var keymapsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 11))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("international-physical-layouts-link")
        }
    }
}
