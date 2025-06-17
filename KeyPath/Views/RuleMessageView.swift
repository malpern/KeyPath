import SwiftUI

struct RuleMessageView: View {
    let rule: KanataRule
    let onInstall: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Visual representation
            EnhancedRemapVisualizer(behavior: rule.visualization.behavior)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            
            // Explanation
            Text(rule.explanation)
                .font(.callout)
                .foregroundColor(.secondary)
            
            // Confidence indicator (if not high)
            if rule.confidence != .high {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Confidence: \(rule.confidence.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Install button
            Button(action: onInstall) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Install Rule")
                }
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.green)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
