import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Displays a layer-switch icon + label in keycap style for rules summary rows.
struct RulesSummaryLayerSwitchChip: View {
    let layerName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: LayerInfo.iconName(for: layerName))
                .font(.footnote.weight(.medium))
                .foregroundColor(KeycapStyle.textColor)
                .frame(width: 16, height: 16)

            Text("\(LayerInfo.displayName(for: layerName)) Layer")
                .font(.body.monospaced().weight(.semibold))
                .foregroundColor(KeycapStyle.textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .fill(Color.accentColor.opacity(0.2))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
        )
    }
}
