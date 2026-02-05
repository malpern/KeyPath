import KeyPathCore
import SwiftUI

extension OverlayInspectorPanel {
    // MARK: - Custom Rules Content

    @ViewBuilder
    var customRulesContent: some View {
        VStack(spacing: 0) {
            // Scrollable list of rule cards (no header - title removed)
            ScrollView {
                LazyVStack(spacing: 10) {
                    // "Everywhere" section for global rules (only shown when rules exist)
                    if !customRules.isEmpty {
                        GlobalRulesCard(
                            rules: customRules,
                            onEdit: { rule in
                                editGlobalRule(rule: rule)
                            },
                            onDelete: { rule in
                                onDeleteGlobalRule?(rule)
                            },
                            onAddRule: {
                                // Switch to mapper with no app condition (global/everywhere)
                                onSelectSection(.mapper)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NotificationCenter.default.post(
                                        name: .mapperSetAppCondition,
                                        object: nil,
                                        userInfo: ["bundleId": "", "displayName": ""]
                                    )
                                }
                            },
                            onRuleHover: onRuleHover
                        )
                    }

                    // App-specific rules
                    ForEach(appKeymaps) { keymap in
                        AppRuleCard(
                            keymap: keymap,
                            onEdit: { override in
                                editAppRule(keymap: keymap, override: override)
                            },
                            onDelete: { override in
                                onDeleteAppRule?(keymap, override)
                            },
                            onAddRule: {
                                addRuleForApp(keymap: keymap)
                            },
                            onRuleHover: onRuleHover
                        )
                    }
                }
            }

            Spacer()

            // Bottom action bar with reset and add buttons (anchored to bottom right)
            HStack {
                Spacer()
                // Reset all rules button
                Button { onResetAllRules?() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom-rules-reset-button")
                .accessibilityLabel("Reset all custom rules")
                .help("Reset all custom rules")

                // New rule button
                Button { onCreateNewAppRule?() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom-rules-new-button")
                .accessibilityLabel("Create new custom rule")
                .help("Create new custom rule")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Custom Rules Actions

    private func editAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        // Open mapper with this app's context and rule preloaded
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Convert input key label to keyCode for proper keyboard highlighting
            let keyCode = LogicalKeymap.keyCode(forQwertyLabel: override.inputKey) ?? 0
            let userInfo: [String: Any] = [
                "keyCode": keyCode,
                "inputKey": override.inputKey,
                "outputKey": override.outputAction,
                "appBundleId": keymap.mapping.bundleIdentifier,
                "appDisplayName": keymap.mapping.displayName
            ]
            NotificationCenter.default.post(
                name: .mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private func addRuleForApp(keymap: AppKeymap) {
        // Open mapper with this app's context (no rule preloaded)
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set the app condition on the mapper view model
            NotificationCenter.default.post(
                name: .mapperSetAppCondition,
                object: nil,
                userInfo: [
                    "bundleId": keymap.mapping.bundleIdentifier,
                    "displayName": keymap.mapping.displayName
                ]
            )
        }
    }

    private func editGlobalRule(rule: CustomRule) {
        // Open mapper with the global rule preloaded (no app condition)
        onSelectSection(.mapper)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Convert input key label to keyCode for proper keyboard highlighting
            let keyCode = LogicalKeymap.keyCode(forQwertyLabel: rule.input) ?? 0
            let userInfo: [String: Any] = [
                "keyCode": keyCode,
                "inputKey": rule.input,
                "outputKey": rule.output
                // No appBundleId means global/everywhere
            ]
            NotificationCenter.default.post(
                name: .mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
