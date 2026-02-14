import SwiftUI

// MARK: - Half Zone Button

struct HalfZoneButton: View {
    let zone: SnapZone
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    private var isHovered: Bool {
        hoveredZone == zone
    }

    var body: some View {
        HStack(spacing: 6) {
            if zone == .left {
                SnapKeyBadge(key: zone.key(for: convention), color: zone.color, isHighlighted: isHovered)
                Text(zone.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? zone.color : .secondary)
            } else {
                Text(zone.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? zone.color : .secondary)
                SnapKeyBadge(key: zone.key(for: convention), color: zone.color, isHighlighted: isHovered)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? zone.color.opacity(0.15) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredZone = hovering ? zone : nil
            }
        }
    }
}
