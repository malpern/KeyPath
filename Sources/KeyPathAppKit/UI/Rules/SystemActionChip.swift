import KeyPathCore
import SwiftUI

// MARK: - System Action Chip

/// Displays an SF Symbol icon and action name in a chip style for system actions
struct SystemActionChip: View {
    let actionIdentifier: String

    /// Get action info from SystemActionInfo (single source of truth)
    private var actionInfo: (icon: String, name: String) {
        // Use SystemActionInfo as the single source of truth
        if let action = SystemActionInfo.find(byOutput: actionIdentifier) {
            return (action.sfSymbol, action.name)
        }
        // Fallback for unknown actions
        return ("gearshape.fill", actionIdentifier.capitalized)
    }

    var body: some View {
        HStack(spacing: 6) {
            // System action SF Symbol
            Image(systemName: actionInfo.icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)

            // Action name
            Text(actionInfo.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}
