import SwiftUI

struct VimKeyBadge: View {
    let key: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        Text(key)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(isHovered ? .white : color)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? color : color.opacity(0.15))
            )
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
