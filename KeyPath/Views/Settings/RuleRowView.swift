import SwiftUI

struct RuleRowView: View {
    let rule: MockRule
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
                .buttonStyle(PlainButtonStyle())
                .onTapGesture {
                    onToggle()
                }

                // Rule name and visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CompactRuleVisualizer(behavior: rule.behavior, explanation: rule.explanation)
                        .opacity(rule.isActive ? 1.0 : 0.6)
                }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Delete rule")
                .onTapGesture {
                    onDelete()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12) // Increased from 8 to 12 for 25% more height
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rule.isActive ? Color.clear : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}