import AppKit
import KeyPathCore
import SwiftUI

struct CustomRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var isPresentingNewRule = false
    @State private var editingRule: CustomRule?
    @State private var pendingDeleteRule: CustomRule?
    @State private var appKeymaps: [AppKeymap] = []
    @State private var pendingDeleteAppRule: (keymap: AppKeymap, override: AppKeyOverride)?

    private var sortedRules: [CustomRule] {
        let rules = kanataManager.customRules
        AppLogger.shared.log("📋 [CustomRulesView] sortedRules computed: \(rules.count) rules")
        for rule in rules {
            AppLogger.shared.log("📋 [CustomRulesView]   - '\(rule.input)' → '\(rule.output)' (enabled: \(rule.isEnabled))")
        }
        return rules.sorted { lhs, rhs in
            if lhs.isEnabled == rhs.isEnabled {
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                    == .orderedAscending
            }
            return lhs.isEnabled && !rhs.isEnabled
        }
    }

    /// Whether there are any rules to display (either custom rules or app-specific)
    private var hasAnyRules: Bool {
        !sortedRules.isEmpty || !appKeymaps.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Rules")
                        .font(.headline)
                    Text("These rules stay separate from presets so you can manage them independently.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    isPresentingNewRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            if !hasAnyRules {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(.secondary.opacity(0.3))

                        VStack(spacing: 4) {
                            Text("No Custom Rules Yet")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Text("Create personalized key mappings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        isPresentingNewRule = true
                    } label: {
                        Label("Create Your First Rule", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // MARK: - Everywhere Section

                        if !sortedRules.isEmpty {
                            RulesSectionHeader(
                                title: "Everywhere",
                                systemImage: "globe",
                                subtitle: "These rules apply in all apps"
                            )
                            .padding(.horizontal, 16)

                            ForEach(sortedRules) { rule in
                                CustomRuleRow(
                                    rule: rule,
                                    onToggle: { isOn in
                                        _ = Task { await kanataManager.toggleCustomRule(rule.id, enabled: isOn) }
                                    },
                                    onEdit: {
                                        editingRule = rule
                                    },
                                    onDelete: {
                                        pendingDeleteRule = rule
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                        }

                        // MARK: - App-Specific Sections

                        ForEach(appKeymaps) { keymap in
                            AppRulesSectionHeader(keymap: keymap)
                                .padding(.horizontal, 16)
                                .padding(.top, sortedRules.isEmpty ? 0 : 8)

                            ForEach(keymap.overrides) { override in
                                AppRuleRow(
                                    keymap: keymap,
                                    override: override,
                                    onDelete: {
                                        pendingDeleteAppRule = (keymap, override)
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear {
            loadAppKeymaps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appKeymapsDidChange)) { _ in
            loadAppKeymaps()
        }
        .sheet(isPresented: $isPresentingNewRule) {
            CustomRuleEditorView(
                rule: nil,
                existingRules: kanataManager.customRules
            ) { newRule in
                _ = Task { await kanataManager.saveCustomRule(newRule) }
            }
        }
        .sheet(item: $editingRule) { rule in
            CustomRuleEditorView(
                rule: rule,
                existingRules: kanataManager.customRules,
                onSave: { updatedRule in
                    _ = Task { await kanataManager.saveCustomRule(updatedRule) }
                },
                onDelete: { ruleToDelete in
                    AppLogger.shared.log("🗑️ [CustomRulesView] Delete from editor for rule: \(ruleToDelete.id)")
                    Task { await kanataManager.removeCustomRule(ruleToDelete.id) }
                }
            )
        }
        .alert(
            "Delete \"\(pendingDeleteRule?.displayTitle ?? "")\"?",
            isPresented: Binding(
                get: { pendingDeleteRule != nil },
                set: { if !$0 { pendingDeleteRule = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("custom-rules-delete-cancel-button")
                .accessibilityLabel("Cancel")
            Button("Delete", role: .destructive) {
                if let rule = pendingDeleteRule {
                    AppLogger.shared.log("🗑️ [CustomRulesView] Delete confirmed for rule: \(rule.id) '\(rule.displayTitle)'")
                    Task { await kanataManager.removeCustomRule(rule.id) }
                } else {
                    AppLogger.shared.log("⚠️ [CustomRulesView] Delete confirmed but pendingDeleteRule was nil!")
                }
                pendingDeleteRule = nil
            }
            .accessibilityIdentifier("custom-rules-delete-confirm-button")
            .accessibilityLabel("Delete rule")
        } message: {
            Text("This removes the rule from Custom Rules but leaves preset collections untouched.")
        }
        .alert(
            "Delete app rule?",
            isPresented: Binding(
                get: { pendingDeleteAppRule != nil },
                set: { if !$0 { pendingDeleteAppRule = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let pending = pendingDeleteAppRule {
                    deleteAppRule(keymap: pending.keymap, override: pending.override)
                }
                pendingDeleteAppRule = nil
            }
        } message: {
            if let pending = pendingDeleteAppRule {
                Text("Delete \(pending.override.inputKey) → \(pending.override.outputAction) from \(pending.keymap.mapping.displayName)?")
            }
        }
        .settingsBackground()
    }

    // MARK: - Helper Methods

    private func loadAppKeymaps() {
        Task {
            let keymaps = await AppKeymapStore.shared.loadKeymaps()
            await MainActor.run {
                appKeymaps = keymaps.sorted { $0.mapping.displayName < $1.mapping.displayName }
            }
        }
    }

    private func deleteAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        Task {
            var updatedKeymap = keymap
            updatedKeymap.overrides.removeAll { $0.id == override.id }

            do {
                if updatedKeymap.overrides.isEmpty {
                    try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                } else {
                    try await AppKeymapStore.shared.upsertKeymap(updatedKeymap)
                }

                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()

                _ = await kanataManager.underlyingManager.restartKanata(reason: "App rule deleted from Settings")
            } catch {
                AppLogger.shared.log("⚠️ [CustomRulesView] Failed to delete app rule: \(error)")
            }
        }
    }
}

private struct CustomRuleRow: View {
    let rule: CustomRule
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Extract app identifier from push-msg launch output
    private var appLaunchIdentifier: String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: rule.output)
    }

    /// Extract system action identifier from push-msg output
    private var systemActionIdentifier: String? {
        // Look for (push-msg "system:ACTION_NAME") pattern
        let pattern = #"\(push-msg\s+"system:([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: rule.output, range: NSRange(rule.output.startIndex..., in: rule.output)),
              let actionRange = Range(match.range(at: 1), in: rule.output)
        else {
            return nil
        }
        return String(rule.output[actionRange])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.displayTitle)
                        .font(.headline)

                    HStack(spacing: 8) {
                        KeyCapChip(text: rule.input)
                        Text("→")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Show appropriate chip based on action type
                        if let appId = appLaunchIdentifier {
                            AppLaunchChip(appIdentifier: appId)
                        } else if let actionId = systemActionIdentifier {
                            SystemActionChip(actionIdentifier: actionId)
                        } else {
                            KeyCapChip(text: rule.output)
                        }

                        // Behavior summary on same line
                        if let behavior = rule.behavior {
                            behaviorSummaryView(behavior: behavior)
                        }

                        Spacer(minLength: 0)
                    }

                    if let notes = rule.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { onToggle($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("custom-rules-toggle-\(rule.id)")
                .accessibilityLabel("Toggle \(rule.displayTitle)")

                Menu {
                    Button("Edit") { onEdit() }
                        .accessibilityIdentifier("custom-rules-menu-edit-button-\(rule.id)")
                        .accessibilityLabel("Edit rule")
                    Button("Delete", role: .destructive) { onDelete() }
                        .accessibilityIdentifier("custom-rules-menu-delete-button-\(rule.id)")
                        .accessibilityLabel("Delete rule")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .padding(.leading, 4)
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("custom-rules-menu-\(rule.id)")
                .accessibilityLabel("Rule options menu")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }

    @ViewBuilder
    private func behaviorSummaryView(behavior: MappingBehavior) -> some View {
        HStack(spacing: 6) {
            switch behavior {
            case let .dualRole(dr):
                behaviorItem(icon: "hand.point.up.left", label: "Hold", key: dr.holdAction)

            case let .tapDance(td):
                let behaviorItems = extractBehaviorItemsInEditOrder(from: td)

                if behaviorItems.isEmpty {
                    EmptyView()
                } else {
                    ForEach(Array(behaviorItems.enumerated()), id: \.offset) { itemIndex, item in
                        if itemIndex > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        behaviorItem(icon: item.0, label: item.1, key: item.2)
                    }
                }
            }
        }
        .foregroundColor(.secondary)
    }

    // Extract tap dance steps (skip index 0 which is single tap = output)
    private func extractBehaviorItemsInEditOrder(from td: TapDanceBehavior) -> [(String, String, String)] {
        var behaviorItems: [(String, String, String)] = []

        // Step 0 = single tap (shown as "Finish" already)
        // Step 1+ = double tap, triple tap, etc.
        let tapLabels = ["Double Tap", "Triple Tap", "Quad Tap", "5× Tap", "6× Tap", "7× Tap"]
        let tapIcons = ["hand.tap", "hand.tap", "hand.tap", "hand.tap", "hand.tap", "hand.tap"]

        for index in 1 ..< td.steps.count {
            let step = td.steps[index]
            guard !step.action.isEmpty else { continue }

            let labelIndex = index - 1
            let label = labelIndex < tapLabels.count ? tapLabels[labelIndex] : "\(index + 1)× Tap"
            let icon = labelIndex < tapIcons.count ? tapIcons[labelIndex] : "hand.tap"

            behaviorItems.append((icon, label, step.action))
        }

        return behaviorItems
    }

    @ViewBuilder
    private func behaviorItem(icon: String, label: String, key: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
            KeyCapChip(text: formatKeyForBehavior(key))
        }
    }

    private func formatKeyForBehavior(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "spc": "␣ Space",
            "space": "␣ Space",
            "caps": "⇪ Caps",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "bspc": "⌫ Delete",
            "del": "⌦ Fwd Del",
            "esc": "⎋ Escape",
            "lmet": "⌘ Cmd",
            "rmet": "⌘ Cmd",
            "lalt": "⌥ Opt",
            "ralt": "⌥ Opt",
            "lctl": "⌃ Ctrl",
            "rctl": "⌃ Ctrl",
            "lsft": "⇧ Shift",
            "rsft": "⇧ Shift"
        ]

        if let symbol = keySymbols[key.lowercased()] {
            return symbol
        }

        // Handle modifier prefixes
        var result = key
        var prefix = ""
        if result.hasPrefix("M-") {
            prefix = "⌘"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("C-") {
            prefix = "⌃"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("A-") {
            prefix = "⌥"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("S-") {
            prefix = "⇧"
            result = String(result.dropFirst(2))
        }

        if let symbol = keySymbols[result.lowercased()] {
            return prefix + symbol
        }

        return prefix + result.capitalized
    }
}

// MARK: - App Launch Chip

/// Displays an app icon and name in a chip style for app launch actions
private struct AppLaunchChip: View {
    let appIdentifier: String

    @State private var appIcon: NSImage?
    @State private var appName: String?

    var body: some View {
        HStack(spacing: 6) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }

            // App name
            Text(appName ?? appIdentifier)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
        .onAppear {
            loadAppInfo()
        }
    }

    private func loadAppInfo() {
        let workspace = NSWorkspace.shared

        // Try to find app by bundle identifier first
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appIdentifier) {
            loadFromURL(appURL)
            return
        }

        // Try common paths
        let appName = appIdentifier.hasSuffix(".app") ? appIdentifier : "\(appIdentifier).app"
        let commonPaths = [
            "/Applications/\(appName)",
            "/System/Applications/\(appName)",
            "\(NSHomeDirectory())/Applications/\(appName)"
        ]

        for path in commonPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                loadFromURL(url)
                return
            }
        }

        // Fallback: use identifier as name (capitalize it)
        let parts = appIdentifier.replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
        self.appName = parts.last.map { String($0) } ?? appIdentifier
    }

    private func loadFromURL(_ url: URL) {
        // Get icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32) // Request appropriate size
        appIcon = icon

        // Get app name from bundle
        if let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        {
            appName = name
        } else {
            // Use filename without extension
            appName = url.deletingPathExtension().lastPathComponent
        }
    }
}

// MARK: - System Action Chip

/// Displays an SF Symbol icon and action name in a chip style for system actions
private struct SystemActionChip: View {
    let actionIdentifier: String

    /// Get action info from SystemActionInfo (single source of truth)
    private var actionInfo: (icon: String, name: String) {
        // Use SystemActionInfo as the single source of truth
        if let action = SystemActionInfo.find(byOutput: actionIdentifier) {
            return (action.sfSymbol, action.name)
        }
        // Fallback for unknown actions
        return ("gearshape.fill", actionIdentifier.capitalized)
    }

    var body: some View {
        HStack(spacing: 6) {
            // System action SF Symbol
            Image(systemName: actionInfo.icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)

            // Action name
            Text(actionInfo.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Section Headers

/// Section header for rule groups (e.g., "Everywhere")
private struct RulesSectionHeader: View {
    let title: String
    let systemImage: String
    let subtitle: String?

    init(title: String, systemImage: String, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Section header for app-specific rules with app icon
private struct AppRulesSectionHeader: View {
    let keymap: AppKeymap

    @State private var appIcon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // App icon
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }

                Text(keymap.mapping.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            Text("Only applies when \(keymap.mapping.displayName) is active")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onAppear {
            loadAppIcon()
        }
    }

    private func loadAppIcon() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: keymap.mapping.bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 40, height: 40)
            appIcon = icon
        }
    }
}

// MARK: - App Rule Row

/// A row displaying an app-specific rule override
private struct AppRuleRow: View {
    let keymap: AppKeymap
    let override: AppKeyOverride
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Key mapping display
            HStack(spacing: 8) {
                KeyCapChip(text: override.inputKey.uppercased())

                Text("→")
                    .font(.caption)
                    .foregroundColor(.secondary)

                KeyCapChip(text: override.outputAction.uppercased())
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("app-rule-delete-\(override.id)")
            .accessibilityLabel("Delete rule \(override.inputKey) to \(override.outputAction)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-rule-row-\(override.id)")
    }
}
