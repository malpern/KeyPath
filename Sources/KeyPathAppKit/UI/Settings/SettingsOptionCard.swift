import SwiftUI

/// Reusable horizontal option card for settings selections.
/// Displays an icon + title/subtitle with accent-colored selected state.
struct SettingsOptionCard: View {
    static let settingsRowWidth: CGFloat = 240

    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    var cardWidth: CGFloat?
    var onHoverChanged: ((Bool) -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(width: cardWidth, alignment: .leading)
            .frame(maxWidth: cardWidth == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.3)
                            : (isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)),
                        lineWidth: isSelected ? 1.5 : (isHovered ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth, alignment: .leading)
        .fixedSize(horizontal: cardWidth != nil, vertical: false)
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged?(hovering)
        }
        .accessibilityIdentifier("settings-option-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}
