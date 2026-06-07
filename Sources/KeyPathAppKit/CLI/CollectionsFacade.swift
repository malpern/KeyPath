import Foundation
import KeyPathCore

public struct CollectionsFacade: Sendable {
    public init() {}

    // MARK: - Collection CRUD

    public func loadRuleCollections() async -> [CLIRuleCollection] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        return collections.map { CLIRuleCollection(from: $0) }
    }

    public func enableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        if let owner = await InstalledPackTracker.shared.packManagingCollection(collections[index].id) {
            throw PackManagedCollectionError(
                collectionName: collections[index].name,
                packName: owner.packName,
                packID: owner.packID
            )
        }
        collections[index].isEnabled = true
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    public func disableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        if let owner = await InstalledPackTracker.shared.packManagingCollection(collections[index].id) {
            throw PackManagedCollectionError(
                collectionName: collections[index].name,
                packName: owner.packName,
                packID: owner.packID
            )
        }
        collections[index].isEnabled = false
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    public func showCollection(nameOrId: String) async throws -> CLIRuleCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIRuleCollection(from: collections[index])
    }

    public func showCollectionDetail(nameOrId: String) async throws -> CLIRuleCollectionDetail? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIRuleCollectionDetail(from: collections[index])
    }

    public func createCollection(name: String, category: String?, summary: String?) async throws -> CLIRuleCollection {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let cat: RuleCollectionCategory = if let category {
            RuleCollectionCategory(rawValue: category) ?? .custom
        } else {
            .custom
        }
        let collection = RuleCollection(
            name: name,
            summary: summary ?? "",
            category: cat,
            mappings: []
        )
        collections.append(collection)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: collection)
    }

    public func renameCollection(nameOrId: String, newName: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        let oldName = collections[index].name
        collections[index].name = newName
        try await RuleCollectionStore.shared.saveCollections(collections)
        return oldName
    }

    public func deleteCollection(nameOrId: String) async throws -> Bool {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return false
        }
        collections.remove(at: index)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return true
    }

    public func duplicateCollection(nameOrId: String, newName: String?) async throws -> CLIRuleCollection? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        var duplicate = collections[index]
        duplicate = RuleCollection(
            name: newName ?? "\(duplicate.name) (Copy)",
            summary: duplicate.summary,
            category: duplicate.category,
            mappings: duplicate.mappings,
            isEnabled: false
        )
        collections.insert(duplicate, at: index + 1)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: duplicate)
    }

    public func reorderCollection(nameOrId: String, position: Int) async throws -> Bool {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return false
        }
        let collection = collections.remove(at: index)
        let targetIndex = min(max(0, position), collections.count)
        collections.insert(collection, at: targetIndex)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return true
    }

    // MARK: - Export / Import

    public func exportCollection(nameOrId: String) async throws -> CLIExportedCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIExportedCollection(from: collections[index])
    }

    public func exportAllCollections() async -> [CLIExportedCollection] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        return collections.map { CLIExportedCollection(from: $0) }
    }

    public func importCollection(_ exported: CLIExportedCollection, onConflict: CLIConflictStrategy = .fail) async throws -> CLIRuleCollection {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let existingIndex = collections.firstIndex(where: { $0.name == exported.name })

        if let existingIndex {
            switch onConflict {
            case .fail:
                throw AmbiguousCollectionMatch(
                    query: exported.name,
                    matches: [.init(name: collections[existingIndex].name, id: collections[existingIndex].id.uuidString)],
                    hint: "Use --on-conflict=replace to overwrite or --on-conflict=skip to no-op"
                )
            case .skip:
                return CLIRuleCollection(from: collections[existingIndex])
            case .replace, .merge:
                collections.remove(at: existingIndex)
            }
        }

        let collection = exported.toRuleCollection()
        collections.append(collection)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: collection)
    }

    // MARK: - Karabiner Import

    public func importFromKarabiner(data: Data, collectionName: String?, profileIndex: Int?) throws -> CLIKarabinerImportResult {
        let service = KarabinerConverterService()

        let result: KarabinerConversionResult
        do {
            result = try service.convert(data: data, profileIndex: profileIndex)
        } catch {
            if let complexResult = try? convertComplexModsFile(data: data, service: service) {
                result = complexResult
            } else {
                throw error
            }
        }

        let exportedCollections: [CLIExportedCollection]
        if let name = collectionName {
            let allMappings = result.collections.flatMap(\.mappings)
            let merged = RuleCollection(
                name: name,
                summary: "Imported from Karabiner profile: \(result.profileName)",
                category: .custom,
                mappings: allMappings
            )
            exportedCollections = [CLIExportedCollection(from: merged)]
        } else {
            exportedCollections = result.collections.map { CLIExportedCollection(from: $0) }
        }

        var warnings = result.warnings

        if !result.appKeymaps.isEmpty {
            let count = result.appKeymaps.map(\.overrides.count).reduce(0, +)
            warnings.append("\(count) app-specific override(s) found -- use the GUI to configure app keymaps")
        }

        if !result.launcherMappings.isEmpty {
            warnings.append("\(result.launcherMappings.count) launcher mapping(s) found -- use the GUI to configure launcher shortcuts")
        }

        let skipped = result.skippedRules.map {
            CLISkippedRule(description: $0.description, reason: $0.reason)
        }

        return CLIKarabinerImportResult(
            profileName: result.profileName,
            collections: exportedCollections,
            skippedRules: skipped,
            warnings: warnings
        )
    }

    public func listKarabinerProfiles(data: Data) throws -> [CLIKarabinerProfile] {
        let service = KarabinerConverterService()
        let profiles = try service.getProfiles(from: data)
        return profiles.map {
            CLIKarabinerProfile(name: $0.name, index: $0.index, isSelected: $0.isSelected)
        }
    }

    private func convertComplexModsFile(data: Data, service: KarabinerConverterService) throws -> KarabinerConversionResult {
        struct ComplexModsFile: Decodable {
            let title: String?
            let rules: [KarabinerRule]
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["rules"] != nil
        else {
            throw KarabinerImportError.invalidJSON("Not a recognized Karabiner format")
        }

        let title = json["title"] as? String ?? "Imported Rules"
        let wrapped: [String: Any] = [
            "profiles": [[
                "name": title,
                "selected": true,
                "complex_modifications": json,
            ]],
        ]

        let wrappedData = try JSONSerialization.data(withJSONObject: wrapped)
        return try service.convert(data: wrappedData, profileIndex: 0)
    }

    // MARK: - Layer CRUD

    public func listDefinedLayers() async -> [String] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        var layers = Set<String>()
        layers.insert("base")
        for collection in collections {
            layers.insert(collection.targetLayer.kanataName)
        }
        return layers.sorted()
    }

    public func createLayer(name: String) async throws -> CLIRuleCollection {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let layer = Self.parseLayer(name)
        let collection = RuleCollection(
            name: "\(name) Layer",
            summary: "Rules for the \(name) layer",
            category: .layers,
            mappings: [],
            targetLayer: layer
        )
        collections.append(collection)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: collection)
    }

    public func deleteLayer(name: String) async throws -> Int {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let targetName = Self.parseLayer(name).kanataName
        let before = collections.count
        collections.removeAll { $0.targetLayer.kanataName == targetName }
        let removed = before - collections.count
        if removed > 0 {
            try await RuleCollectionStore.shared.saveCollections(collections)
        }
        return removed
    }

    public func renameLayer(oldName: String, newName: String) async throws -> Int {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let oldLayerName = Self.parseLayer(oldName).kanataName
        let newLayer = Self.parseLayer(newName)
        var updated = 0
        for i in collections.indices {
            if collections[i].targetLayer.kanataName == oldLayerName {
                collections[i].targetLayer = newLayer
                updated += 1
            }
        }
        if updated > 0 {
            try await RuleCollectionStore.shared.saveCollections(collections)
        }
        return updated
    }

    // MARK: - Helpers

    public func resolveCollectionIndex(nameOrId: String, in collections: [RuleCollection]) throws -> Int? {
        if let index = collections.firstIndex(where: { $0.id.uuidString == nameOrId }) {
            return index
        }

        let exactMatches = collections.enumerated().filter {
            $0.element.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 {
            return exactMatches[0].offset
        }
        if exactMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: exactMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) },
                hint: "Multiple collections share this name. Use the ID to disambiguate."
            )
        }

        let substringMatches = collections.enumerated().filter {
            $0.element.name.localizedCaseInsensitiveContains(nameOrId)
        }
        if substringMatches.count == 1 {
            return substringMatches[0].offset
        }
        if substringMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) }
            )
        }

        return nil
    }

    static func parseLayer(_ name: String) -> RuleCollectionLayer {
        switch name.lowercased() {
        case "base": .base
        case "nav", "navigation": .navigation
        default: .custom(name)
        }
    }
}

// MARK: - Collection Types

public struct CLIRuleCollection: Codable, Sendable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
    public let mappingCount: Int
    public let summary: String

    public init(from collection: RuleCollection) {
        id = collection.id.uuidString
        name = collection.name
        isEnabled = collection.isEnabled
        mappingCount = collection.mappings.count
        summary = collection.summary
    }
}

public struct CLIRuleCollectionDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let category: String
    public let displayStyle: String
    public let isEnabled: Bool
    public let isSystemDefault: Bool
    public let owningPackID: String?
    public let icon: String?
    public let tags: [String]
    public let targetLayer: String
    public let activationHint: String?
    public let mappingCount: Int
    public let mappings: [KeyMapping]
    public let configuration: RuleCollectionConfiguration
    public let windowKeyConvention: String?
    public let windowSnappingActivationMode: String?
    public let functionKeyMode: String?

    public init(from collection: RuleCollection) {
        id = collection.id.uuidString
        name = collection.name
        summary = collection.summary
        category = collection.category.rawValue
        displayStyle = collection.displayStyle.rawValue
        isEnabled = collection.isEnabled
        isSystemDefault = collection.isSystemDefault
        owningPackID = collection.owningPackID
        icon = collection.icon
        tags = collection.tags
        targetLayer = collection.targetLayer.kanataName
        activationHint = collection.activationHint
        mappingCount = collection.mappings.count
        mappings = collection.mappings
        configuration = collection.configuration
        windowKeyConvention = collection.windowKeyConvention?.rawValue
        windowSnappingActivationMode = collection.windowSnappingActivationMode?.rawValue
        functionKeyMode = collection.functionKeyMode?.rawValue
    }
}

// MARK: - Export/Import Types

public struct CLIExportedCollection: Codable, Sendable {
    public let name: String
    public let summary: String
    public let category: String
    public let isEnabled: Bool
    public let targetLayer: String
    public let mappings: [CLIExportedMapping]

    public init(from collection: RuleCollection) {
        name = collection.name
        summary = collection.summary
        category = collection.category.rawValue
        isEnabled = collection.isEnabled
        targetLayer = collection.targetLayer.kanataName
        mappings = collection.mappings.map { CLIExportedMapping(from: $0) }
    }

    public func toRuleCollection() -> RuleCollection {
        let cat = RuleCollectionCategory(rawValue: category) ?? .custom
        let layer: RuleCollectionLayer = switch targetLayer {
        case "base": .base
        case "nav": .navigation
        default: .custom(targetLayer)
        }
        return RuleCollection(
            name: name,
            summary: summary,
            category: cat,
            mappings: mappings.map { $0.toKeyMapping() },
            isEnabled: isEnabled,
            targetLayer: layer
        )
    }
}

public struct CLIExportedMapping: Codable, Sendable {
    public let input: String
    public let action: KeyAction
    public let shiftedOutput: String?
    public let behavior: MappingBehavior?

    public init(from mapping: KeyMapping) {
        input = mapping.input
        action = mapping.action
        shiftedOutput = mapping.shiftedOutput
        behavior = mapping.behavior
    }

    public func toKeyMapping() -> KeyMapping {
        KeyMapping(input: input, action: action, shiftedOutput: shiftedOutput, behavior: behavior)
    }
}

// MARK: - Karabiner Import Types

public struct CLIKarabinerImportResult: Codable, Sendable {
    public let profileName: String
    public let collections: [CLIExportedCollection]
    public let skippedRules: [CLISkippedRule]
    public let warnings: [String]
}

public struct CLISkippedRule: Codable, Sendable {
    public let description: String
    public let reason: String
}

public struct CLIKarabinerProfile: Codable, Sendable {
    public let name: String
    public let index: Int
    public let isSelected: Bool
}

// MARK: - Ambiguous Match Error

public struct AmbiguousCollectionMatch: Error, CustomStringConvertible {
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
        var lines = ["Found \(matches.count) collections matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}
