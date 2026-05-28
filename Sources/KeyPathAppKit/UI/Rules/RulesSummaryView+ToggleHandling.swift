import KeyPathCore
import SwiftUI

// MARK: - Dependency-Aware Toggle Handling

extension RulesTabView {
    func handleCollectionToggle(collection: RuleCollection, isOn: Bool) {
        AppLogger.shared.log("🎚️ [Rules] handleCollectionToggle: '\(collection.name)' isOn=\(isOn) pack=\(packForCollection(collection)?.name ?? "nil") collectionID=\(collection.id)")
        if let owner = collectionOwnershipMap[collection.id] {
            settingsToastManager.showError(
                "Part of \(owner.packName) — turn off the pack to change this"
            )
            pendingToggles.removeValue(forKey: collection.id)
            return
        }

        let pack = packForCollection(collection)

        if isOn, let pack {
            let unmet = PackDependencyChecker.unmetRequirements(
                for: pack.id,
                enabledCollections: kanataManager.ruleCollections,
                installedPackIDs: []
            )

            if !unmet.isEmpty {
                let allAutoResolvable = unmet.allSatisfy { $0.reason == .notEnabled }

                if allAutoResolvable {
                    pendingToggles[collection.id] = true
                    Task {
                        for dep in unmet {
                            if let depPack = PackRegistry.pack(id: dep.dependency.packID) {
                                await toggleViaPack(depPack, isOn: true)
                            }
                        }
                        await toggleViaPack(pack, isOn: true)
                        pendingToggles.removeValue(forKey: collection.id)
                        refreshUnmetDependencies()
                        let depNames = unmet.map { PackRegistry.pack(id: $0.dependency.packID)?.name ?? $0.dependency.packID }
                        settingsToastManager.showSuccess("Also enabled \(depNames.joined(separator: ", "))")
                    }
                    return
                } else {
                    pendingEnablePack = pack
                    pendingEnableUnmetDeps = unmet
                    return
                }
            }
        }

        if !isOn, let pack {
            let dependents = PackDependencyChecker.dependents(
                of: pack.id,
                enabledCollections: kanataManager.ruleCollections,
                installedPackIDs: []
            )

            if !dependents.isEmpty {
                pendingDisablePack = pack
                pendingDisableDependents = dependents
                return
            }
        }

        pendingToggles[collection.id] = isOn
        if !isOn {
            pendingSelections.removeValue(forKey: collection.id)
        }
        Task {
            if let pack {
                AppLogger.shared.log("🎚️ [Rules] toggleViaPack path for '\(pack.name)' (collectionID=\(collection.id), packAssoc=\(pack.associatedCollectionID?.uuidString ?? "nil"))")
                await toggleViaPack(pack, isOn: isOn)
            } else {
                AppLogger.shared.log("🎚️ [Rules] direct toggleRuleCollection for '\(collection.name)' (id=\(collection.id))")
                await kanataManager.toggleRuleCollection(collection.id, enabled: isOn)
            }
            pendingToggles.removeValue(forKey: collection.id)
            refreshUnmetDependencies()
        }
    }

    func toggleViaPack(_ pack: Pack, isOn: Bool) async {
        let manager = kanataManager.underlyingManager.ruleCollectionsManager
        do {
            if isOn {
                _ = try await PackInstaller.shared.install(pack, manager: manager)
            } else {
                try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)
            }
            kanataManager.underlyingManager.notifyStateChanged()
        } catch {
            AppLogger.shared.log("⚠️ [Rules] Pack toggle failed for '\(pack.name)': \(error.localizedDescription)")
            await kanataManager.toggleRuleCollection(
                pack.associatedCollectionID ?? UUID(),
                enabled: isOn
            )
        }
    }

    func refreshCollectionOwnership() async {
        var map: [UUID: (packID: String, packName: String)] = [:]
        for collection in allCollections {
            if let owner = await InstalledPackTracker.shared.packManagingCollection(collection.id) {
                let pack = PackRegistry.pack(id: owner.packID)
                let isSelfManaged = pack?.associatedCollectionID == collection.id
                if !isSelfManaged {
                    map[collection.id] = (packID: owner.packID, packName: owner.packName)
                }
            }
        }
        collectionOwnershipMap = map
    }

    func refreshUnmetDependencies() {
        unmetDependencyMap = PackDependencyChecker.allUnmetRequirements(
            enabledCollections: kanataManager.ruleCollections,
            installedPackIDs: []
        )
    }

    func availableHomeRowLayers(for _: RuleCollection) -> [String] {
        let existingLayerNames = Set(
            kanataManager.ruleCollections
                .map(\.targetLayer.kanataName)
                .filter { $0.lowercased() != "base" }
        )
        return Array(existingLayerNames).sorted()
    }
}
