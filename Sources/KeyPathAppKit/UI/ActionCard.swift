import SwiftUI

// MARK: - Action Card

struct ActionCard<Content: View>: View {
    let icon: String
    let title: String
    let isHovered: Bool
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(isHovered ? .white : accentColor)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered ? accentColor : accentColor.opacity(0.15))
                    )

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }

            // Content
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(isHovered ? 0.4 : 0.15), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}
