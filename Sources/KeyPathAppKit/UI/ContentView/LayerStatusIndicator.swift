import SwiftUI

struct LayerStatusIndicator: View {
    let currentLayerName: String

    private var isBaseLayer: Bool {
        currentLayerName.caseInsensitiveCompare("base") == .orderedSame
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isBaseLayer ? Color.secondary.opacity(0.4) : Color.accentColor)
                .frame(width: 8, height: 8)
            Text(isBaseLayer ? "Base Layer" : "\(currentLayerName) Layer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current layer")
        .accessibilityValue(isBaseLayer ? "Base" : currentLayerName)
    }
}
