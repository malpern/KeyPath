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

    private struct VersionedCollections: Codable {
        var schemaVersion: Int
        var collections: [RuleCollection]
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
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return catalog.defaultCollections()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let collections: [RuleCollection]
            if let versioned = try? decoder.decode(VersionedCollections.self, from: data) {
                collections = versioned.collections
            } else {
                collections = try decoder.decode([RuleCollection].self, from: data)
            }

            var upgraded = collections
                .filter { $0.id != RuleCollectionIdentifier.typingSounds }
                .map { catalog.upgradedCollection(from: $0) }

            let defaults = catalog.defaultCollections()
            for collection in defaults where !upgraded.contains(where: { $0.id == collection.id }) {
                upgraded.append(collection)
            }

            return upgraded
        } catch {
            AppLogger.shared.log(
                "⚠️ [RuleCollectionStore] Failed to load collections: \(error). Falling back to defaults."
            )
            return catalog.defaultCollections()
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
}

#if DEBUG
    extension RuleCollectionStore {
        /// Convenience initializer used by tests so they can provide a sandboxed location.
        nonisolated static func testStore(at url: URL) -> RuleCollectionStore {
            RuleCollectionStore(fileURL: url)
        }
    }
#endif
