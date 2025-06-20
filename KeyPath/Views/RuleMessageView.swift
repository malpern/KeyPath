import SwiftUI

struct RuleMessageView: View {
    let rule: KanataRule
    let onInstall: () -> Void
    @AppStorage("showKanataCode") private var showKanataCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Compact visual representation with code toggle
            VStack(alignment: .leading, spacing: 16) {
                CompactRuleVisualizer(
                    behavior: rule.visualization.behavior,
                    explanation: rule.explanation,
                    showCodeToggle: true
                )

                // Kanata code section (collapsible)
                if showKanataCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kanata rule:")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        KanataSyntaxHighlightedView(code: rule.kanataRule)
                            .frame(maxWidth: .infinity)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }

            // Install button
            Button(action: {
                print("🔧 DEBUG: Add Rule button pressed for rule: \(rule.explanation)")
                onInstall()
            }) {
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
