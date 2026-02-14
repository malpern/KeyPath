import KeyPathCore
import SwiftUI

// MARK: - Layer Switch Chip

/// Displays a layer icon and "X Layer" name for layer-switch actions
struct LayerSwitchChip: View {
    let layerName: String

    /// The SF Symbol icon for this layer
    private var layerIcon: String {
        LayerInfo.iconName(for: layerName)
    }

    /// Human-readable display name with "Layer" suffix
    private var displayName: String {
        "\(LayerInfo.displayName(for: layerName)) Layer"
    }

    var body: some View {
        HStack(spacing: 5) {
            // Layer icon
            Image(systemName: layerIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)

            // Layer name (e.g., "Nav Layer")
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}
