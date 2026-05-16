import Foundation
import KeyPathCore
import SwiftUI

extension OverlayInspectorPanel {
    // MARK: - Custom Rules Content

    var customRulesContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Rule cards
                LazyVStack(spacing: 10) {
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
                                onSelectSection(.mapper)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: DispatchWorkItem {
                                    Foundation.NotificationCenter.default.post(
                                        name: Foundation.Notification.Name.mapperSetAppCondition,
                                        object: nil,
                                        userInfo: ["bundleId": "", "displayName": ""]
                                    )
                                })
                            },
                            onRuleHover: onRuleHover
                        )
                    }

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

                // Action buttons below the rules list
                HStack(spacing: 2) {
                    Spacer()
                    Button { onResetAllRules?() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .accessibilityIdentifier("custom-rules-reset-button")
                    .accessibilityLabel("Reset all custom rules")
                    .help("Reset all custom rules")

                    Button { onCreateNewAppRule?() } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .accessibilityIdentifier("custom-rules-new-button")
                    .accessibilityLabel("Create new custom rule")
                    .help("Create new custom rule")
                }
                .padding(.top, 8)

                // Active chord groups
                activeChordsCard
                    .padding(.top, 12)

                // Active rules + merchandising
                activeRulesFooter
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Active Rules Footer

    private var enabledUserPacks: [Pack] {
        guard let vm = kanataViewModel else { return [] }
        let enabledIDs = Set(vm.ruleCollections.filter(\.isEnabled).map(\.id))
        return PackRegistry.starterKit.filter { pack in
            guard let collectionID = pack.associatedCollectionID else { return false }
            guard !pack.visualOnly else { return false }
            return enabledIDs.contains(collectionID)
        }.filter { pack in
            let systemIDs: Set<String> = ["com.keypath.pack.leader-key"]
            return !systemIDs.contains(pack.id)
        }
    }

    @ViewBuilder
    private var activeRulesFooter: some View {
        let packs = enabledUserPacks
        let remaining = PackRegistry.starterKit.count - packs.count

        VStack(alignment: .leading, spacing: 6) {
            if !packs.isEmpty {
                Text("Active Rules")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                FlowLayout(spacing: 4) {
                    ForEach(packs) { pack in
                        Button {
                            if let vm = kanataViewModel {
                                PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: vm, fromOverlay: true)
                            }
                        } label: {
                            Text(pack.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }
            }

            if packs.count < 6, remaining > 0 {
                Spacer()
                    .frame(height: 8)

                Button {
                    openPreferencesTab(.openSettingsRules)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .openSettingsRules, object: nil)
                    }
                } label: {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                            .padding(.top, 4)

                        VStack(spacing: 6) {
                            Text("Vim nav, home row mods, window snapping")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)

                            Text("and \(remaining - 3) more ready-made rules →")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .padding(.top, 4)
            } else if remaining > 0 {
                Spacer()
                    .frame(height: 8)

                Button {
                    openPreferencesTab(.openSettingsRules)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .openSettingsRules, object: nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                        Text("Unlock \(remaining) more shortcuts & layers")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Custom Rules Actions

    private func editAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        // Open mapper with this app's context and rule preloaded
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: DispatchWorkItem {
            // Convert input key label to keyCode for proper keyboard highlighting
            let keyCode = LogicalKeymap.keyCode(forQwertyLabel: override.inputKey) ?? 0
            let userInfo: [String: Any] = [
                "keyCode": keyCode,
                "inputKey": override.inputKey,
                "outputKey": override.action.outputString,
                "appBundleId": keymap.mapping.bundleIdentifier,
                "appDisplayName": keymap.mapping.displayName
            ]
            Foundation.NotificationCenter.default.post(
                name: Foundation.Notification.Name.mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        })
    }

    private func addRuleForApp(keymap: AppKeymap) {
        // Open mapper with this app's context (no rule preloaded)
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: DispatchWorkItem {
            // Set the app condition on the mapper view model
            Foundation.NotificationCenter.default.post(
                name: Foundation.Notification.Name.mapperSetAppCondition,
                object: nil,
                userInfo: [
                    "bundleId": keymap.mapping.bundleIdentifier,
                    "displayName": keymap.mapping.displayName
                ]
            )
        })
    }

    private func editGlobalRule(rule: CustomRule) {
        // Open mapper with the global rule preloaded (no app condition)
        onSelectSection(.mapper)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: DispatchWorkItem {
            // Convert input key label to keyCode for proper keyboard highlighting
            let keyCode = LogicalKeymap.keyCode(forQwertyLabel: rule.input) ?? 0
            var userInfo: [String: Any] = [
                "keyCode": keyCode,
                "inputKey": rule.input,
                "outputKey": rule.action.outputString
                // No appBundleId means global/everywhere
            ]
            if let shiftedOutput = rule.shiftedOutput {
                userInfo["shiftedOutputKey"] = shiftedOutput
            }
            Foundation.NotificationCenter.default.post(
                name: Foundation.Notification.Name.mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        })
    }

    // MARK: - Active Chords Card

    private var activeChordGroups: ChordGroupsConfig? {
        guard let vm = kanataViewModel else { return nil }
        let collection = vm.ruleCollections.first {
            $0.id == RuleCollectionIdentifier.chordGroups && $0.isEnabled
        }
        guard let collection else { return nil }
        return collection.configuration.chordGroupsConfig
    }

    @ViewBuilder
    var activeChordsCard: some View {
        if let chordConfig = activeChordGroups, !chordConfig.groups.isEmpty {
            let totalChords = chordConfig.groups.reduce(0) { $0 + $1.chords.count }
            if totalChords > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Active Chords")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()
                        Button {
                            if let vm = kanataViewModel {
                                PackDetailWindowController.shared.showWindow(
                                    pack: PackRegistry.chordGroups,
                                    kanataManager: vm,
                                    fromOverlay: true
                                )
                            }
                        } label: {
                            Text("Edit")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("active-chords-edit-button")
                    }

                    ForEach(chordConfig.groups) { group in
                        ForEach(group.chords) { chord in
                            HStack(spacing: 6) {
                                HStack(spacing: 2) {
                                    ForEach(chord.keys, id: \.self) { key in
                                        Text(key.uppercased())
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                    }
                                }

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)

                                Text(chord.output)
                                    .font(.system(size: 10, design: .monospaced))

                                if let desc = chord.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }
}
