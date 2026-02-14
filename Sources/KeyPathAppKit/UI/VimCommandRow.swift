import KeyPathCore
import SwiftUI

struct VimCommandRow: View {
    let command: KeyMapping
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            // Key
            StandardKeyBadge(key: command.input, color: accentColor)

            // Description
            if let desc = command.description {
                Text(desc)
                    .font(.footnote)
                    .foregroundColor(.primary)
            }

            Spacer()

            // Shift variant indicator
            if command.shiftedOutput != nil {
                HStack(spacing: 2) {
                    Text("+⇧")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                }
            }

            // Ctrl variant indicator
            if command.ctrlOutput != nil {
                HStack(spacing: 2) {
                    Text("+⌃")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
