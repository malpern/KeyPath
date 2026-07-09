import KeyPathCore
import KeyPathRulesCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Visual-Only Packs, App Keymaps & Utilities

extension RulesTabView {
    // MARK: - KindaVim Visual-Only Pack

    @ViewBuilder
    var kindaVimRow: some View {
        let pack = PackRegistry.kindaVim
        if !isSearching || pack.name.localizedCaseInsensitiveContains(trimmedSearchQuery)
            || "kindavim".contains(trimmedSearchQuery.lowercased())
        {
            ExpandableKindaVimRow(
                isPackEnabled: isKindaVimInstalled,
                onToggle: { newValue in
                    isKindaVimInstalled = newValue
                    Task {
                        do {
                            if newValue {
                                let record = InstalledPackRecord(
                                    packID: pack.id,
                                    version: pack.version,
                                    installedAt: Date(),
                                    quickSettingValues: [:]
                                )
                                try await InstalledPackTracker.shared.upsert(record)
                            } else {
                                try await InstalledPackTracker.shared.remove(packID: pack.id)
                            }
                        } catch {
                            AppLogger.shared.log("⚠️ [Rules] KindaVim toggle failed: \(error.localizedDescription)")
                            isKindaVimInstalled = !newValue
                            settingsToastManager.showError("Failed to \(newValue ? "enable" : "disable") KindaVim")
                        }
                    }
                },
                onTapRow: {
                    PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager)
                }
            )
        }
    }

    @ViewBuilder
    var keystrokeHistoryRow: some View {
        let pack = PackRegistry.keystrokeHistory
        if !isSearching || pack.name.localizedCaseInsensitiveContains(trimmedSearchQuery)
            || "keystroke history".contains(trimmedSearchQuery.lowercased())
            || "debug".contains(trimmedSearchQuery.lowercased())
        {
            ExpandableKeystrokeHistoryRow(
                isPackEnabled: isKeystrokeHistoryInstalled,
                onToggle: { newValue in
                    isKeystrokeHistoryInstalled = newValue
                    Task {
                        do {
                            if newValue {
                                let record = InstalledPackRecord(
                                    packID: pack.id,
                                    version: pack.version,
                                    installedAt: Date(),
                                    quickSettingValues: [:]
                                )
                                try await InstalledPackTracker.shared.upsert(record)
                                KeystrokeHistoryService.shared.isRecording = true
                            } else {
                                try await InstalledPackTracker.shared.remove(packID: pack.id)
                                KeystrokeHistoryService.shared.isRecording = false
                                KeystrokeHistoryService.shared.clearEvents()
                            }
                        } catch {
                            AppLogger.shared.log("⚠️ [Rules] Keystroke History toggle failed: \(error.localizedDescription)")
                            isKeystrokeHistoryInstalled = !newValue
                        }
                    }
                },
                onTapRow: {
                    PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager)
                }
            )
        }
    }

    // MARK: - App Keymaps Helpers

    func loadAppKeymaps() {
        Task {
            let keymaps = await services.appKeymapStore.loadKeymaps()
            await MainActor.run {
                appKeymaps = keymaps.sorted { $0.mapping.displayName < $1.mapping.displayName }
            }
        }
    }

    func deleteAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        Task {
            var updatedKeymap = keymap
            updatedKeymap.overrides.removeAll { $0.id == override.id }

            do {
                if updatedKeymap.overrides.isEmpty {
                    try await services.appKeymapStore.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                } else {
                    try await services.appKeymapStore.upsertKeymap(updatedKeymap)
                }

                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()
                _ = await kanataManager.underlyingManager.restartKanata(reason: "App rule deleted from Settings")
            } catch {
                AppLogger.shared.log("⚠️ [RulesTabView] Failed to delete app rule: \(error)")
                settingsToastManager.showError("Failed to delete rule: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Search & Utility Helpers

    func collectionMatchesSearch(_ collection: RuleCollection) -> Bool {
        let query = trimmedSearchQuery.lowercased()

        let mappingText = collection.mappings
            .flatMap { mapping in
                [mapping.input, mapping.action.outputString, mapping.shiftedOutput ?? "", mapping.ctrlOutput ?? "", mapping.description ?? ""]
            }
            .joined(separator: " ")

        let searchable = [
            collection.name,
            collection.summary,
            collection.activationHint ?? "",
            collection.tags.joined(separator: " "),
            mappingText
        ]
        .joined(separator: " ")
        .lowercased()

        return searchable.contains(query)
    }

    func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        openFileInPreferredEditor(url)
    }

    func openBackupsFolder() {
        let backupsPath = "\(KeyPathConstants.Config.directory)/.backups"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
    }

    func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.resetToDefaultConfig()
                pendingToggles.removeAll()
                pendingSelections.removeAll()
                stableSortOrder = computeSortOrder()
                settingsToastManager.showSuccess("Configuration reset to default")
            } catch {
                settingsToastManager.showError("Reset failed: \(error.localizedDescription)")
            }
        }
    }
}
