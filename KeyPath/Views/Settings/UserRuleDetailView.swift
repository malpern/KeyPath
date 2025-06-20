import SwiftUI

struct UserRuleDetailView: View {
    let rule: UserRule
    let onBack: () -> Void

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

                Text(rule.kanataRule.visualization.description)
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
                        EnhancedRemapVisualizer(behavior: rule.kanataRule.visualization.behavior)
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

                    // Rule Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.headline)
                        HStack {
                            Image(systemName: rule.isActive ? "checkmark.circle.fill" : "pause.circle.fill")
                                .foregroundColor(rule.isActive ? .green : .orange)
                            Text(rule.isActive ? "Active" : "Inactive")
                                .foregroundColor(rule.isActive ? .green : .orange)
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(rule.kanataRule.explanation)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    // Creation Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Created")
                            .font(.headline)
                        Text(DateFormatter.localizedString(from: rule.dateCreated, dateStyle: .medium, timeStyle: .short))
                            .foregroundColor(.secondary)
                    }

                    // Last Modified Date
                    if rule.dateModified != rule.dateCreated {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last Modified")
                                .font(.headline)
                            Text(DateFormatter.localizedString(from: rule.dateModified, dateStyle: .medium, timeStyle: .short))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Kanata code with syntax highlighting
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kanata Configuration")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            KanataSyntaxHighlightedView(code: rule.kanataRule.completeKanataConfig)
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