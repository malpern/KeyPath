import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Layer Switcher Button

/// Button that shows current layer and opens a menu to switch layers
struct LayerSwitcherButton: View {
    let currentLayer: String
    let onSelectLayer: (String) -> Void
    let onCreateLayer: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var displayName: String {
        currentLayer.lowercased() == "base" ? "Base Layer" : currentLayer.capitalized
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Menu {
            // Available layers
            ForEach(["base", "nav"], id: \.self) { layer in
                Button {
                    onSelectLayer(layer)
                } label: {
                    HStack {
                        Text(layer.lowercased() == "base" ? "Base Layer" : layer.capitalized)
                        Spacer()
                        if currentLayer.lowercased() == layer.lowercased() {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            // Create new layer
            Button {
                onCreateLayer()
            } label: {
                Label("New Layer...", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.15) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("mapper-layer-switcher")
        .accessibilityLabel("Current layer: \(displayName). Click to change layer.")
    }
}
