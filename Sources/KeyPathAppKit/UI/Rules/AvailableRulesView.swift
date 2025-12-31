import AppKit
import KeyPathCore
import SwiftUI

struct AvailableRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    private let catalog = RuleCollectionCatalog()

    private var availableCollections: [RuleCollection] {
        let existing = Set(kanataManager.ruleCollections.map(\.id))
        return catalog.defaultCollections().filter { !existing.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(availableCollections) { collection in
                    AvailableRuleCollectionCard(collection: collection) {
                        activateCollection(collection)
                    }
                }

                if availableCollections.isEmpty {
                    Text("All built-in collections are active.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    private func activateCollection(_ collection: RuleCollection) {
        // Activate collection directly (welcome dialog moved to drawer's launcher tab)
        Task { await kanataManager.addRuleCollection(collection) }
    }
}

private struct AvailableRuleCollectionCard: View {
    let collection: RuleCollection
    let onActivate: () -> Void

    /// Format leader key for display (simplified version for available rules)
    private func formatLeaderKey(_ key: String) -> String {
        switch key.lowercased() {
        case "space", "spc":
            "␣ Space"
        case "leader":
            "Leader"
        default:
            key.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if let icon = collection.icon {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.headline)
                    Text(collection.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onActivate) {
                    Label("Activate", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("available-rules-activate-button-\(collection.id)")
                .accessibilityLabel("Activate \(collection.name)")
            }

            if !collection.mappings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(collection.mappings.prefix(6)) { mapping in
                            HStack(spacing: 4) {
                                // For leader-based rules, show "Leader + input" instead of just "input"
                                if let activator = collection.momentaryActivator {
                                    Text(String(localized: "\(formatLeaderKey(activator.input)) + \(mapping.input)"))
                                        .font(.caption.monospaced())
                                } else {
                                    Text(mapping.input)
                                        .font(.caption.monospaced())
                                }
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(mapping.output)
                                    .font(.caption.monospaced())
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        if collection.mappings.count > 6 {
                            Text("+\(collection.mappings.count - 6) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }
}
