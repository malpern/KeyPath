import SwiftUI

// MARK: - Zone Cell

struct ZoneCell: View {
    let zone: SnapZone
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    private var isHovered: Bool {
        hoveredZone == zone
    }

    var body: some View {
        ZStack {
            // Background fill on hover
            Rectangle()
                .fill(isHovered ? zone.color.opacity(0.3) : Color.clear)

            // Key badge
            SnapKeyBadge(
                key: zone.key(for: convention),
                color: zone.color,
                isHighlighted: isHovered
            )

            // Zone label (shown on hover)
            if isHovered {
                VStack {
                    Spacer()
                    Text(zone.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(zone.color)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredZone = hovering ? zone : nil
            }
        }
    }
}
