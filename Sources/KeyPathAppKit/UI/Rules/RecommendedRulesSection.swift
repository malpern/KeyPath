import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct RecommendedRulesSection: View {
    let recommendations: [(collection: RuleCollection, reason: String)]
    let onReview: (RuleCollection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recommended for you", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            ForEach(recommendations, id: \.collection.id) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.collection.icon ?? "lightbulb")
                        .foregroundColor(.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.collection.name)
                            .font(.subheadline.weight(.semibold))
                        Text(item.reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button("Review") {
                        onReview(item.collection)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("rules-recommendation-review-\(item.collection.id)")
                    .accessibilityLabel("Review recommended rule \(item.collection.name)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
                )
                .accessibilityIdentifier("rules-recommendation-row-\(item.collection.id)")
            }
        }
    }
}
