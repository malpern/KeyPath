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
            
            // Kanata code with syntax highlighting
            KanataSyntaxHighlightedView(code: rule.kanataRule)
                .frame(maxWidth: .infinity)
            
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
