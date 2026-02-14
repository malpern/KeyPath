import SwiftUI

// MARK: - Quarter Zones Grid

struct QuarterZonesGrid: View {
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    var body: some View {
        // Monitor frame
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZoneCell(zone: .topLeft, convention: convention, hoveredZone: $hoveredZone)
                ZoneDivider(orientation: .vertical)
                ZoneCell(zone: .topRight, convention: convention, hoveredZone: $hoveredZone)
            }
            ZoneDivider(orientation: .horizontal)
            HStack(spacing: 0) {
                ZoneCell(zone: .bottomLeft, convention: convention, hoveredZone: $hoveredZone)
                ZoneDivider(orientation: .vertical)
                ZoneCell(zone: .bottomRight, convention: convention, hoveredZone: $hoveredZone)
            }
        }
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}
