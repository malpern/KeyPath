import Foundation
import KeyPathCore

// MARK: - Rule Collections

extension CLIFacade {
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
}
