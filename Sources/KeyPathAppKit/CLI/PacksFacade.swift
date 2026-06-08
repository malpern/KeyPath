import Foundation
import KeyPathCore

public struct PacksFacade: Sendable {
    public init() {}

    // MARK: - Pack Management

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

        try validateQuickSettings(settingValues, for: pack)

        if dryRun {
            var warnings: [String] = []
            let installedIDs = await Set(InstalledPackTracker.shared.allInstalled().map(\.packID))
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
        let installedIDs = await Set(InstalledPackTracker.shared.allInstalled().map(\.packID))
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

        try validateQuickSettings(settingValues, for: pack)

        if dryRun {
            let current = await PackInstaller.shared.quickSettings(for: pack.id)
            var merged = current
            for (k, v) in settingValues {
                merged[k] = v
            }
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

    private func validateQuickSettings(_ values: [String: Int], for pack: Pack) throws {
        let settingsByID = Dictionary(uniqueKeysWithValues: pack.quickSettings.map { ($0.id, $0) })
        for (key, value) in values {
            guard let setting = settingsByID[key] else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: key,
                    validKeys: pack.quickSettings.map(\.id)
                )
            }
            try validateQuickSettingValue(value, setting: setting, packName: pack.name)
        }
    }

    private func validateQuickSettingValue(_ value: Int, setting: PackQuickSetting, packName: String) throws {
        switch setting.kind {
        case let .slider(_, min, max, _, unitSuffix):
            guard value >= min, value <= max else {
                throw CLIPackSettingValueError(
                    packName: packName,
                    settingKey: setting.id,
                    value: value,
                    reason: "must be between \(min)\(unitSuffix) and \(max)\(unitSuffix)"
                )
            }
        }
    }
}

// MARK: - Pack CLI Types

public struct CLIPack: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let isInstalled: Bool
    public let installedAt: Date?
}

public struct CLIPackDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let shortDescription: String
    public let longDescription: String
    public let author: String
    public let isInstalled: Bool
    public let installedAt: Date?
    public let visualOnly: Bool
    public let bindings: [CLIPackBinding]
    public let quickSettings: [CLIPackQuickSetting]
    public let dependencies: [CLIPackDep]
    public let quickSettingValues: [String: Int]

    public init(from pack: Pack, record: InstalledPackRecord?) {
        id = pack.id
        name = pack.name
        version = pack.version
        category = pack.category
        tagline = pack.tagline
        shortDescription = pack.shortDescription
        longDescription = pack.longDescription
        author = pack.author
        isInstalled = record != nil
        installedAt = record?.installedAt
        visualOnly = pack.visualOnly
        bindings = pack.bindings.map { CLIPackBinding(input: $0.input, output: $0.output, holdOutput: $0.holdOutput) }
        quickSettings = pack.quickSettings.map { CLIPackQuickSetting(from: $0) }
        dependencies = pack.dependencies.map { CLIPackDep(from: $0) }
        quickSettingValues = record?.quickSettingValues ?? [:]
    }
}

public struct CLIPackBinding: Codable, Sendable {
    public let input: String
    public let output: String
    public let holdOutput: String?
}

public struct CLIPackQuickSetting: Codable, Sendable {
    public let id: String
    public let label: String
    public let defaultValue: Int
    public let min: Int
    public let max: Int
    public let step: Int
    public let unitSuffix: String

    public init(from setting: PackQuickSetting) {
        id = setting.id
        label = setting.label
        switch setting.kind {
        case let .slider(defaultValue, min, max, step, unitSuffix):
            self.defaultValue = defaultValue
            self.min = min
            self.max = max
            self.step = step
            self.unitSuffix = unitSuffix
        }
    }
}

public struct CLIPackDep: Codable, Sendable {
    public let packID: String
    public let kind: String
    public let description: String?

    public init(from dep: PackDependency) {
        packID = dep.packID
        kind = dep.kind.rawValue
        description = dep.description
    }
}

public struct CLIPackInstallResult: Codable, Sendable {
    public let packID: String
    public let packName: String
    public let action: String
    public let warnings: [String]
    public let quickSettingValues: [String: Int]
}

public struct AmbiguousPackMatch: Error, CustomStringConvertible {
    public struct Match: Sendable {
        public let name: String
        public let id: String
    }

    public let query: String
    public let matches: [Match]
    public let hint: String

    public init(query: String, matches: [Match], hint: String = "Use the full name or ID to disambiguate.") {
        self.query = query
        self.matches = matches
        self.hint = hint
    }

    public var description: String {
        var lines = ["Found \(matches.count) packs matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}

public struct CLIPackNotFound: Error, CustomStringConvertible {
    public let query: String
    public var description: String {
        "No pack found matching \"\(query)\""
    }
}

public struct CLIPackSettingError: Error, CustomStringConvertible {
    public let packName: String
    public let settingKey: String
    public let validKeys: [String]
    public var description: String {
        if validKeys.isEmpty {
            return "Pack '\(packName)' has no quick settings, but --setting \(settingKey) was provided"
        }
        return "Unknown setting '\(settingKey)' for pack '\(packName)'. Valid keys: \(validKeys.joined(separator: ", "))"
    }
}

public struct CLIPackSettingValueError: Error, CustomStringConvertible {
    public let packName: String
    public let settingKey: String
    public let value: Int
    public let reason: String

    public var description: String {
        "Invalid value \(value) for setting '\(settingKey)' on pack '\(packName)': \(reason)"
    }
}

public struct PackManagedCollectionError: Error, CustomStringConvertible {
    public let collectionName: String
    public let packName: String
    public let packID: String
    public var description: String {
        let slug = packName.lowercased().replacingOccurrences(of: " ", with: "-")
        return "'\(collectionName)' is managed by pack '\(packName)'. Run 'keypath pack uninstall \(slug)' to release it."
    }
}
