import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Displays a system action icon + name in keycap style for rules summary rows.
struct RulesSummarySystemActionChip: View {
    let actionIdentifier: String

    private var actionInfo: SystemActionInfo? {
        SystemActionInfo.find(byOutput: actionIdentifier)
    }

    private var iconName: String {
        actionInfo?.sfSymbol ?? "gearshape.fill"
    }

    private var displayName: String {
        actionInfo?.name ?? actionIdentifier.capitalized
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.footnote.weight(.medium))
                .foregroundColor(KeycapStyle.textColor)
                .frame(width: 16, height: 16)

            Text(displayName)
                .font(.body.monospaced().weight(.semibold))
                .foregroundColor(KeycapStyle.textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .fill(Color.accentColor.opacity(0.25))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 0.5)
        )
    }
}
