import SwiftUI

struct RuleMessageView: View {
    let rule: KanataRule
    let onInstall: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Compact visual representation like in settings
            VStack(alignment: .leading, spacing: 16) {
                CompactRuleVisualizer(
                    behavior: rule.visualization.behavior,
                    explanation: rule.explanation
                )
                
                // Kanata code on its own line
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kanata rule:")
                        .font(.callout)
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
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.green)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }
}
