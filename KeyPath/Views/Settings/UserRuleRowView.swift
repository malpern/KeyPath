import SwiftUI

struct UserRuleRowView: View {
    let rule: UserRule
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkbox
                Button(action: onToggle) {
                    Image(systemName: rule.isActive ? "checkmark.square.fill" : "square")
                        .foregroundColor(rule.isActive ? .accentColor : .secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .onTapGesture {
                    onToggle()
                }

                // Rule name and visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.kanataRule.visualization.description)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CompactRuleVisualizer(
                        behavior: rule.kanataRule.visualization.behavior, 
                        explanation: rule.kanataRule.explanation
                    )
                    .opacity(rule.isActive ? 1.0 : 0.6)
                }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Delete rule")
                .onTapGesture {
                    onDelete()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rule.isActive ? Color.clear : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}