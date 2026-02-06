import AppKit
import KeyPathCore
import SwiftUI

struct CustomRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var pendingDeleteRule: CustomRule?
    @State private var appKeymaps: [AppKeymap] = []
    @State private var pendingDeleteAppRule: (keymap: AppKeymap, override: AppKeyOverride)?
    @State private var newInputKey: String = ""
    @State private var newOutputKey: String = ""
    @State private var newTitle: String = ""
    @State private var newNotes: String = ""
    @State private var inlineError: String?

    private static let inlineKeyOptions: [String] = {
        let letters = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
        let numbers = "0123456789".map { String($0) }
        let base = CustomRuleValidator.commonKeys + letters + numbers
        return Array(Set(base)).sorted()
    }()

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
            CustomRulesToolbarView()
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            Divider()

            CustomRulesInlineEditor(
                inputKey: $newInputKey,
                outputKey: $newOutputKey,
                title: $newTitle,
                notes: $newNotes,
                inlineError: $inlineError,
                keyOptions: Self.inlineKeyOptions,
                onAddRule: addInlineRule
            )
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider()

            CustomRulesListView(
                rules: sortedRules,
                appKeymaps: appKeymaps,
                onToggleRule: { rule, isOn in
                    _ = Task { await kanataManager.toggleCustomRule(rule.id, enabled: isOn) }
                },
                onEditRule: openRuleInDrawer,
                onDeleteRule: { rule in
                    pendingDeleteRule = rule
                },
                onDeleteAppRule: { keymap, override in
                    pendingDeleteAppRule = (keymap, override)
                }
            )
        }
        .onAppear {
            loadAppKeymaps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appKeymapsDidChange)) { _ in
            loadAppKeymaps()
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

    private func addInlineRule() {
        inlineError = nil
        let rule = Self.makeInlineRule(
            input: newInputKey,
            output: newOutputKey,
            title: newTitle,
            notes: newNotes
        )

        let errors = CustomRuleValidator.validate(rule, existingRules: kanataManager.customRules)
        if let first = errors.first {
            inlineError = first.errorDescription
            return
        }

        Task {
            let saved = await kanataManager.underlyingManager.saveCustomRule(rule)
            await MainActor.run {
                if saved {
                    newInputKey = ""
                    newOutputKey = ""
                    newTitle = ""
                    newNotes = ""
                } else {
                    inlineError = "Rule save failed"
                }
            }
        }
    }

    static func makeInlineRule(
        input: String,
        output: String,
        title: String,
        notes: String
    ) -> CustomRule {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return CustomRule(
            title: trimmedTitle,
            input: trimmedInput,
            output: trimmedOutput,
            isEnabled: true,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
    }

    private func openRuleInDrawer(_ rule: CustomRule) {
        NotificationCenter.default.post(
            name: .openOverlayWithMapperPreset,
            object: nil,
            userInfo: ["inputKey": rule.input, "outputKey": rule.output]
        )
    }

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
