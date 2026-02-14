import SwiftUI

struct VimArrowKeysCompact: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["H", "J", "K", "L"], id: \.self) { key in
                VimKeyBadge(key: key, color: .blue)
            }
            Text("= Arrow keys")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
