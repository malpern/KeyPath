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
                    .foregroundStyle(Color.secondary.opacity(0.5))
                Text("No active key mappings")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button(action: openConfigInEditor) {
                    Text("Edit your configuration to add key remapping rules.")
                        .font(.body)
                        .foregroundStyle(.secondary)
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
        openFileInPreferredEditor(url)
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
                        .foregroundStyle(.secondary)
                    if let activationDescription {
                        Label(activationDescription, systemImage: "hand.point.up.left")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { collection.isEnabled },
                        set: { onToggle($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.blue)

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
                .accessibilityHint("Show or hide mapping details")
            }

            if isExpanded {
                if collection.displayStyle == .table {
                    MappingTableView(collection: collection, prettyKeyName: prettyKeyName)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(collection.mappings.prefix(8)) { mapping in
                            HStack(spacing: 8) {
                                Text(mappingDescription(for: mapping))
                                    .font(.callout.monospaced().weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(.rect(cornerRadius: 6))

                                Image(systemName: "arrow.right")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                Text(mapping.output)
                                    .font(.callout.monospaced().weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(.rect(cornerRadius: 6))
                            }
                            .padding(.vertical, 2)
                        }

                        if collection.mappings.count > 8 {
                            Text("+\(collection.mappings.count - 8) more…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.leading, collection.icon == nil ? 0 : 4)
                    .padding(.top, 4)
                }
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
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
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

// MARK: - Mapping Table View

/// Table-style display for complex rule collections with modifier variants
private struct MappingTableView: View {
    let collection: RuleCollection
    let prettyKeyName: (String) -> String

    private var hasShiftVariants: Bool {
        collection.mappings.contains { $0.shiftedOutput != nil }
    }

    private var hasCtrlVariants: Bool {
        collection.mappings.contains { $0.ctrlOutput != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                headerCell("Key", width: 80)
                headerCell("Action", width: 120, alignment: .leading)
                if hasShiftVariants {
                    headerCell("+Shift", width: 100, color: .orange)
                }
                if hasCtrlVariants {
                    headerCell("+Ctrl", width: 100, color: .cyan)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Data rows
            ForEach(collection.mappings) { mapping in
                HStack(spacing: 0) {
                    keyCell(prettyKeyName(mapping.input), width: 80)
                    actionCell(formatOutput(mapping.output), width: 120)
                    if hasShiftVariants {
                        modifierCell(mapping.shiftedOutput.map { formatOutput($0) }, width: 100, color: .orange)
                    }
                    if hasCtrlVariants {
                        modifierCell(mapping.ctrlOutput.map { formatOutput($0) }, width: 100, color: .cyan)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if mapping.id != collection.mappings.last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .center, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    private func keyCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.callout.monospaced().weight(.medium))
            .foregroundStyle(.primary)
            .frame(width: width, alignment: .center)
    }

    @ViewBuilder
    private func actionCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func modifierCell(_ text: String?, width: CGFloat, color: Color) -> some View {
        if let text {
            Text(text)
                .font(.callout.monospaced())
                .foregroundStyle(color.opacity(0.8))
                .frame(width: width, alignment: .leading)
        } else {
            Text("—")
                .font(.callout)
                .foregroundStyle(Color.secondary.opacity(0.3))
                .frame(width: width, alignment: .center)
        }
    }

    /// Format output for display (convert Kanata codes to readable names)
    private func formatOutput(_ output: String) -> String {
        output
            .replacingOccurrences(of: "M-", with: "⌘")
            .replacingOccurrences(of: "A-", with: "⌥")
            .replacingOccurrences(of: "C-", with: "⌃")
            .replacingOccurrences(of: "S-", with: "⇧")
            .replacingOccurrences(of: "left", with: "←")
            .replacingOccurrences(of: "right", with: "→")
            .replacingOccurrences(of: "up", with: "↑")
            .replacingOccurrences(of: "down", with: "↓")
            .replacingOccurrences(of: "ret", with: "↩")
            .replacingOccurrences(of: "bspc", with: "⌫")
            .replacingOccurrences(of: "del", with: "⌦")
            .replacingOccurrences(of: "pgup", with: "PgUp")
            .replacingOccurrences(of: "pgdn", with: "PgDn")
            .replacingOccurrences(of: " ", with: " ")
    }
}
