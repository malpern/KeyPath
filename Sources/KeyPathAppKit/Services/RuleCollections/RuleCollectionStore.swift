import Foundation
import KeyPathCore

/// Lightweight persistence layer for rule collections.
/// Stores user-defined collections alongside the Kanata config inside the ~/.config/keypath directory.
actor RuleCollectionStore {
    static let shared = RuleCollectionStore()
    static let currentSchemaVersion = 1

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager
    private let catalog: RuleCollectionCatalog

    struct LoadResult: Sendable {
        var collections: [RuleCollection]
        var failedCollectionNames: [String]
        var wasFullReset: Bool
        var backupPath: String?
    }

    private struct VersionedCollections: Codable {
        var schemaVersion: Int
        var collections: [RuleCollection]
    }

    private struct PartialCollection: Decodable {
        var id: UUID?
        var name: String?

        private enum CodingKeys: String, CodingKey {
            case id, name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(UUID.self, forKey: .id)
            name = try? container.decode(String.self, forKey: .name)
        }
    }

    private struct VersionedPartial: Decodable {
        var schemaVersion: Int?
        var collections: [FailableDecodable<RuleCollection>]
    }

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = Foundation.FileManager(),
        catalog: RuleCollectionCatalog = RuleCollectionCatalog()
    ) {
        self.fileManager = fileManager
        self.catalog = catalog
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("RuleCollections.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func loadCollections() -> [RuleCollection] {
        loadCollectionsDetailed().collections
    }

    func loadCollectionsDetailed() -> LoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LoadResult(collections: catalog.defaultCollections(), failedCollectionNames: [], wasFullReset: false)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            AppLogger.shared.log(
                "⚠️ [RuleCollectionStore] Failed to read file: \(error). Falling back to defaults."
            )
            return LoadResult(collections: catalog.defaultCollections(), failedCollectionNames: [], wasFullReset: true)
        }

        // Fast path: try atomic decode of all collections
        if let result = try? decodeAllCollections(from: data) {
            return LoadResult(collections: result, failedCollectionNames: [], wasFullReset: false)
        }

        // Slow path: per-collection resilient decode
        AppLogger.shared.log("⚠️ [RuleCollectionStore] Atomic decode failed, trying per-collection recovery...")
        let backupPath = backupBeforeFallback()
        var result = decodeCollectionsResiliently(from: data)
        result.backupPath = backupPath
        return result
    }

    private func decodeAllCollections(from data: Data) throws -> [RuleCollection] {
        let collections: [RuleCollection] = if let versioned = try? decoder.decode(VersionedCollections.self, from: data) {
            versioned.collections
        } else {
            try decoder.decode([RuleCollection].self, from: data)
        }
        return upgradeAndMergeDefaults(collections)
    }

    private func decodeCollectionsResiliently(from data: Data) -> LoadResult {
        var recovered: [RuleCollection] = []
        var failedNames: [String] = []

        // Try versioned wrapper with per-element failable decode
        let elements: [FailableDecodable<RuleCollection>]
        if let versioned = try? decoder.decode(VersionedPartial.self, from: data) {
            elements = versioned.collections
        } else if let plain = try? decoder.decode([FailableDecodable<RuleCollection>].self, from: data) {
            elements = plain
        } else {
            // JSON structure itself is broken — try to extract names for reporting
            let partialNames = extractPartialNames(from: data)
            AppLogger.shared.log(
                "⚠️ [RuleCollectionStore] JSON structure unreadable. Full reset to defaults."
            )
            return LoadResult(
                collections: catalog.defaultCollections(),
                failedCollectionNames: partialNames,
                wasFullReset: true
            )
        }

        // Pair each failable result with a partial decode for the name
        let partials = (try? decoder.decode(VersionedPartialNames.self, from: data))?.collections
            ?? (try? decoder.decode([PartialCollection].self, from: data))
            ?? []

        for (index, element) in elements.enumerated() {
            if let collection = element.value {
                recovered.append(collection)
            } else {
                let name = (index < partials.count ? partials[index].name : nil) ?? "Unknown (#\(index + 1))"
                failedNames.append(name)
                AppLogger.shared.log(
                    "⚠️ [RuleCollectionStore] Failed to decode collection '\(name)' — using catalog default"
                )
            }
        }

        let upgraded = upgradeAndMergeDefaults(recovered)
        return LoadResult(collections: upgraded, failedCollectionNames: failedNames, wasFullReset: false)
    }

    private func extractPartialNames(from data: Data) -> [String] {
        if let versioned = try? decoder.decode(VersionedPartialNames.self, from: data) {
            return versioned.collections.compactMap(\.name)
        }
        if let partials = try? decoder.decode([PartialCollection].self, from: data) {
            return partials.compactMap(\.name)
        }
        return []
    }

    private func upgradeAndMergeDefaults(_ collections: [RuleCollection]) -> [RuleCollection] {
        var upgraded = collections
            .filter { $0.id != RuleCollectionIdentifier.typingSounds }
            .map { catalog.upgradedCollection(from: $0) }

        let defaults = catalog.defaultCollections()
        for collection in defaults where !upgraded.contains(where: { $0.id == collection.id }) {
            upgraded.append(collection)
        }
        return upgraded
    }

    @discardableResult
    private func backupBeforeFallback() -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let backupDir = fileURL.deletingLastPathComponent().appendingPathComponent(".backups")
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupDir.appendingPathComponent("RuleCollections-\(timestamp).json")

        do {
            try fileManager.copyItem(at: fileURL, to: backupURL)
            AppLogger.shared.log("📦 [RuleCollectionStore] Backed up config to \(backupURL.lastPathComponent)")
            return backupURL.path
        } catch {
            AppLogger.shared.log("⚠️ [RuleCollectionStore] Failed to backup: \(error)")
            return nil
        }
    }

    func saveCollections(_ collections: [RuleCollection]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let versioned = VersionedCollections(
            schemaVersion: Self.currentSchemaVersion,
            collections: collections
        )
        let data = try encoder.encode(versioned)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Helper Types

    private struct VersionedPartialNames: Decodable {
        var collections: [PartialCollection]
    }
}

/// Wraps a Decodable type so that individual elements in an array can fail without
/// breaking the entire array decode.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

#if DEBUG
    extension RuleCollectionStore {
        /// Convenience initializer used by tests so they can provide a sandboxed location.
        nonisolated static func testStore(at url: URL) -> RuleCollectionStore {
            RuleCollectionStore(fileURL: url)
        }
    }
#endif
