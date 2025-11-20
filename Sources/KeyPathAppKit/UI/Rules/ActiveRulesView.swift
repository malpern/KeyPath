import AppKit
import KeyPathCore
import SwiftUI

struct ActiveRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var isHoveringEmptyState = false

    var body: some View {
        if kanataManager.ruleCollections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No active key mappings")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Button(action: openConfigInEditor) {
                    Text("Edit your configuration to add key remapping rules.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .opacity(isHoveringEmptyState ? 0.7 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringEmptyState = hovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .settingsBackground()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(kanataManager.ruleCollections) { collection in
                        RuleCollectionRow(
                            collection: collection,
                            onToggle: { isOn in
                                Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
                            }
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .settingsBackground()
        }
    }

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        NSWorkspace.shared.open(url)
        AppLogger.shared.log("📝 [Rules] Opened config for editing")
    }
}

private struct RuleCollectionRow: View {
    let collection: RuleCollection
    let onToggle: (Bool) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let icon = collection.icon {
                    iconView(for: icon)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.headline)
                    Text(collection.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let activationDescription {
                        Label(activationDescription, systemImage: "hand.point.up.left")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { collection.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.blue)

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(collection.mappings.prefix(8)) { mapping in
                        HStack(spacing: 8) {
                            Text(mappingDescription(for: mapping))
                                .font(.callout.monospaced().weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)

                            Image(systemName: "arrow.right")
                                .font(.callout)
                                .foregroundColor(.secondary)

                            Text(mapping.output)
                                .font(.callout.monospaced().weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .padding(.vertical, 2)
                    }

                    if collection.mappings.count > 8 {
                        Text("+\(collection.mappings.count - 8) more…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, collection.icon == nil ? 0 : 4)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor.windowBackgroundColor))
        )
    }
}

private extension RuleCollectionRow {
    @ViewBuilder
    func iconView(for icon: String) -> some View {
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary)
        }
    }

    var activationDescription: String? {
        if let hint = collection.activationHint { return hint }
        if let activator = collection.momentaryActivator {
            return "Hold \(prettyKeyName(activator.input)) for \(activator.targetLayer.displayName)"
        }
        return nil
    }

    func mappingDescription(for mapping: KeyMapping) -> String {
        guard let activator = collection.momentaryActivator else {
            return prettyKeyName(mapping.input)
        }
        return "Hold \(prettyKeyName(activator.input)) + \(prettyKeyName(mapping.input))"
    }

    func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}
