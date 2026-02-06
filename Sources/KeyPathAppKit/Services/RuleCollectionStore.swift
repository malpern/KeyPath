import Foundation
import KeyPathCore

/// Lightweight persistence layer for rule collections.
/// Stores user-defined collections alongside the Kanata config inside the ~/.config/keypath directory.
actor RuleCollectionStore {
    static let shared = RuleCollectionStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager
    private let catalog: RuleCollectionCatalog

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
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
            let collections = try decoder.decode([RuleCollection].self, from: data)
            var upgraded = collections
                .filter { $0.id != RuleCollectionIdentifier.typingSounds }
                .map { catalog.upgradedCollection(from: $0) }

            // Ensure any newly added catalog defaults are present even if the persisted
            // file was written before they existed (or after a reset that wrote a subset).
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
        let data = try encoder.encode(collections)
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
