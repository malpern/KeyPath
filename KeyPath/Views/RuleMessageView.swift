import SwiftUI

struct RuleMessageView: View {
    let rule: KanataRule
    let onInstall: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Compact visual representation like in settings
            VStack(alignment: .leading, spacing: 12) {
                CompactRuleVisualizer(
                    behavior: rule.visualization.behavior,
                    explanation: rule.explanation
                )
                
                // Kanata code on its own line
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kanata rule:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    KanataSyntaxHighlightedView(code: rule.kanataRule)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Install button
            Button(action: onInstall) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Rule")
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
