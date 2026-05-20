import Foundation
import KeyPathCore

// MARK: - Pack Management

extension CLIFacade {
    public func listPacks() async -> [CLIPack] {
        let allPacks = PackRegistry.starterKit
        let installed = await InstalledPackTracker.shared.allInstalled()
        let installedMap = Dictionary(uniqueKeysWithValues: installed.map { ($0.packID, $0) })

        return allPacks.map { pack in
            let record = installedMap[pack.id]
            return CLIPack(
                id: pack.id,
                name: pack.name,
                version: pack.version,
                category: pack.category,
                tagline: pack.tagline,
                isInstalled: record != nil,
                installedAt: record?.installedAt
            )
        }
    }

    public func showPack(nameOrId: String) async throws -> CLIPackDetail? {
        guard let pack = try resolvePack(nameOrId: nameOrId) else { return nil }
        let record = await InstalledPackTracker.shared.record(for: pack.id)
        return CLIPackDetail(from: pack, record: record)
    }

    @MainActor
    public func installPack(
        nameOrId: String,
        settingValues: [String: Int] = [:],
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        guard let pack = try resolvePack(nameOrId: nameOrId) else {
            throw CLIPackNotFound(query: nameOrId)
        }

        let isAlready = await InstalledPackTracker.shared.isInstalled(packID: pack.id)
        if isAlready {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "already-installed",
                warnings: [],
                quickSettingValues: [:]
            )
        }

        for key in settingValues.keys {
            guard pack.quickSettings.contains(where: { $0.id == key }) else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: key,
                    validKeys: pack.quickSettings.map(\.id)
                )
            }
        }

        if dryRun {
            var warnings: [String] = []
            let installedIDs = Set(await InstalledPackTracker.shared.allInstalled().map(\.packID))
            let suggestions = PackDependencyChecker.suggestions(for: pack.id, installedPackIDs: installedIDs)
            for dep in suggestions {
                let depName = PackRegistry.pack(id: dep.packID)?.name ?? dep.packID
                warnings.append("Enhanced by '\(depName)' — install it for best results")
            }
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "would-install",
                warnings: warnings,
                quickSettingValues: settingValues
            )
        }

        let manager = await makePackManager()
        let record = try await PackInstaller.shared.install(
            pack,
            quickSettingValues: settingValues,
            manager: manager
        )

        var warnings: [String] = []
        let installedIDs = Set(await InstalledPackTracker.shared.allInstalled().map(\.packID))
        let suggestions = PackDependencyChecker.suggestions(for: pack.id, installedPackIDs: installedIDs)
        for dep in suggestions {
            let depName = PackRegistry.pack(id: dep.packID)?.name ?? dep.packID
            warnings.append("Enhanced by '\(depName)' — install it for best results")
        }

        return CLIPackInstallResult(
            packID: pack.id,
            packName: pack.name,
            action: "installed",
            warnings: warnings,
            quickSettingValues: record.quickSettingValues
        )
    }

    @MainActor
    public func uninstallPack(
        nameOrId: String,
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        guard let pack = try resolvePack(nameOrId: nameOrId) else {
            throw CLIPackNotFound(query: nameOrId)
        }

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: pack.id)
        guard isInstalled else {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "not-installed",
                warnings: [],
                quickSettingValues: [:]
            )
        }

        if dryRun {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "would-uninstall",
                warnings: [],
                quickSettingValues: [:]
            )
        }

        let manager = await makePackManager()
        try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)

        return CLIPackInstallResult(
            packID: pack.id,
            packName: pack.name,
            action: "uninstalled",
            warnings: [],
            quickSettingValues: [:]
        )
    }

    @MainActor
    public func configurePack(
        nameOrId: String,
        settingValues: [String: Int],
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        guard let pack = try resolvePack(nameOrId: nameOrId) else {
            throw CLIPackNotFound(query: nameOrId)
        }

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: pack.id)
        guard isInstalled else {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "not-installed",
                warnings: ["Pack must be installed before configuring settings."],
                quickSettingValues: [:]
            )
        }

        guard !pack.quickSettings.isEmpty else {
            throw CLIPackSettingError(
                packName: pack.name,
                settingKey: settingValues.keys.first ?? "",
                validKeys: []
            )
        }

        for key in settingValues.keys {
            guard pack.quickSettings.contains(where: { $0.id == key }) else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: key,
                    validKeys: pack.quickSettings.map(\.id)
                )
            }
        }

        if dryRun {
            let current = await PackInstaller.shared.quickSettings(for: pack.id)
            var merged = current
            for (k, v) in settingValues { merged[k] = v }
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "would-configure",
                warnings: [],
                quickSettingValues: merged
            )
        }

        let manager = await makePackManager()
        try await PackInstaller.shared.updateQuickSettings(
            packID: pack.id,
            newValues: settingValues,
            manager: manager
        )

        let updatedSettings = await PackInstaller.shared.quickSettings(for: pack.id)

        return CLIPackInstallResult(
            packID: pack.id,
            packName: pack.name,
            action: "configured",
            warnings: [],
            quickSettingValues: updatedSettings
        )
    }

    func resolvePack(nameOrId: String) throws -> Pack? {
        let allPacks = PackRegistry.starterKit

        if let pack = allPacks.first(where: { $0.id == nameOrId }) {
            return pack
        }

        let prefix = "com.keypath.pack."
        let slugMatches = allPacks.filter { pack in
            guard pack.id.hasPrefix(prefix) else { return false }
            let slug = String(pack.id.dropFirst(prefix.count))
            return slug.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if slugMatches.count == 1 { return slugMatches[0] }
        if slugMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: slugMatches.map { .init(name: $0.name, id: $0.id) },
                hint: "Multiple packs match this slug. Use the full ID to disambiguate."
            )
        }

        let exactMatches = allPacks.filter {
            $0.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 { return exactMatches[0] }
        if exactMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: exactMatches.map { .init(name: $0.name, id: $0.id) },
                hint: "Multiple packs share this name. Use the ID to disambiguate."
            )
        }

        let substringMatches = allPacks.filter {
            $0.name.localizedCaseInsensitiveContains(nameOrId)
        }
        if substringMatches.count == 1 { return substringMatches[0] }
        if substringMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.name, id: $0.id) }
            )
        }

        return nil
    }

    @MainActor
    func makePackManager() async -> RuleCollectionsManager {
        let configService = ConfigurationService()
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: configService
        )
        let collections = await RuleCollectionStore.shared.loadCollections()
        let customRules = await CustomRulesStore.shared.loadRules()
        manager.ruleCollections = RuleCollectionDeduplicator.dedupe(collections)
        manager.customRules = customRules
        return manager
    }
}
