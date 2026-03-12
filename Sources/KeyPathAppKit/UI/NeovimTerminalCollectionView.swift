import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Rules tab expanded view for the Neovim Terminal collection.
struct NeovimTerminalCollectionView: View {
    let mappings: [KeyMapping]
    @Environment(\.services) private var services
    @State private var selectedTopics: Set<String> = PreferencesService.shared.neovimReferenceTopics
    @State private var hoveredTopic: NeovimTerminalCategory?
    @State private var hoveredCommandMeaningByTopic: [String: String] = [:]

    private struct CommandChip: Identifiable, Hashable {
        let key: String
        let meaning: String

        var id: String { "\(key)|\(meaning)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            terminalScopeSection
            topicsChecklist
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            selectedTopics = services.preferences.neovimReferenceTopics
        }
        .onChange(of: selectedTopics) { _, newValue in
            services.preferences.neovimReferenceTopics = newValue
        }
    }

    private var terminalScopeSection: some View {
        let approvedApps = NeovimTerminalScope.approvedApps
        let installedApps = NeovimTerminalScope.installedApprovedApps()
        let installedBundleIDs = Set(installedApps.map(\.bundleIdentifier))
        let additionalSupportedApps = approvedApps.filter { !installedBundleIDs.contains($0.bundleIdentifier) }
        let frontmostTerminal = NeovimTerminalScope.frontmostApprovedTerminal()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Terminal App Scope")
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)

            Text("This is an app-specific rule. In approved terminal apps, Neovim reference takes precedence. Outside them, other Navigation rules apply.")
                .font(.caption)
                .foregroundColor(.secondary)

            if installedApps.isEmpty {
                Text("Install one of the supported terminal apps below to unlock this rule.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Neovim display shown in")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)

                        appListGrid(installedApps)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Additional supported terminal apps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                if additionalSupportedApps.isEmpty {
                    Text("All supported terminal apps are installed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    additionalSupportedAppList(additionalSupportedApps)
                }
            }

            if let frontmostTerminal {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.green)
                    Text("Active now: \(frontmostTerminal.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.38))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var topicsChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            topicsChecklistHeader
            topicsChecklistGrid
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var topicsChecklistHeader: some View {
        HStack {
            Text("Reference Topics")
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
            Button("Restore Defaults") {
                selectedTopics = NeovimTerminalCategory.defaultRawValues
            }
            .buttonStyle(.link)
            .font(.subheadline)
            .accessibilityIdentifier("neovim-reference-restore-defaults-button")
            .accessibilityLabel("Restore default Neovim reference topics")
        }
    }

    private var topicsChecklistGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 280), spacing: 12),
                GridItem(.flexible(minimum: 280), spacing: 12),
            ],
            spacing: 12
        ) {
            ForEach(NeovimTerminalCategory.allCases) { category in
                topicCard(category)
            }
        }
    }

    private func topicCard(_ category: NeovimTerminalCategory) -> some View {
        let isHovered = hoveredTopic == category

        return Button {
            toggleTopic(category)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    topicToggleRow(category, isHovered: isHovered)
                    topicMappings(category)
                    topicDetail(category)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(category.accentColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: isHovered ? 2 : 1)
                )
                .shadow(color: category.accentColor.opacity(isHovered ? 0.2 : 0), radius: 8, x: 0, y: 4)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

                Image(systemName: selectedTopics.contains(category.rawValue) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(selectedTopics.contains(category.rawValue) ? category.accentColor : .secondary)
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTopic = hovering ? category : (hoveredTopic == category ? nil : hoveredTopic)
        }
        .accessibilityIdentifier("neovim-topic-\(category.rawValue)-checkbox")
        .accessibilityLabel("Neovim topic \(category.title)")
    }

    private func topicToggleRow(_ category: NeovimTerminalCategory, isHovered: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: category.icon)
                .font(.body.weight(.semibold))
                .foregroundColor(isHovered ? .white : category.accentColor)
                .symbolEffect(.bounce, value: isHovered)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? category.accentColor : category.accentColor.opacity(0.15))
                )

            HStack(spacing: 8) {
                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                if category.isNeovimSpecific {
                    Text("Neovim")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
        }
        .padding(.trailing, 28)
    }

    private func topicMappings(_ category: NeovimTerminalCategory) -> some View {
        let rows = commandRows(for: expandedCommandChips(for: category))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.id) { command in
                        commandChip(command, category: category)
                    }
                }
            }
        }
        .padding(.leading, 46)
        .frame(maxWidth: .infinity, minHeight: 156, maxHeight: 156, alignment: .topLeading)
    }

    private func topicDetail(_ category: NeovimTerminalCategory) -> some View {
        Text(hoveredCommandMeaningByTopic[category.rawValue] ?? "Hover a shortcut chip to preview what it does.")
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.leading, 46)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .topLeading)
    }

    private func commandRows(for commands: [CommandChip]) -> [[CommandChip]] {
        guard !commands.isEmpty else { return [] }
        let maxPerRow = 3
        var rows: [[CommandChip]] = []
        var index = 0
        while index < commands.count {
            let end = min(index + maxPerRow, commands.count)
            rows.append(Array(commands[index ..< end]))
            index = end
        }
        return rows
    }

    private func commandChip(_ command: CommandChip, category: NeovimTerminalCategory) -> some View {
        StandardKeyBadge(key: command.key, color: category.accentColor, uppercase: false)
            .help(command.meaning)
            .onHover { hovering in
                if hovering {
                    hoveredCommandMeaningByTopic[category.rawValue] = command.meaning
                } else if hoveredCommandMeaningByTopic[category.rawValue] == command.meaning {
                    hoveredCommandMeaningByTopic.removeValue(forKey: category.rawValue)
                }
            }
    }

    private func appListGrid(_ apps: [NeovimTerminalScope.AppDescriptor]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 145), spacing: 6)],
            spacing: 6
        ) {
            ForEach(apps) { app in
                appNameChip(app)
            }
        }
    }

    private func appNameChip(_ app: NeovimTerminalScope.AppDescriptor) -> some View {
        HStack(spacing: 6) {
            if let icon = appIcon(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "terminal")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
            }

            Text(app.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func additionalSupportedAppList(_ apps: [NeovimTerminalScope.AppDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(apps) { app in
                Text("• \(app.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func appIcon(for app: NeovimTerminalScope.AppDescriptor) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 14, height: 14)
        return icon
    }

    private func expandedCommandChips(for category: NeovimTerminalCategory) -> [CommandChip] {
        var chips: [CommandChip] = []
        var seen: Set<String> = []

        for command in category.commands {
            for token in expandCommandKeys(command.keys) {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let dedupeId = "\(trimmed)|\(command.meaning)"
                if seen.insert(dedupeId).inserted {
                    chips.append(CommandChip(key: trimmed, meaning: command.meaning))
                }
            }
        }

        return chips
    }

    private func expandCommandKeys(_ keys: String) -> [String] {
        let compact = keys
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return [] }

        if isCtrlWCommand(compact) {
            let suffix = stripCtrlWPrefix(compact)
            if suffix.contains("/") {
                let parts = suffix
                    .split(separator: "/")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !parts.isEmpty {
                    return parts.map { "⌃ w \($0)" }
                }
            }
        }

        if compact.contains(" / ") {
            let parts = compact.components(separatedBy: " / ")
            if parts.count == 2, isCtrlWCommand(parts[0]) {
                let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !right.contains(" "), !right.isEmpty {
                    return [normalizeCtrlNotation(left), "⌃ w \(right)"]
                }
            }
        }

        return compact.split(separator: " ").map { normalizeCtrlNotation(String($0)) }
    }

    private func isCtrlWCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("Ctrl-w ") || trimmed.hasPrefix("⌃w ") || trimmed.hasPrefix("⌃ w ")
    }

    private func stripCtrlWPrefix(_ text: String) -> String {
        if text.hasPrefix("Ctrl-w ") {
            return String(text.dropFirst("Ctrl-w ".count))
        }
        if text.hasPrefix("⌃w ") {
            return String(text.dropFirst("⌃w ".count))
        }
        if text.hasPrefix("⌃ w ") {
            return String(text.dropFirst("⌃ w ".count))
        }
        return text
    }

    private func normalizeCtrlNotation(_ token: String) -> String {
        token
            .replacingOccurrences(of: "Ctrl-w", with: "⌃ w")
            .replacingOccurrences(of: "⌃w", with: "⌃ w")
            .replacingOccurrences(of: "Ctrl-", with: "⌃")
    }

    private func toggleTopic(_ category: NeovimTerminalCategory) {
        var updated = selectedTopics
        if updated.contains(category.rawValue) {
            updated.remove(category.rawValue)
        } else {
            updated.insert(category.rawValue)
        }

        if updated.isEmpty {
            updated = NeovimTerminalCategory.defaultRawValues
        }

        selectedTopics = updated
    }
}
