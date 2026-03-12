import Foundation
import KeyPathCore

/// Persisted selection state for a single device.
struct DeviceSelection: Codable, Sendable {
    let hash: String
    let productKey: String
    var isEnabled: Bool
    var lastSeen: Date
}

/// Thread-safe synchronous cache for device selections, used by the config generator.
/// The generator runs synchronously and cannot await actor methods, so it reads from this cache.
final class DeviceSelectionCache: @unchecked Sendable {
    static let shared = DeviceSelectionCache()

    private let lock = NSLock()
    private var selections: [String: DeviceSelection] = [:]

    /// Update the cache with the latest selections from the store.
    func update(_ newSelections: [DeviceSelection]) {
        lock.lock()
        defer { lock.unlock() }
        selections = Dictionary(newSelections.map { ($0.hash, $0) }, uniquingKeysWith: { _, new in new })
    }

    /// Check if a device hash is enabled. Devices not in the cache default to enabled.
    func isEnabled(hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return selections[hash]?.isEnabled ?? true
    }

    /// Get all cached selections.
    func allSelections() -> [DeviceSelection] {
        lock.lock()
        defer { lock.unlock() }
        return Array(selections.values)
    }
}

/// Actor-based store for device selection persistence.
/// File: `~/.config/keypath/DeviceSelection.json`
actor DeviceSelectionStore {
    static let shared = DeviceSelectionStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = Foundation.FileManager()) {
        self.fileManager = fileManager
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("DeviceSelection.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadSelections() -> [DeviceSelection] {
        AppLogger.shared.log("📂 [DeviceSelectionStore] loadSelections from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [DeviceSelectionStore] File does not exist, returning []")
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let selections = try decoder.decode([DeviceSelection].self, from: data)
            AppLogger.shared.log("📂 [DeviceSelectionStore] Loaded \(selections.count) device selection(s)")
            return selections
        } catch {
            AppLogger.shared.log("⚠️ [DeviceSelectionStore] Failed to load selections: \(error)")
            return []
        }
    }

    func saveSelections(_ selections: [DeviceSelection]) throws {
        AppLogger.shared.log("💾 [DeviceSelectionStore] saveSelections: \(selections.count) device(s) to \(fileURL.path)")
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(selections)
        try data.write(to: fileURL, options: .atomic)
        // Sync to cache for synchronous config generator reads
        DeviceSelectionCache.shared.update(selections)
        AppLogger.shared.log("💾 [DeviceSelectionStore] Saved \(data.count) bytes")
    }

    /// Load selections and sync to cache. Call at startup.
    func syncToCache() {
        let selections = loadSelections()
        DeviceSelectionCache.shared.update(selections)
    }
}

#if DEBUG
    extension DeviceSelectionStore {
        nonisolated static func testStore(at url: URL) -> DeviceSelectionStore {
            DeviceSelectionStore(fileURL: url)
        }
    }
#endif
