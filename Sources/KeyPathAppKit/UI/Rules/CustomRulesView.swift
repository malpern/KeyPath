import AppKit
import KeyPathCore
import SwiftUI

struct CustomRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var isPresentingNewRule = false
    @State private var editingRule: CustomRule?
    @State private var pendingDeleteRule: CustomRule?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Rules")
                        .font(.headline)
                    Text("These rules stay separate from presets so you can manage them independently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            if sortedRules.isEmpty {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundStyle(Color.secondary.opacity(0.3))

                        VStack(spacing: 4) {
                            Text("No Custom Rules Yet")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("Create personalized key mappings")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                    LazyVStack(spacing: 12) {
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
                    .padding(.vertical, 12)
                }
            }
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
            Button("Delete", role: .destructive) {
                if let rule = pendingDeleteRule {
                    AppLogger.shared.log("🗑️ [CustomRulesView] Delete confirmed for rule: \(rule.id) '\(rule.displayTitle)'")
                    Task { await kanataManager.removeCustomRule(rule.id) }
                } else {
                    AppLogger.shared.log("⚠️ [CustomRulesView] Delete confirmed but pendingDeleteRule was nil!")
                }
                pendingDeleteRule = nil
            }
        } message: {
            Text("This removes the rule from Custom Rules but leaves preset collections untouched.")
        }
        .settingsBackground()
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
                            .foregroundStyle(.secondary)

                        // Show app icon + name for launch actions, otherwise show key chip
                        if let appId = appLaunchIdentifier {
                            AppLaunchChip(appIdentifier: appId)
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
                            .foregroundStyle(.secondary)
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

                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .padding(.leading, 4)
                }
                .menuStyle(.borderlessButton)
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
                    ForEach(behaviorItems.indices, id: \.self) { itemIndex in
                        let item = behaviorItems[itemIndex]
                        if itemIndex > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(Color.secondary.opacity(0.5))
                        }
                        behaviorItem(icon: item.0, label: item.1, key: item.2)
                    }
                }
            }
        }
        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            appName = name
        } else {
            // Use filename without extension
            appName = url.deletingPathExtension().lastPathComponent
        }
    }
}
