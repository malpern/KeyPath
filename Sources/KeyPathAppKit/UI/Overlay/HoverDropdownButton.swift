import AppKit
import SwiftUI

struct HoverDropdownButton: View {
    let text: String
    var sfSymbol: String? = nil
    var icon: (name: String, image: NSImage?)? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon, let nsImage = icon.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 12, height: 12)
                } else if let icon, !icon.name.isEmpty {
                    Image(systemName: icon.name)
                        .font(.system(size: 10))
                } else if let sfSymbol {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 10))
                }
                Text(text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(isHovering ? 1 : 0.4)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
