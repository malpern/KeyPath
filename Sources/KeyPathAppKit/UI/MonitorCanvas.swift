import SwiftUI

// MARK: - Monitor Canvas

/// A stylized monitor showing window snap zones with embedded key badges.
struct MonitorCanvas: View {
    let convention: WindowKeyConvention
    @State private var hoveredZone: SnapZone?

    var body: some View {
        VStack(spacing: 12) {
            // Quarter zones grid
            QuarterZonesGrid(convention: convention, hoveredZone: $hoveredZone)

            // Halves axis with maximize
            HalvesAxis(convention: convention, hoveredZone: $hoveredZone)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
