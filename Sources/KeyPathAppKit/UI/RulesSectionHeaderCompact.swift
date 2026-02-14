import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Compact section header for rule groups (e.g., "Everywhere")
struct RulesSectionHeaderCompact: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.bottom, 4)
    }
}
