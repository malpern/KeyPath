import KeyPathCore
import SwiftUI

struct VimCommandRowCompact: View {
    let command: KeyMapping
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            // Key
            StandardKeyBadge(key: command.input, color: accentColor, uppercase: false)

            // Description
            if let desc = command.description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Modifier indicators
            if command.shiftedOutput != nil {
                Text("⇧")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            if command.ctrlOutput != nil {
                Text("⌃")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
        }
        .padding(.vertical, 2)
    }
}
