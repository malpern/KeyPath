import SwiftUI

struct VimArrowKeysCompact: View {
    private let mappings: [(String, String)] = [
        ("h", "←"),
        ("j", "↓"),
        ("k", "↑"),
        ("l", "→"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(mappings, id: \.0) { mapping in
                HStack(spacing: 4) {
                    VimKeyBadge(key: mapping.0, color: .blue)
                    Text(mapping.1)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
