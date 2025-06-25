import SwiftUI

struct ShowcaseRuleDetailView: View {
    let rule: ShowcaseRule
    let onBack: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text(rule.visualization.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Large visualization
                    VStack(spacing: 16) {
                        EnhancedRemapVisualizer(behavior: rule.visualization.behavior)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(rule.detailedExplanation)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        if !rule.visualization.description.isEmpty {
                            Text(rule.visualization.description)
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }

                    // Add Rule Button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installation")
                            .font(.headline)
                        
                        Button(action: onInstall) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add This Rule")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        
                        Text("This will add the rule to your active configuration.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Kanata code with syntax highlighting
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kanata Configuration")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            KanataSyntaxHighlightedView(code: rule.kanataRule)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}