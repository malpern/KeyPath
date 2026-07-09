import KeyPathCore
import KeyPathRulesCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct RecommendedRulesSection: View {
    let recommendations: [(collection: RuleCollection, reason: String)]
    let onReview: (RuleCollection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recommended for you", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendations, id: \.collection.id) { item in
                        recommendationCard(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func recommendationCard(_ item: (collection: RuleCollection, reason: String)) -> some View {
        let pack = PackRegistry.starterKit.first { $0.associatedCollectionID == item.collection.id }

        return Button { onReview(item.collection) } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Hero icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                        )

                    heroIcon(pack: pack, collection: item.collection)
                }
                .frame(height: 72)

                // Title + reason
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack?.name ?? item.collection.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(width: 200, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(RecommendationCardButtonStyle())
        .accessibilityIdentifier("rules-recommendation-card-\(item.collection.id)")
        .accessibilityLabel("\(item.collection.name). \(item.reason)")
    }

    @ViewBuilder
    private func heroIcon(pack: Pack?, collection: RuleCollection) -> some View {
        let symbol = pack?.iconSymbol ?? collection.icon ?? "lightbulb"

        if let secondary = pack?.iconSecondarySymbol {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: secondary)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        } else {
            Image(systemName: symbol)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct RecommendationCardButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovering ? 1.02 : 1.0))
            .shadow(color: .black.opacity(isHovering ? 0.12 : 0.04),
                    radius: isHovering ? 8 : 2,
                    y: isHovering ? 4 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isHovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}
