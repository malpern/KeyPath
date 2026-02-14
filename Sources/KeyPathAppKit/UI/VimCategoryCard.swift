import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct VimCategoryCard: View {
    let category: VimCategory
    let commands: [KeyMapping]

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.body.weight(.semibold))
                    .foregroundColor(isHovered ? .white : category.accentColor)
                    .symbolEffect(.bounce, value: isHovered)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? category.accentColor : category.accentColor.opacity(0.15))
                    )

                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // Special HJKL cluster for navigation
            if category == .navigation {
                VimArrowKeysCompact()
                    .padding(.vertical, 4)
            }

            // Command list
            VStack(alignment: .leading, spacing: 2) {
                ForEach(commands, id: \.id) { command in
                    VimCommandRowCompact(command: command, accentColor: category.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(category.accentColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: category.accentColor.opacity(isHovered ? 0.2 : 0), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
