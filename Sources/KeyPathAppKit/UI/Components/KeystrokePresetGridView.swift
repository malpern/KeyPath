import SwiftUI

struct KeystrokePresetGridView: View {
    let selectedKey: String?
    let onSelect: (String) -> Void

    static let presets: [(key: String, label: String, icon: String)] = [
        ("esc", String(localized: "Esc", comment: "Key name: Escape, abbreviated"), "escape"),
        ("enter", String(localized: "Return", comment: "Key name"), "return"),
        ("bspc", String(localized: "Backspace", comment: "Key name"), "delete.backward"),
        ("del", String(localized: "Delete", comment: "Key name"), "delete.forward"),
        ("tab", String(localized: "Tab", comment: "Key name"), "arrow.right.to.line"),
        ("spc", String(localized: "Space", comment: "Key name"), "space"),
        ("up", "↑", "arrow.up"),
        ("down", "↓", "arrow.down"),
        ("left", "←", "arrow.left"),
        ("right", "→", "arrow.right"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 4) {
            ForEach(Self.presets, id: \.key) { item in
                Button { onSelect(item.key) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.caption2)
                        Text(item.label)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selectedKey == item.key ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(selectedKey == item.key ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keystroke-preset-\(item.key)")
            }
        }
    }
}
