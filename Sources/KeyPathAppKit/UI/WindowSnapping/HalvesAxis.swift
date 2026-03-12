import SwiftUI

// MARK: - Halves Axis

struct HalvesAxis: View {
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Left half
                HalfZoneButton(zone: .left, convention: convention, hoveredZone: $hoveredZone)

                // Visual connector
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)

                // Maximize (center of axis)
                SnapKeyBadge(
                    key: SnapZone.maximize.key(for: convention),
                    color: SnapZone.maximize.color,
                    isHighlighted: hoveredZone == .maximize,
                    size: .large
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredZone = hovering ? .maximize : nil
                    }
                }

                // Visual connector
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)

                // Right half
                HalfZoneButton(zone: .right, convention: convention, hoveredZone: $hoveredZone)
            }

            // Center button below
            HStack {
                Spacer()
                SnapKeyBadge(
                    key: SnapZone.center.key(for: convention),
                    color: SnapZone.center.color,
                    isHighlighted: hoveredZone == .center,
                    label: "Center"
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredZone = hovering ? .center : nil
                    }
                }
                Spacer()
            }
        }
    }
}
